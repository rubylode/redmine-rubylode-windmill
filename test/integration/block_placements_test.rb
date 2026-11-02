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

# Where the block shows is a setting. Every placement uses the same partial, so permission and the cache apply to all.
class RubylodeWindmill::BlockPlacementsTest < Redmine::IntegrationTest
  include RubylodeWindmillTestHelpers

  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles, :issue_statuses, :trackers,
           :projects_trackers, :enumerations, :enabled_modules, :issues, :versions, :wikis, :wiki_pages, :wiki_contents, :news

  BLOCK = ".rubylode-windmill-status".freeze

  setup do
    use_memory_cache
    start_fake_windmill
    Setting.default_language = "en"
  end

  teardown do
    stop_fake_windmill
    restore_cache
  end

  def with_placement(overrides)
    configure_plugin({ "windmill_url" => @fake_windmill.base_url }.merge(overrides))
  end

  test "nothing extra is drawn on a fresh install" do
    log_user("jsmith", "jsmith")
    get "/"
    assert_select BLOCK, 0
    get "/projects/ecookbook"
    assert_select BLOCK, 0
    get "/issues"
    assert_select BLOCK, 0
    assert_select "#top-menu a.rubylode-windmill-status", 0
  end

  test "the welcome page shows it in the chosen column" do
    with_placement("show_on_welcome_page" => "1", "welcome_page_column" => "left")
    log_user("jsmith", "jsmith")
    get "/"
    assert_select ".splitcontentleft #{BLOCK} .rubylode-windmill-status-summary", text: /failing/
    assert_select ".splitcontentright #{BLOCK}", 0

    with_placement("show_on_welcome_page" => "1", "welcome_page_column" => "right")
    get "/"
    assert_select ".splitcontentright #{BLOCK}", 1
  end

  test "the welcome text is rendered with macros, so the macro works there" do
    Setting.welcome_text = "Hello\n\n{{windmill_status}}"
    log_user("jsmith", "jsmith")
    get "/"

    assert_select ".wiki #{BLOCK} .rubylode-windmill-status-summary", text: /failing/
  end

  test "the project Overview page shows it in the chosen column" do
    with_placement("show_on_project_overview" => "1", "project_overview_column" => "left")
    log_user("jsmith", "jsmith")
    get "/projects/ecookbook"

    assert_select ".splitcontentleft #{BLOCK}", 1
    assert_select ".splitcontentright #{BLOCK}", 0
  end

  test "the default My page layout gets the block when asked, a person's own layout is left alone" do
    with_placement("show_on_my_page" => "1")
    log_user("jsmith", "jsmith")
    get "/my/page"
    assert_select "#block-rubylode_windmill_status #{BLOCK}", 1

    reset!
    preference = User.find(2).pref
    preference.my_page_layout = { "top" => ["news"] }
    preference.save!
    log_user("jsmith", "jsmith")
    get "/my/page"
    assert_select "#block-rubylode_windmill_status", 0

    with_placement("show_on_my_page" => "0")
    reset!
    preference.my_page_layout = nil
    preference.save!
    log_user("jsmith", "jsmith")
    get "/my/page"
    assert_select "#block-rubylode_windmill_status", 0
  end

  test "pages whose path is listed get a compact block under the content" do
    with_placement("show_on_matching_pages" => "1", "matching_page_paths" => "/issues\n/projects/*/issues")
    log_user("jsmith", "jsmith")

    get "/issues"
    assert_select "#content #{BLOCK}.is-compact .rubylode-windmill-status-summary", text: /failing/
    assert_select "#content #{BLOCK}.is-compact th", text: "Kind", count: 0
    get "/issues?set_filter=1&status_id=o"
    assert_select "#{BLOCK}.is-compact", 1
    get "/projects/ecookbook/issues"
    assert_select "#{BLOCK}.is-compact", 1
    get "/projects/ecookbook"
    assert_select BLOCK, 0
    get "/news"
    assert_select BLOCK, 0
  end

  test "a wildcard list never puts the block on the settings or administration pages" do
    with_placement("show_on_matching_pages" => "1", "matching_page_paths" => "/**")
    log_user("admin", "admin")

    get "/settings"
    assert_select BLOCK, 0
    get "/admin"
    assert_select BLOCK, 0
    get "/issues"
    assert_select BLOCK, 1
  end

  test "the top menu gets a link to the page when asked, for the people allowed to see it" do
    with_placement("show_in_top_menu" => "1")
    log_user("jsmith", "jsmith")
    get "/"
    assert_select "#top-menu a[href=?]", "/windmill_status", text: "Windmill status"

    with_placement("show_in_top_menu" => "1", "visibility" => "admins")
    get "/"
    assert_select "#top-menu a[href=?]", "/windmill_status", 0

    with_placement("show_in_top_menu" => "0")
    get "/"
    assert_select "#top-menu a[href=?]", "/windmill_status", 0
  end

  test "every placement honours the who-may-see-it setting" do
    with_placement("visibility" => "admins", "show_on_welcome_page" => "1", "show_on_project_overview" => "1",
                   "show_on_matching_pages" => "1", "matching_page_paths" => "/issues")
    log_user("jsmith", "jsmith")
    %w[/ /projects/ecookbook /issues].each do |path|
      get path
      assert_select BLOCK, 0, path
    end

    reset!
    log_user("admin", "admin")
    %w[/ /projects/ecookbook /issues].each do |path|
      get path
      assert_select BLOCK, 1, path
    end
  end

  test "all placements share the cache: Windmill is asked once for several pages" do
    with_placement("show_on_welcome_page" => "1", "show_on_project_overview" => "1", "show_on_matching_pages" => "1", "matching_page_paths" => "/issues")
    log_user("jsmith", "jsmith")
    get "/"
    asked = @fake_windmill.request_count
    get "/projects/ecookbook"
    get "/issues"

    assert_equal asked, @fake_windmill.request_count
  end

  test "an unavailable Windmill does not break the host page" do
    @fake_windmill.scenario = "unavailable"
    with_placement("show_on_welcome_page" => "1", "show_on_matching_pages" => "1", "matching_page_paths" => "/issues")
    log_user("jsmith", "jsmith")
    get "/"
    assert_response :success
    assert_select "#{BLOCK}-summary.is-unavailable", text: "Status unavailable"
    get "/issues"
    assert_response :success
    assert_select "#content table.issues", 1
  end
end
