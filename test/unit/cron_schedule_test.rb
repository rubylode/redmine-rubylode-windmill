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

class RubylodeWindmill::CronScheduleTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 4, 12, 7, 30) # a Wednesday

  def previous(expression, timezone = "UTC")
    RubylodeWindmill::CronSchedule.parse(expression, timezone).previous_fire_time(NOW).utc
  end

  test "every five minutes" do
    assert_equal Time.utc(2026, 11, 4, 12, 5, 0), previous("0 */5 * * * *")
  end

  test "hourly and daily" do
    assert_equal Time.utc(2026, 11, 4, 12, 0, 0), previous("0 0 * * * *")
    assert_equal Time.utc(2026, 11, 4, 2, 0, 0), previous("0 0 2 * * *")
    assert_equal Time.utc(2026, 11, 3, 18, 30, 0), previous("0 30 18 * * *")
  end

  test "a weekday restriction uses the cron library's numbering, 1 is Sunday" do
    assert_equal Time.utc(2026, 11, 2, 8, 0, 0), previous("0 0 8 * * 2") # Monday
    assert_equal Time.utc(2026, 11, 2, 8, 0, 0), previous("0 0 8 * * MON")
    assert_equal Time.utc(2026, 11, 1, 8, 0, 0), previous("0 0 8 * * 1") # Sunday
  end

  test "lists, ranges and steps" do
    assert_equal Time.utc(2026, 11, 4, 12, 0, 0), previous("0 0,30 9-12 * * *")
    assert_equal Time.utc(2026, 11, 4, 10, 0, 0), previous("0 0 */5 * * *")
  end

  test "a monthly schedule" do
    assert_equal Time.utc(2026, 11, 1, 3, 0, 0), previous("0 0 3 1 * *")
  end

  test "the time zone is the schedule's own" do
    assert_equal Time.utc(2026, 11, 4, 7, 0, 0), previous("0 0 2 * * *", "America/New_York") # 02:00 EST is 07:00 UTC
  end

  test "five fields get a zero second" do
    assert_equal Time.utc(2026, 11, 4, 12, 7, 0), previous("* * * * *")
  end

  test "an expression it cannot read gives nil instead of a guess" do
    ["nonsense", "0 0 0 * * * 2026", "0 61 * * * *", "0 0 25 * * *", "0 0 * * * 9", ""].each do |expression|
      assert_nil RubylodeWindmill::CronSchedule.parse(expression), expression
    end
    assert_nil RubylodeWindmill::CronSchedule.parse("0 0 * * * *", "Nowhere/Land")
  end

  test "the interval is the gap between the last two fire times" do
    assert_equal 300, RubylodeWindmill::CronSchedule.parse("0 */5 * * * *").interval_seconds(NOW)
    assert_equal 3600, RubylodeWindmill::CronSchedule.parse("0 0 * * * *").interval_seconds(NOW)
    assert_equal 86_400, RubylodeWindmill::CronSchedule.parse("0 0 2 * * *").interval_seconds(NOW)
  end
end
