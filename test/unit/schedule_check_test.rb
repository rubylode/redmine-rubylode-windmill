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

class RubylodeWindmill::ScheduleCheckTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 4, 12, 7, 30)

  def verdict(cron: "0 0 * * * *", enabled: true, last_run: nil)
    RubylodeWindmill::ScheduleCheck.verdict(enabled: enabled, cron_expression: cron, timezone: "UTC", last_run: last_run, now: NOW)
  end

  def last_run_of(minutes_ago, success: true)
    { id: "run", success: success, started_at: NOW - (minutes_ago * 60) }
  end

  test "a run after the latest expected time is fine and shows its result" do
    result = verdict(last_run: last_run_of(5))

    assert_equal :success, result.last_result
    refute result.overdue?
    refute result.needs_attention?
    assert_equal 3600, result.interval_seconds
  end

  test "a failed last run needs attention but is not overdue" do
    result = verdict(last_run: last_run_of(5, success: false))

    assert_equal :failure, result.last_result
    refute result.overdue?
    assert result.needs_attention?
  end

  test "a run older than the latest expected time is overdue" do
    result = verdict(last_run: last_run_of(90))

    assert result.overdue?
    assert result.needs_attention?
  end

  test "a schedule with no run at all that should have fired is overdue" do
    result = verdict(last_run: nil)

    assert_equal :none, result.last_result
    assert result.overdue?
  end

  test "a run that is just due gets a grace period" do
    just_after_the_hour = Time.utc(2026, 11, 4, 12, 0, 40)
    result = RubylodeWindmill::ScheduleCheck.verdict(enabled: true, cron_expression: "0 0 * * * *", timezone: "UTC",
                                                     last_run: { id: "r", success: true, started_at: Time.utc(2026, 11, 4, 11, 0, 3) }, now: just_after_the_hour)

    refute result.overdue?
  end

  test "a paused schedule is never overdue" do
    refute verdict(enabled: false, last_run: last_run_of(600)).overdue?
  end

  test "an unknown interval is never flagged overdue" do
    result = verdict(cron: "something odd", last_run: last_run_of(100_000))

    refute result.overdue?
    assert_nil result.interval_seconds
  end
end
