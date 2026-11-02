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
  # The plugin's settings, read with their defaults and clamped to sensible values. The token is not one of them:
  # only the NAME of the environment variable that holds it is a setting, and that name must start with WINDMILL_ so a
  # setting can never make the plugin read (and send out) some other secret of the server.
  class Configuration
    VISIBILITIES = %w[logged_in admins].freeze
    TOKEN_VARIABLE_PATTERN = /\AWINDMILL_[A-Z0-9_]*\z/
    WORKSPACE_PATTERN = /\A[A-Za-z0-9_-]+\z/
    HOST_PATTERN = /\A[A-Za-z0-9.-]+\z/
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    def self.current
      new(Setting.send(:"plugin_#{RedmineRubylodeWindmill::PLUGIN_ID}"))
    end

    def self.web_address?(value)
      uri = URI.parse(value.to_s.strip)
      %w[http https].include?(uri.scheme) && !uri.host.to_s.empty?
    rescue URI::InvalidURIError
      false
    end

    def self.loopback_host?(host)
      LOOPBACK_HOSTS.include?(host.to_s.downcase) || host.to_s.match?(/\A127\.\d+\.\d+\.\d+\z/)
    end

    def initialize(raw_settings = {})
      @settings = RedmineRubylodeWindmill::Defaults::SETTINGS.merge((raw_settings || {}).to_h.stringify_keys.compact)
    end

    def windmill_url
      @settings["windmill_url"].to_s.strip.chomp("/")
    end

    def windmill_host
      URI.parse(windmill_url).host.to_s.downcase
    rescue URI::InvalidURIError
      ""
    end

    def workspace_id
      @settings["workspace_id"].to_s.strip
    end

    # The configured name when it is allowed, otherwise nil: a name that is not allowed is never looked up in the
    # environment, so the token counts as missing.
    def token_environment_variable
      name = @settings["token_environment_variable"].to_s.strip
      name = RedmineRubylodeWindmill::Defaults::SETTINGS["token_environment_variable"] if name.empty?
      name.match?(TOKEN_VARIABLE_PATTERN) ? name : nil
    end

    def token
      name = token_environment_variable
      name ? ENV[name].to_s : ""
    end

    def allowed_hosts
      @settings["allowed_hosts"].to_s.downcase.split(/[\s,]+/).select { |host| host.match?(HOST_PATTERN) }.uniq
    end

    # The hosts the token may be sent to: the Windmill host and the extra hosts listed in the settings.
    def token_hosts
      ([windmill_host] + allowed_hosts).reject(&:empty?)
    end

# May the token be sent to this address? The host must be the saved Windmill host (on the saved port) or one of the
# extra allowed hosts, and the scheme must pass plain_http_acceptable?.
def token_destination_allowed?(url)
  uri = URI.parse(url.to_s)
  host = uri.host.to_s.downcase
  host_allowed = if host == windmill_host
    uri.port == URI.parse(windmill_url).port
  else
    allowed_hosts.include?(host)
  end
  host_allowed && plain_http_acceptable?(url)
rescue URI::InvalidURIError
  false
end

def allow_plain_http?
      @settings["allow_plain_http"].to_s == "1"
    end

    # https is required, except for a loopback host or when the settings explicitly allow plain http.
    def plain_http_acceptable?(url)
      uri = URI.parse(url.to_s)
      uri.scheme == "https" || (uri.scheme == "http" && (allow_plain_http? || self.class.loopback_host?(uri.host)))
    rescue URI::InvalidURIError
      false
    end

    def look_back_hours
      whole_number("look_back_hours", minimum: 1)
    end

    def maximum_rows
      whole_number("maximum_rows", minimum: 1)
    end

    def path_prefix
      @settings["path_prefix"].to_s.strip
    end

    def watched_schedules_text
      @settings["watched_schedules"].to_s
    end

    def watched_schedules
      ScheduleLineParser.parse(watched_schedules_text).schedules
    end

    def cache_seconds
      whole_number("cache_seconds", minimum: 0)
    end

    def failure_cache_seconds
      whole_number("failure_cache_seconds", minimum: 0)
    end

    def timeout_seconds
      whole_number("timeout_seconds", minimum: 1)
    end

    def block_title
      title = @settings["block_title"].to_s.strip
      title.empty? ? RedmineRubylodeWindmill::Defaults::SETTINGS["block_title"] : title
    end

COLUMNS = %w[left right].freeze

def show_on_welcome_page?
  flag?("show_on_welcome_page")
end

def welcome_page_column
  column("welcome_page_column")
end

def show_on_my_page?
  flag?("show_on_my_page")
end

def show_on_project_overview?
  flag?("show_on_project_overview")
end

def project_overview_column
  column("project_overview_column")
end

def show_on_matching_pages?
  flag?("show_on_matching_pages") && matching_page_paths.any?
end

def matching_page_paths
  PathMatcher.patterns_from(@settings["matching_page_paths"])
end

def show_in_top_menu?
  flag?("show_in_top_menu")
end

    def visibility
      VISIBILITIES.include?(@settings["visibility"].to_s) ? @settings["visibility"].to_s : "logged_in"
    end

    def visible_to?(user)
      return false unless user&.logged?

      visibility == "admins" ? user.admin? : true
    end

    def configured?
      !windmill_url.empty? && !workspace_id.empty?
    end

    # Changes whenever a setting that changes the answer changes, so cached answers never outlive their settings.
    def cache_fingerprint
      Digest::SHA256.hexdigest([windmill_url, workspace_id, look_back_hours, maximum_rows, path_prefix, watched_schedules_text].join("\u0000"))[0, 16]
    end

    private

    def flag?(key)
      @settings[key].to_s == "1"
    end

    def column(key)
      COLUMNS.include?(@settings[key].to_s) ? @settings[key].to_s : "right"
    end

    def whole_number(key, minimum:)
      value = Integer(@settings[key].to_s.strip, 10)
      [value, minimum].max
    rescue ArgumentError
      Integer(RedmineRubylodeWindmill::Defaults::SETTINGS[key], 10)
    end
  end
end
