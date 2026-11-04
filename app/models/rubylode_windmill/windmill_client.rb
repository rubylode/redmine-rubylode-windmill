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

require "net/http"
require "json"

module RubylodeWindmill
  # Asks Windmill's REST API (https://app.windmill.dev/openapi.html) for completed runs and schedules, with the API token
  # as a bearer token. Read-only: it only issues GET requests.
  #
  # The token is held only in memory for the request. It is never logged and is scrubbed from every error message. It is
  # sent only to the host of the saved Windmill address (plus the hosts listed in "allowed hosts"), over https unless the
  # host is loopback or plain http was allowed in the settings. A redirect is followed only to such a host; any other
  # redirect is refused before a byte is sent there.
  class WindmillClient
    class Unavailable < StandardError; end

    JOB_KINDS = "script,flow,singlestepflow".freeze
    PAGE_SIZE = 100
    MAXIMUM_PAGES = 3
    MAXIMUM_REDIRECTS = 3
    REDIRECT_STATUSES = [301, 302, 303, 307, 308].freeze

    def self.from_configuration(configuration)
      new(configuration: configuration)
    end

    # http_client: a callable (url, token) returning [status, body, location]; replaced in unit tests.
    def initialize(configuration:, http_client: nil)
      @configuration = configuration
      @token = configuration.token
      @http_client = http_client || method(:fetch_over_http)
    end

    # Failed runs of scripts and flows in the look-back window, newest first. Flow steps are left out.
    def failed_runs(now: Time.current)
      since = now - @configuration.look_back_hours.hours
      query = { success: "false", is_flow_step: "false", job_kinds: JOB_KINDS, order_desc: "true",
                started_after: since.utc.iso8601(3), per_page: PAGE_SIZE }
      query[:script_path_start] = @configuration.path_prefix unless @configuration.path_prefix.empty?
      jobs = (1..MAXIMUM_PAGES).each_with_object([]) do |page, collected|
        batch = get_json("/jobs/completed/list", query.merge(page: page))
        collected.concat(batch)
        break collected if batch.size < PAGE_SIZE
      end
      jobs.filter_map { |job| failed_run_from(job) }
    end

    # Did a run of the same path that started after this failed run succeed?
    def recovered?(failed_run)
      query = { success: "true", is_flow_step: "false", job_kinds: JOB_KINDS, script_path_exact: failed_run.path,
                started_after: failed_run.started_at.utc.iso8601(3), per_page: 1 }
      get_json("/jobs/completed/list", query).any?
    end

    # The error of a failed run, as one short line. Asked for only when the list did not carry the result.
    def error_summary_for(run_id)
      ErrorSummary.from(get_json("/jobs_u/completed/get_result/#{segment(run_id)}", {}, parse_as: :any))
    end

    # The schedule as a plain hash, or nil when Windmill has no schedule at that path.
    def schedule(path)
      status_and_body = request("/schedules/get/#{path_segments(path)}", {}, accept_not_found: true)
      return nil if status_and_body.nil?

      parsed = parse(status_and_body)
      raise Unavailable, I18n.t("rubylode_windmill.errors.windmill_unreadable") unless parsed.is_a?(Hash)

      { path: parsed["path"], enabled: parsed["enabled"] != false, cron: parsed["schedule"].to_s,
        timezone: parsed["timezone"].to_s, script_path: parsed["script_path"].to_s, is_flow: parsed["is_flow"] == true }
    end

    # The latest run started by a schedule: {id:, success:, started_at:}, or nil when it has not run.
    def latest_schedule_run(schedule_path)
      jobs = get_json("/jobs/completed/list", { schedule_path: schedule_path, order_desc: "true", per_page: 1 })
      job = jobs.first
      return nil unless job

      { id: job["id"].to_s, success: job["success"] == true, started_at: time_from(job["started_at"] || job["created_at"]) }
    end

    private

    def failed_run_from(job)
      started_at = time_from(job["started_at"] || job["created_at"])
      return nil if started_at.nil? || job["script_path"].to_s.empty?

      kind = job["job_kind"].to_s == "flow" ? "flow" : "script"
      error = job.key?("result") ? ErrorSummary.from(job["result"]) : nil
      AttentionRule::FailedRun.new(job["id"].to_s, job["script_path"].to_s, kind, started_at,
                                   time_from(job["completed_at"]) || started_at, error)
    end

    def time_from(text)
      Time.iso8601(text.to_s)
    rescue ArgumentError
      nil
    end

    def get_json(path, query, parse_as: :array)
      parsed = parse(request(path, query))
      raise Unavailable, I18n.t("rubylode_windmill.errors.windmill_unreadable") if parse_as == :array && !parsed.is_a?(Array)

      parsed
    end

    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError
      raise Unavailable, I18n.t("rubylode_windmill.errors.windmill_unreadable")
    end

    # Returns the body of a 200 answer (nil for a 404 when accept_not_found). Raises Unavailable for anything else.
    def request(path, query, accept_not_found: false)
      raise Unavailable, token_missing_message if @token.empty?
      raise Unavailable, I18n.t("rubylode_windmill.errors.not_configured") unless @configuration.configured?

      url = "#{@configuration.base_url}/api/w/#{segment(@configuration.workspace_id)}#{path}"
      url += "?#{URI.encode_www_form(query)}" unless query.empty?
      status, body = follow(url)
      return nil if status == 404 && accept_not_found
      raise Unavailable, I18n.t("rubylode_windmill.errors.windmill_status", status: status) unless status == 200

      body
    rescue Unavailable => error
      raise Unavailable, scrub(error.message)
    rescue StandardError => error
      raise Unavailable, I18n.t("rubylode_windmill.errors.windmill_unreachable", error_class: error.class)
    end

    def follow(url)
      (MAXIMUM_REDIRECTS + 1).times do
        check_destination!(url)
        status, body, location = @http_client.call(url, @token)
        return [status, body] unless REDIRECT_STATUSES.include?(status) && location.to_s != ""

        url = URI.join(url, location.to_s).to_s
      end
      raise Unavailable, I18n.t("rubylode_windmill.errors.too_many_redirects")
    end

# Checked before every request, including each redirect, so the token never leaves for an unlisted host or port, or in clear text.
def check_destination!(url)
  return if @configuration.token_destination_allowed?(url)

  uri = URI.parse(url)
  if @configuration.token_hosts.include?(uri.host.to_s.downcase) && uri.scheme != "https"
    raise Unavailable, I18n.t("rubylode_windmill.errors.plain_http_refused_at_runtime")
  end
  raise Unavailable, I18n.t("rubylode_windmill.errors.host_not_allowed", host: uri.host)
end

    def token_missing_message
      name = @configuration.token_environment_variable
      return I18n.t("rubylode_windmill.errors.token_variable_not_allowed") if name.nil?

      "#{I18n.t('rubylode_windmill.errors.token_missing')} (#{name})"
    end

    def scrub(message)
      @token.empty? ? message : message.gsub(@token, "[filtered]")
    end

    def segment(text)
      ERB::Util.url_encode(text.to_s)
    end

    def path_segments(path)
      path.to_s.split("/").map { |part| segment(part) }.join("/")
    end

    def fetch_over_http(url, token)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"
      seconds = @configuration.timeout_seconds
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: seconds, read_timeout: seconds) do |http|
        http.request(request)
      end
      [response.code.to_i, response.body, response["location"]]
    end
  end
end
