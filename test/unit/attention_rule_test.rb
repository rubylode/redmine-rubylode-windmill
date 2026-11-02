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

# The "needs attention" rule: a failed run whose later run of the same path has not succeeded.
class RubylodeWindmill::AttentionRuleTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 11, 1, 12, 0, 0)

  def failed(path, minutes_ago, kind: "script", id: nil)
    started = NOW - (minutes_ago * 60)
    RubylodeWindmill::AttentionRule::FailedRun.new(id || "#{path}-#{minutes_ago}", path, kind, started, started + 5, "error")
  end

  def rows_for(runs, recovered_paths: [])
    RubylodeWindmill::AttentionRule.call(runs, recovered: ->(run) { recovered_paths.include?(run.path) })
  end

  test "a failure with no later success needs attention" do
    rows = rows_for([failed("f/a/one", 30)])

    assert_equal ["f/a/one"], rows.map(&:path)
  end

  test "a failure followed by a success is recovered and not listed" do
    rows = rows_for([failed("f/a/one", 30), failed("f/a/two", 20)], recovered_paths: ["f/a/one"])

    assert_equal ["f/a/two"], rows.map(&:path)
  end

  test "several failures of one path make one row for the latest, with the count" do
    rows = rows_for([failed("f/a/one", 90, id: "old"), failed("f/a/one", 10, id: "new"), failed("f/a/one", 50, id: "mid")])

    assert_equal 1, rows.size
    assert_equal "new", rows.first.run_id
    assert_equal 3, rows.first.failure_count
  end

  test "the recovery question is asked about the latest failure of the path" do
    asked = []
    RubylodeWindmill::AttentionRule.call([failed("f/a/one", 90, id: "old"), failed("f/a/one", 10, id: "new")],
                                         recovered: ->(run) { asked << run.run_id; false })

    assert_equal ["new"], asked
  end

  test "the newest failure comes first" do
    rows = rows_for([failed("f/a/old", 200), failed("f/a/new", 5), failed("f/a/mid", 60)])

    assert_equal %w[f/a/new f/a/mid f/a/old], rows.map(&:path)
  end

  test "a script and a flow with the same path are separate" do
    rows = rows_for([failed("f/a/same", 10), failed("f/a/same", 20, kind: "flow")])

    assert_equal %w[script flow], rows.map(&:kind)
  end

  test "nothing failed means nothing needs attention" do
    assert_empty rows_for([])
  end
end
