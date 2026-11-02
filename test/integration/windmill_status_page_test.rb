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

class RubylodeWindmill::WindmillStatusPageTest < Redmine::IntegrationTest
  include RubylodeWindmillTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issue_statuses, :trackers, :projects_trackers, :enumerations, :enabled_modules

  setup do
    use_memory_cache
  end

  teardown do
    stop_fake_windmill
    restore_cache
  end

  test "failures that still need attention are listed with path, kind, time, error and a link to the run" do
    start_fake_windmill
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_response :success
    assert_select ".rubylode-windmill-status-summary.is-attention", text: /\A4 failing/
    assert_select "table.rubylode-windmill-failures tbody tr", 4
    assert_select "tr.is-failed td.rubylode-windmill-status-path", text: /f\/billing\/sync_invoices/
    assert_select "tr.is-failed td.rubylode-windmill-status-error", text: "connection refused (billing database)"
    assert_select "tr.is-failed td.rubylode-windmill-status-kind", text: "Flow"
    assert_select "tr.is-failed td.rubylode-windmill-status-run a[href^=?]", "#{@fake_windmill.base_url}/run/", text: "Open run"
    assert_select "tr.is-failed td.rubylode-windmill-status-path", text: /import_contacts.*2/m
  end

  test "a failure that was followed by a success and one outside the window are not listed" do
    start_fake_windmill
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_select "td.rubylode-windmill-status-path", text: /cleanup_files/, count: 0
    assert_select "td.rubylode-windmill-status-path", text: /old_export/, count: 0
  end

  test "a long error is truncated" do
    start_fake_windmill
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_select "td.rubylode-windmill-status-error", text: /\A429 rate limited by the CRM.*…\z/m
  end

  test "all green says nothing needs attention and lists no failures" do
    start_fake_windmill(scenario: "all_green")
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_select ".rubylode-windmill-status-summary.is-ok", text: "Nothing needs attention"
    assert_select "table.rubylode-windmill-failures", 0
  end

  test "watched schedules show their last result and a late one is flagged" do
    start_fake_windmill
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_select "table.rubylode-windmill-schedules tbody tr", 3
    assert_select "tr.is-success td.rubylode-windmill-status-name", text: "Nightly sync"
    assert_select "tr.is-failure td.rubylode-windmill-status-name", text: "Hourly metrics"
    assert_select "tr.is-overdue td.rubylode-windmill-status-name", text: "Heartbeat"
    assert_select "tr.is-overdue .rubylode-windmill-status-flag", text: "Not run since its expected time"
  end

  test "a healthy schedule in the all green scenario is not flagged" do
    start_fake_windmill(scenario: "all_green")
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_select "tr.is-overdue", 0
    assert_select "tr.is-failure", 0
    assert_select "tr.is-success", 3
  end

  test "the path prefix filter narrows the failures" do
    start_fake_windmill("path_prefix" => "f/billing/")
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_select ".rubylode-windmill-status-summary", text: /\A1 failing/
  end

  test "rows beyond the maximum are counted" do
    start_fake_windmill("maximum_rows" => "2")
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_select "table.rubylode-windmill-failures tbody tr", 2
    assert_select ".rubylode-windmill-status-hint", text: /And 2 more failing/
  end

  test "an unavailable Windmill shows the fallback and the page still renders" do
    start_fake_windmill(scenario: "unavailable")
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_response :success
    assert_select ".rubylode-windmill-status-summary.is-unavailable", text: "Status unavailable"
    assert_select "table.rubylode-windmill-failures", 0
    assert_select "#header", 1
  end

  test "only an administrator sees why the status is unavailable" do
    start_fake_windmill(scenario: "unavailable")
    log_user("jsmith", "jsmith")
    get "/windmill_status"
    assert_select ".rubylode-windmill-status-hint", 0

    reset!
    log_user("admin", "admin")
    RubylodeWindmill::WindmillStatus.cache.clear
    get "/windmill_status"
    assert_select ".rubylode-windmill-status-hint", text: /Windmill answered 503/
  end

  test "an administrator sees a hint while the plugin is not configured, others see nothing" do
    configure_plugin("windmill_url" => "")
    log_user("admin", "admin")
    get "/windmill_status"
    assert_select ".rubylode-windmill-status-hint a[href=?]", "/settings/plugin/redmine_rubylode_windmill"

    reset!
    log_user("jsmith", "jsmith")
    get "/windmill_status"
    assert_select ".rubylode-windmill-status-hint", 0
    assert_select ".rubylode-windmill-status-summary", 0
  end

  test "signed-out visitors are sent to the login page, and administrators-only hides it from others" do
    start_fake_windmill("visibility" => "admins")
    get "/windmill_status"
    assert_response :redirect

    reset!
    log_user("jsmith", "jsmith")
    get "/windmill_status"
    assert_response :forbidden

    reset!
    log_user("admin", "admin")
    get "/windmill_status"
    assert_response :success
  end

  test "Windmill is asked once for two page loads within the cache window" do
    start_fake_windmill
    log_user("jsmith", "jsmith")
    get "/windmill_status"
    calls_after_first = @fake_windmill.request_count
    get "/windmill_status"

    assert_equal calls_after_first, @fake_windmill.request_count
  end

  test "everything Windmill supplies is escaped: a hostile path and error message" do
    start_fake_windmill(scenario: "hostile")
    log_user("jsmith", "jsmith")
    get "/windmill_status"

    assert_response :success
    refute_includes response.body, "<script>alert(\"x\")</script>"
    refute_includes response.body, "<img src=x onerror"
    refute_includes response.body, "<b>bold</b>"
    assert_select "td.rubylode-windmill-status-error script", 0
    assert_select "td.rubylode-windmill-status-error img", 0
    assert_select "td.rubylode-windmill-status-error", text: FakeWindmillServer::HOSTILE_ERROR
    assert_select "td.rubylode-windmill-status-path", text: /f\/evil\/<b>bold<\/b>/
  end
end
