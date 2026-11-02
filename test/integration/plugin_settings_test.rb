# Rubylode Windmill: the state of a Windmill workspace in Redmine
# Copyright (C) 2026  Nick Gorbikoff
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require_relative "../test_helper"

class RubylodeWindmill::PluginSettingsTest < Redmine::IntegrationTest
  include RubylodeWindmillTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles

  SETTINGS_PATH = "/settings/plugin/redmine_rubylode_windmill".freeze

  GOOD_SETTINGS = {
    "windmill_url" => "https://windmill.example.com", "workspace_id" => "ops",
    "token_environment_variable" => "WINDMILL_MY_TOKEN", "allowed_hosts" => "alias.example.com", "allow_plain_http" => "0",
    "look_back_hours" => "48", "maximum_rows" => "5", "path_prefix" => "f/",
    "watched_schedules" => "Nightly | f/billing/nightly | Copies\nHourly | f/reports/hourly | Refreshes",
    "cache_seconds" => "120", "failure_cache_seconds" => "15", "timeout_seconds" => "3",
    "block_title" => "Automation", "visibility" => "admins"
  }.freeze

  setup do
    Setting.send(:"plugin_#{PLUGIN_ID}=", RedmineRubylodeWindmill::Defaults::SETTINGS.dup)
  end

  def saved
    Setting.send(:"plugin_#{PLUGIN_ID}")
  end

  test "the plugin is registered and its settings page opens with every field" do
    log_user("admin", "admin")
    get SETTINGS_PATH

    assert_response :success
    %w[windmill_url workspace_id token_environment_variable allowed_hosts allow_plain_http look_back_hours maximum_rows
       path_prefix watched_schedules cache_seconds failure_cache_seconds timeout_seconds block_title visibility].each do |field|
      assert_select "[name=?]", "settings[#{field}]"
    end
    assert_select "input[name=?][value=?]", "settings[token_environment_variable]", "WINDMILL_API_TOKEN"
  end

  test "good settings are saved" do
    log_user("admin", "admin")
    post SETTINGS_PATH, params: { settings: GOOD_SETTINGS }

    assert_redirected_to SETTINGS_PATH
    assert_equal "ops", saved["workspace_id"]
    assert_equal "WINDMILL_MY_TOKEN", saved["token_environment_variable"]
    assert_equal 2, RubylodeWindmill::Configuration.current.watched_schedules.size
    assert_equal 48, RubylodeWindmill::Configuration.current.look_back_hours
  end

  test "SECRET_KEY_BASE and DATABASE_PASSWORD are refused at save and nothing is saved" do
    log_user("admin", "admin")
    %w[SECRET_KEY_BASE DATABASE_PASSWORD].each do |name|
      post SETTINGS_PATH, params: { settings: GOOD_SETTINGS.merge("token_environment_variable" => name) }

      assert_response :unprocessable_entity
      assert_select "#errorExplanation li", text: /WINDMILL_/
      assert_equal "", saved["windmill_url"], "nothing was saved for #{name}"
    end
  end

  test "plain http to an outside host is refused at save" do
    log_user("admin", "admin")
    post SETTINGS_PATH, params: { settings: GOOD_SETTINGS.merge("windmill_url" => "http://windmill.internal") }

    assert_response :unprocessable_entity
    assert_select "#errorExplanation li", text: /https/
  end

  test "a bad schedule line shows the line error and keeps what was typed" do
    log_user("admin", "admin")
    typed = "Nightly | f/billing/nightly | Copies\nbroken line"
    post SETTINGS_PATH, params: { settings: GOOD_SETTINGS.merge("watched_schedules" => typed) }

    assert_response :unprocessable_entity
    assert_select "#errorExplanation li", text: /line 2/
    assert_select "textarea[name=?]", "settings[watched_schedules]", text: /broken line/
  end

  test "only administrators may open the settings" do
    log_user("jsmith", "jsmith")
    get SETTINGS_PATH

    assert_response :forbidden
  end
end

class RubylodeWindmill::PluginSettingsHelpTest < Redmine::IntegrationTest
  include RubylodeWindmillTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles

  PATH = "/settings/plugin/redmine_rubylode_windmill".freeze

  setup do
    Setting.send(:"plugin_#{PLUGIN_ID}=", RedmineRubylodeWindmill::Defaults::SETTINGS.dup)
  end

  test "the settings page has the where-to-show fields" do
    log_user("admin", "admin")
    get PATH

    %w[show_on_welcome_page welcome_page_column show_on_my_page show_on_project_overview project_overview_column
       show_on_matching_pages matching_page_paths show_in_top_menu].each do |field|
      assert_select "[name=?]", "settings[#{field}]"
    end
  end

  test "the help explains every place with copy-paste snippets" do
    log_user("admin", "admin")
    get PATH

    assert_select "#rubylode-windmill-help h3", text: "How to show the block on other pages"
    assert_select "#rubylode-windmill-help table tbody tr", 7
    assert_select "#rubylode-windmill-help pre", text: "{{windmill_status}}"
    assert_select "#rubylode-windmill-help pre", text: "{{windmill_status(title=Automation)}}"
    assert_select "#rubylode-windmill-help pre", text: /render partial: "rubylode_windmill\/status"/
    assert_select "#rubylode-windmill-help", text: /welcome text/
    assert_select "#rubylode-windmill-help", text: %r{/windmill_status}
  end

  test "good placement settings are saved and a bad path is refused" do
    log_user("admin", "admin")
    good = RedmineRubylodeWindmill::Defaults::SETTINGS.merge("show_on_matching_pages" => "1", "matching_page_paths" => "/issues\n/projects/*/issues", "welcome_page_column" => "left")
    post PATH, params: { settings: good }
    assert_redirected_to PATH
    assert_equal ["/issues", "/projects/*/issues"], RubylodeWindmill::Configuration.current.matching_page_paths

    post PATH, params: { settings: good.merge("matching_page_paths" => "https://evil.example.com/") }
    assert_response :unprocessable_entity
    assert_select "#errorExplanation li", text: /line 1/
  end
end
