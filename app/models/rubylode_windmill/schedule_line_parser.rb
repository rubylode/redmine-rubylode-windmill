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
  # Reads the watched-schedules textarea: one schedule per line, "Name | schedule path | Description".
  # Blank lines and lines starting with # are skipped. The description may be empty. A bad line is reported with its line
  # number and does not stop the others from being read.
  class ScheduleLineParser
    WatchedSchedule = Struct.new(:name, :path, :description)
    LineError = Struct.new(:line_number, :message)
    Result = Struct.new(:schedules, :errors) do
      def valid?
        errors.empty?
      end
    end

    FIELD_COUNT = 3
    PATH_PATTERN = %r{\A[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)+\z}

    def self.parse(text)
      new(text).parse
    end

    def initialize(text)
      @text = text.to_s
    end

    def parse
      schedules = []
      errors = []
      @text.each_line.with_index(1) do |raw_line, line_number|
        line = raw_line.strip
        next if line.empty? || line.start_with?("#")

        schedule_or_message = read_line(line)
        if schedule_or_message.is_a?(String)
          errors << LineError.new(line_number, schedule_or_message)
        else
          schedules << schedule_or_message
        end
      end
      Result.new(schedules, errors)
    end

    private

    def read_line(line)
      fields = line.split("|", -1).map(&:strip)
      return I18n.t("rubylode_windmill.errors.line_field_count", count: FIELD_COUNT, found: fields.size) unless fields.size == FIELD_COUNT

      name, path, description = fields
      return I18n.t("rubylode_windmill.errors.line_name_missing") if name.empty?
      return I18n.t("rubylode_windmill.errors.line_path_invalid", path: path) unless path.match?(PATH_PATTERN)

      WatchedSchedule.new(name, path, description)
    end
  end
end
