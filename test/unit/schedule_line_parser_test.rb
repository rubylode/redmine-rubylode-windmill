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

class RubylodeWindmill::ScheduleLineParserTest < ActiveSupport::TestCase
  test "reads name, path and description" do
    result = RubylodeWindmill::ScheduleLineParser.parse("Nightly sync | f/billing/nightly_sync | Copies invoices")

    assert result.valid?
    schedule = result.schedules.first
    assert_equal ["Nightly sync", "f/billing/nightly_sync", "Copies invoices"], [schedule.name, schedule.path, schedule.description]
  end

  test "the description may be empty, blank lines and comments are skipped" do
    result = RubylodeWindmill::ScheduleLineParser.parse("# watched\n\nSync | u/me/sync |\n  \n")

    assert result.valid?
    assert_equal 1, result.schedules.size
    assert_equal "", result.schedules.first.description
  end

  test "a bad line is reported with its number and the good lines are still read" do
    result = RubylodeWindmill::ScheduleLineParser.parse("Good | f/a/b | x\nonly two | fields\n | f/a/c | no name\nBad path | not a path | x")

    refute result.valid?
    assert_equal 1, result.schedules.size
    assert_equal [2, 3, 4], result.errors.map(&:line_number)
  end

  test "a description with extra pipes is refused as too many fields" do
    result = RubylodeWindmill::ScheduleLineParser.parse("Name | f/a/b | one | two")

    assert_equal [1], result.errors.map(&:line_number)
  end
end
