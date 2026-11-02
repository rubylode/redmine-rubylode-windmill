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
  # Turns what Windmill returns as the result of a failed run into one short line. Windmill's own errors are
  # {"error": {"name": "ExecutionErr", "message": "..."}}, but a script may throw anything. The text is plain text:
  # escaping is the view's job.
  module ErrorSummary
    MAXIMUM_LENGTH = 200
    TOO_BIG_PLACEHOLDER = "WINDMILL_TOO_BIG".freeze

    module_function

    def from(result, maximum_length: MAXIMUM_LENGTH)
      text = text_of(result)
      return I18n.t("rubylode_windmill.errors.no_error_message") if text.empty?
      return I18n.t("rubylode_windmill.errors.result_too_big") if text == TOO_BIG_PLACEHOLDER

      text.truncate(maximum_length, omission: "…")
    end

    def message_of(error)
      error.is_a?(Hash) ? error["message"] : error
    end

    def text_of(result)
      value = case result
              when Hash then message_of(result["error"]) || result["message"] || result
              else result
              end
      value = value.is_a?(String) ? value : value.to_json unless value.nil?
      value.to_s.gsub(/\s+/, " ").strip
    end
  end
end
