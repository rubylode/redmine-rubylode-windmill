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

class RubylodeWindmill::StatusWidgetTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  NOW = Time.utc(2026, 11, 4, 12, 7, 30)

  def failing_row(path, count: 1)
    RubylodeWindmill::AttentionRule::Row.new("run-#{path}", path, "flow", NOW - 600, NOW - 300, "connection refused", count)
  end

  def schedule_state(name, found: true, unreadable: false, last_result: :success, overdue: false, enabled: true)
    verdict = if found && !unreadable
      RubylodeWindmill::ScheduleCheck::Verdict.new(last_result, NOW - 60, "run-#{name}", overdue, enabled, 3600, overdue || last_result == :failure)
    end
    RubylodeWindmill::WindmillStatus::ScheduleState.new(name, "f/ops/#{name}", "", found, unreadable, verdict, verdict&.last_run_id)
  end

  def report_with(rows: [], schedules: [], unavailable: false, summary: "Nothing needs attention")
    state = unavailable ? :unavailable : (rows.empty? && schedules.none?(&:needs_attention?) ? :ok : :attention)
    RubylodeWindmill::WindmillStatus::Report.new(rows, rows, 0, schedules, summary, state, unavailable, nil)
  end

  def data_for(report, overrides = {})
    configure_plugin(overrides)
    replacing_method(RubylodeWindmill::WindmillStatus, :safe_report, ->(*) { report }) do
      RubylodeWindmill::StatusWidget.data
    end
  end

  test "the data has the keys of the widget contract" do
    data = data_for(report_with)

    assert_equal %i[state summary items], data.keys
    assert_equal "ok", data[:state]
    assert_equal "Nothing needs attention", data[:summary]
    assert_equal [], data[:items]
  end

  test "a failed run is a down item with its error as the detail" do
    data = data_for(report_with(rows: [failing_row("f/billing/sync")], summary: "1 failing"))

    assert_equal "down", data[:state]
    assert_equal "1 failing", data[:summary]
    assert_equal [{ name: "f/billing/sync", state: "down", detail: "connection refused" }], data[:items]
  end

  test "a failure that repeated says how many times" do
    data = data_for(report_with(rows: [failing_row("f/billing/sync", count: 3)]))

    assert_equal "connection refused (3 failures)", data[:items].first[:detail]
  end

  test "watched schedules map to ok, warning, down and unknown" do
    schedules = [
      schedule_state("fine"),
      schedule_state("late", overdue: true),
      schedule_state("broken", last_result: :failure),
      schedule_state("gone", found: false),
      schedule_state("unreadable", unreadable: true)
    ]
    data = data_for(report_with(schedules: schedules))

    assert_equal %w[ok warning down unknown unknown], data[:items].map { |item| item[:state] }
    assert_equal ["fine", "late", "broken", "gone", "unreadable"], data[:items].map { |item| item[:name] }
    assert_nil data[:items][0][:detail]
    assert_equal "Not run since its expected time", data[:items][1][:detail]
    assert_equal "Last run failed", data[:items][2][:detail]
    assert_equal "Not found in Windmill", data[:items][3][:detail]
    assert_equal "Could not be read", data[:items][4][:detail]
  end

  test "the block state is the worst item state, and an unknown item makes it a warning" do
    assert_equal "warning", data_for(report_with(schedules: [schedule_state("late", overdue: true)]))[:state]
    assert_equal "warning", data_for(report_with(schedules: [schedule_state("gone", found: false)]))[:state]
    assert_equal "down", data_for(report_with(rows: [failing_row("f/a")], schedules: [schedule_state("late", overdue: true)]))[:state]
  end

  test "an unreachable Windmill is unknown" do
    data = data_for(report_with(unavailable: true, summary: "Status unavailable"))

    assert_equal "unknown", data[:state]
    assert_equal "Status unavailable", data[:summary]
    assert_equal [], data[:items]
  end

  test "a plugin that is not set up is unknown and does not ask Windmill" do
    configure_plugin("base_url" => "")
    asked = false
    data = replacing_method(RubylodeWindmill::WindmillStatus, :safe_report, ->(*) { asked = true }) { RubylodeWindmill::StatusWidget.data }

    refute asked
    assert_equal "unknown", data[:state]
    assert_equal "Windmill is not set up yet", data[:summary]
  end
end

class RubylodeWindmill::StatusWidgetRegistrationTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  test "the widget is registered with its title, page, partial and visibility when the Status plugin is there" do
    with_fake_status_registry do |registry|
      configure_plugin("block_title" => "Automation", "visibility" => "admins")
      RubylodeWindmill::StatusWidget.register_with_status_plugin

      widget = registry.widgets.fetch("windmill")
      assert_equal "Automation", widget[:title].call
      assert_equal "/status/windmill", widget[:path]
      assert_equal "rubylode_windmill/status", widget[:partial]
      assert_equal "admins", widget[:visibility].call
      assert_respond_to widget[:data], :call
    end
  end

  test "registering twice keeps one widget" do
    with_fake_status_registry do |registry|
      2.times { RubylodeWindmill::StatusWidget.register_with_status_plugin }

      assert_equal 1, registry.widgets.size
    end
  end

  test "nothing is registered and nothing breaks when the Status plugin is missing" do
    refute defined?(RubylodeStatus::Registry)

    assert_nil RubylodeWindmill::StatusWidget.register_with_status_plugin
  end
end
