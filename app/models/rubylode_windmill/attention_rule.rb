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

module RubylodeWindmill
  # The "needs attention" rule. A failed run needs attention when no run of the same script or flow path that started
  # after it has succeeded. A path with several failures is one row, for its latest failure, with the number of
  # failures in the window. The newest failure comes first.
  class AttentionRule
    FailedRun = Struct.new(:run_id, :path, :kind, :started_at, :failed_at, :error)
    Row = Struct.new(:run_id, :path, :kind, :started_at, :failed_at, :error, :failure_count)

    # recovered: a callable that gets the latest failed run of a path and answers whether a later run succeeded.
    def self.call(failed_runs, recovered:)
      new(failed_runs, recovered: recovered).rows
    end

    def initialize(failed_runs, recovered:)
      @failed_runs = failed_runs
      @recovered = recovered
    end

    def rows
      latest_per_path = @failed_runs.group_by { |run| [run.path, run.kind] }.map do |_key, runs|
        [runs.max_by(&:started_at), runs.size]
      end
      still_failing = latest_per_path.reject { |latest, _count| @recovered.call(latest) }
      still_failing.sort_by { |latest, _count| -latest.failed_at.to_f }.map do |latest, count|
        Row.new(latest.run_id, latest.path, latest.kind, latest.started_at, latest.failed_at, latest.error, count)
      end
    end
  end
end
