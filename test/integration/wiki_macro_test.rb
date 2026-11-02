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

class RubylodeWindmill::WikiMacroTest < Redmine::IntegrationTest
  include RubylodeWindmillTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :issue_statuses, :trackers,
           :projects_trackers, :enumerations, :enabled_modules, :wikis, :wiki_pages, :wiki_contents, :wiki_content_versions

  setup do
    use_memory_cache
    start_fake_windmill
  end

  teardown do
    stop_fake_windmill
    restore_cache
  end

  def get_wiki_page(text, login: "jsmith")
    page = WikiPage.new(wiki: Project.find(1).wiki, title: "Status_#{SecureRandom.hex(3)}")
    page.content = WikiContent.new(text: text, author: User.find(2))
    page.save!
    log_user(login, login)
    get "/projects/ecookbook/wiki/#{page.title}"
    assert_response :success
  end

  test "the macro draws the status block inside the wiki page" do
    get_wiki_page("Automation:\n\n{{windmill_status}}")

    assert_select ".wiki .rubylode-windmill-status-summary", text: /\A4 failing/
    assert_select ".wiki table.rubylode-windmill-failures"
  end

  test "the macro takes a title" do
    get_wiki_page("{{windmill_status(title=Automation)}}")

    assert_select ".wiki h3.rubylode-windmill-status-title", text: /\AAutomation/
  end

  test "the macro draws nothing for a person the settings do not allow" do
    configure_plugin("windmill_url" => @fake_windmill.base_url, "visibility" => "admins")
    get_wiki_page("before {{windmill_status}} after")

    assert_select ".wiki .rubylode-windmill-status", 0
  end

  test "a page with the macro still renders when Windmill is unavailable" do
    @fake_windmill.scenario = "unavailable"
    get_wiki_page("Before\n\n{{windmill_status}}\n\nAfter")

    assert_select ".wiki .rubylode-windmill-status-summary.is-unavailable", text: "Status unavailable"
    assert_select ".wiki", text: /After/
  end
end
