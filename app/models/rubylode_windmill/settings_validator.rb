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
  # Checks the settings form before it is saved. Returns a list of messages, empty when everything is fine.
  # Empty values are fine where the plugin has a default or the setting is optional.
  class SettingsValidator
    NUMBER_FIELDS = { "look_back_hours" => 1, "maximum_rows" => 1, "cache_seconds" => 0, "failure_cache_seconds" => 0, "timeout_seconds" => 1 }.freeze

    def self.errors_for(raw_settings)
      new(raw_settings).errors
    end

    def initialize(raw_settings)
      @settings = (raw_settings || {}).to_h.stringify_keys
    end

    def errors
      messages = []
      messages << t("windmill_url_invalid") unless blank_or_web_address?("windmill_url")
      messages << t("plain_http_refused") if plain_http_refused?
      messages << t("workspace_invalid") unless workspace_valid?
      messages << t("environment_variable_invalid") unless environment_variable_valid?
      messages << t("allowed_hosts_invalid") unless allowed_hosts_valid?
      messages << t("block_title_blank") if @settings.key?("block_title") && @settings["block_title"].to_s.strip.empty?
      messages << t("visibility_invalid") unless visibility_valid?
      messages.concat(number_errors)
      messages << t("column_invalid") unless columns_valid?
      messages.concat(schedule_errors)
      messages.concat(path_errors)
      messages
    end

    private

    def t(key, **options)
      I18n.t("rubylode_windmill.errors.#{key}", **options)
    end

    def blank_or_web_address?(key)
      value = @settings[key].to_s.strip
      value.empty? || Configuration.web_address?(value)
    end

    def plain_http_refused?
      configuration = Configuration.new(@settings)
      url = configuration.windmill_url
      return false if url.empty? || !Configuration.web_address?(url)

      !configuration.plain_http_acceptable?(url)
    end

    def workspace_valid?
      workspace = @settings["workspace_id"].to_s.strip
      workspace.empty? || workspace.match?(Configuration::WORKSPACE_PATTERN)
    end

    def environment_variable_valid?
      name = @settings["token_environment_variable"].to_s.strip
      name.empty? || name.match?(Configuration::TOKEN_VARIABLE_PATTERN)
    end

    def allowed_hosts_valid?
      @settings["allowed_hosts"].to_s.downcase.split(/[\s,]+/).all? { |host| host.empty? || host.match?(Configuration::HOST_PATTERN) }
    end

def columns_valid?
  %w[welcome_page_column project_overview_column].all? do |key|
    !@settings.key?(key) || Configuration::COLUMNS.include?(@settings[key].to_s)
  end
end

def path_errors
  patterns = @settings["matching_page_paths"].to_s.lines.map(&:strip).each_with_index.reject { |line, _| line.empty? || line.start_with?("#") }
  errors = patterns.filter_map do |pattern, index|
    problem = PathMatcher.problem_with(pattern)
    t("path_line_prefix", line_number: index + 1, message: t("path_#{problem}", maximum: PathMatcher::MAXIMUM_LENGTH)) if problem
  end
  errors << t("path_too_many", maximum: PathMatcher::MAXIMUM_PATTERNS) if patterns.size > PathMatcher::MAXIMUM_PATTERNS
  errors
end

def visibility_valid?
      !@settings.key?("visibility") || Configuration::VISIBILITIES.include?(@settings["visibility"].to_s)
    end

    def number_errors
      NUMBER_FIELDS.filter_map do |key, minimum|
        value = @settings[key].to_s.strip
        next if value.empty?

        valid = value.match?(/\A\d+\z/) && value.to_i >= minimum
        t("number_invalid", field: I18n.t("rubylode_windmill.settings.#{key}"), minimum: minimum) unless valid
      end
    end

    def schedule_errors
      ScheduleLineParser.parse(@settings["watched_schedules"]).errors.map do |line_error|
        t("line_prefix", line_number: line_error.line_number, message: line_error.message)
      end
    end
  end
end
