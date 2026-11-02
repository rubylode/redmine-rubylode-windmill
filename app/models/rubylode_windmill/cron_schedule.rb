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
  # Reads a Windmill schedule's cron expression (six fields: seconds, minutes, hours, day of month, month, day of week)
  # and answers when it last should have fired. Understands numbers, lists, ranges, steps, * and ? and the usual month
  # and weekday names. Day of week numbers follow the cron library Windmill uses: 1 is Sunday, 7 is Saturday.
  # An expression it cannot read gives nil from .parse, which means "the interval is not known".
  class CronSchedule
    SEARCH_DAYS = 62
    MONTH_NAMES = %w[JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC].freeze
    WEEKDAY_NAMES = %w[SUN MON TUE WED THU FRI SAT].freeze

    def self.parse(expression, timezone = "UTC")
      new(expression, timezone)
    rescue ArgumentError
      nil
    end

    def initialize(expression, timezone = "UTC")
      fields = expression.to_s.split
      fields.unshift("0") if fields.size == 5
      raise ArgumentError, "a cron expression has six fields" unless fields.size == 6

      @seconds = expand(fields[0], 0..59)
      @minutes = expand(fields[1], 0..59)
      @hours = expand(fields[2], 0..23)
      @days_of_month = expand(fields[3], 1..31)
      @months = expand(fields[4], 1..12, MONTH_NAMES, 1)
      @weekdays = expand(fields[5], 1..7, WEEKDAY_NAMES, 1).map { |number| (number - 1) % 7 }
      @zone = ActiveSupport::TimeZone[timezone.to_s.presence || "UTC"] or raise ArgumentError, "unknown time zone"
    end

    # The latest time at or before the given time when the schedule fires, or nil when none within about two months.
    def previous_fire_time(at_or_before)
      local = at_or_before.in_time_zone(@zone)
      SEARCH_DAYS.times do |days_back|
        day = local.to_date - days_back
        next unless runs_on?(day)

        @hours.reverse_each do |hour|
          @minutes.reverse_each do |minute|
            @seconds.reverse_each do |second|
              candidate = @zone.local(day.year, day.month, day.day, hour, minute, second)
              return candidate if candidate <= local
            end
          end
        end
      end
      nil
    end

    # Seconds between the last two times it should have fired, or nil when unknown.
    def interval_seconds(before = Time.current)
      latest = previous_fire_time(before)
      earlier = latest && previous_fire_time(latest - 1)
      earlier && (latest - earlier).round
    end

    private

    def runs_on?(day)
      @months.include?(day.month) && @days_of_month.include?(day.day) && @weekdays.include?(day.wday)
    end

    def expand(field, range, names = [], name_offset = 0)
      values = field.split(",").flat_map { |part| expand_part(part, range, names, name_offset) }.uniq.sort
      raise ArgumentError, "empty field" if values.empty?

      values
    end

    def expand_part(part, range, names, name_offset)
      base, step_text = part.split("/", 2)
      step = step_text ? Integer(step_text, 10) : 1
      raise ArgumentError, "bad step" unless step.positive?

      first, last = if %w[* ?].include?(base)
        [range.first, range.last]
      elsif base.include?("-")
        base.split("-", 2).map { |bound| number_of(bound, names, name_offset) }
      else
        value = number_of(base, names, name_offset)
        step_text ? [value, range.last] : [value, value]
      end
      raise ArgumentError, "out of range" unless range.cover?(first) && range.cover?(last) && first <= last

      (first..last).step(step).to_a
    end

    def number_of(text, names, name_offset)
      index = names.index(text.upcase)
      index ? index + name_offset : Integer(text, 10)
    end
  end
end
