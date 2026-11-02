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
  # Judges one watched schedule from what Windmill said about it and its latest run. Pure: give it the times.
  #
  # last_result is :success, :failure or :none (no run recorded). overdue is true when the schedule is enabled, its cron
  # expression is understood, and it should have fired by now (GRACE_SECONDS allowed) but its latest run is older than
  # that moment. An unreadable expression means the interval is unknown, so it is never flagged overdue.
  class ScheduleCheck
    GRACE_SECONDS = 120

    Verdict = Struct.new(:last_result, :last_run_at, :last_run_id, :overdue, :enabled, :interval_seconds, :needs_attention) do
      alias_method :overdue?, :overdue
      alias_method :needs_attention?, :needs_attention
    end

    def self.verdict(enabled:, cron_expression:, timezone:, last_run:, now: Time.current)
      last_result = last_run ? (last_run[:success] ? :success : :failure) : :none
      cron = CronSchedule.parse(cron_expression, timezone)
      overdue = !!(enabled && cron && overdue?(cron, last_run && last_run[:started_at], now))
      Verdict.new(last_result, last_run && last_run[:started_at], last_run && last_run[:id], overdue, enabled,
                  cron&.interval_seconds(now), overdue || last_result == :failure)
    end

    def self.overdue?(cron, last_started_at, now)
      expected = cron.previous_fire_time(now - GRACE_SECONDS)
      return false if expected.nil?

      last_started_at.nil? || last_started_at < expected
    end
  end
end
