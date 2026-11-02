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

class RubylodeWindmill::ErrorSummaryTest < ActiveSupport::TestCase
  test "takes the message of Windmill's error object" do
    assert_equal "boom", RubylodeWindmill::ErrorSummary.from({ "error" => { "name" => "ExecutionErr", "message" => "boom" } })
  end

  test "takes a plain string, a string error or any other value" do
    assert_equal "plain", RubylodeWindmill::ErrorSummary.from("plain")
    assert_equal "text", RubylodeWindmill::ErrorSummary.from({ "error" => "text" })
    assert_equal '{"code":7}', RubylodeWindmill::ErrorSummary.from({ "code" => 7 })
  end

  test "collapses whitespace and truncates a long message with an ellipsis" do
    summary = RubylodeWindmill::ErrorSummary.from("line one\n\n   line two " + ("x" * 500))

    assert summary.start_with?("line one line two ")
    assert_operator summary.length, :<=, RubylodeWindmill::ErrorSummary::MAXIMUM_LENGTH
    assert summary.end_with?("…")
  end

  test "an empty result and the too-big placeholder get readable text" do
    assert_equal "No error message", RubylodeWindmill::ErrorSummary.from(nil)
    assert_equal "The error is too large to show", RubylodeWindmill::ErrorSummary.from("WINDMILL_TOO_BIG")
  end

  test "html is left as text for the view to escape" do
    assert_equal "<b>x</b>", RubylodeWindmill::ErrorSummary.from("<b>x</b>")
  end
end
