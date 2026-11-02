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

require "socket"
require "json"
require "uri"
require "time"
require "digest"

# A tiny stand-in for Windmill's REST API, for the demo and the integration tests. Standard library only.
#
# It answers the three calls the plugin makes, in the shape of Windmill's OpenAPI document, but only when the request
# carries "Authorization: Bearer <token>"; otherwise 401:
#
#   GET /api/w/demo/jobs/completed/list       completed runs, filtered by success, started_after, script_path_start,
#                                             script_path_exact, schedule_path, is_flow_step, per_page, page, order_desc
#   GET /api/w/demo/jobs_u/completed/get_result/<id>   the result of one run
#   GET /api/w/demo/schedules/get/<path>      one schedule
#
# The workspace is "demo". What it reports depends on the scenario:
#
#   failures     three paths failing, one failure that was followed by a success (must not be listed), one old failure
#                outside a 24 hour window, and a watched schedule that is late
#   all_green    every run succeeded
#   hostile      one failing script whose path and error message are HTML and script tags
#   unavailable  503, as if Windmill were broken
#
# POST /__scenario/<name> switches the scenario (no token needed); GET /__requests returns how many API calls were made;
# GET /__redirect/<port> answers 302 to http://127.0.0.1:<port>/api/w/demo/jobs/completed/list (to test redirect handling).
# Run it on its own:  FAKE_WINDMILL_TOKEN=some-token FAKE_WINDMILL_PORT=9100 ruby test/support/fake_windmill_server.rb
class FakeWindmillServer
  WORKSPACE = "demo".freeze
  SCENARIOS = %w[failures all_green hostile unavailable].freeze
  HOSTILE_ERROR = %(<script>alert("x")</script><img src=x onerror=alert(1)> & "quoted").freeze
  HOSTILE_PATH = "f/evil/<b>bold</b>".freeze

  # Schedules the demo and the tests watch. Cron is Windmill's six-field form.
  SCHEDULES = {
    "f/billing/nightly_sync" => { cron: "0 0 2 * * *", enabled: true },
    "f/reports/hourly_metrics" => { cron: "0 0 * * * *", enabled: true },
    "f/ops/heartbeat" => { cron: "0 */5 * * * *", enabled: true },
    "f/crm/weekly_digest" => { cron: "0 0 8 * * 2", enabled: false }
  }.freeze

  attr_reader :port, :request_count, :authorizations
  attr_accessor :scenario

  def initialize(token:, port: 0, scenario: "failures", host: "127.0.0.1")
    @token = token
    @host = host
    @requested_port = port
    @scenario = scenario
    @request_count = 0
    @authorizations = []
  end

  def start
    @server = TCPServer.new(@host, @requested_port)
    @port = @server.addr[1]
    @thread = Thread.new { accept_loop }
    self
  end

  def stop
    @server&.close
    @thread&.join(2)
  end

  def base_url
    "http://#{@host}:#{@port}"
  end

  # The runs of the current scenario, newest first, as Windmill would list them. Times are relative to now, and the
  # schedules last ran just after the moment they were due, so a healthy schedule stays healthy whenever you look.
  def jobs(now = Time.now)
    return [] if scenario == "unavailable"

    scenario_definitions(now).each_with_index.map { |definition, index| render(definition, index, now) }
                             .sort_by { |job| -Time.iso8601(job["started_at"]).to_f }
  end

  private

  def scenario_definitions(now)
    case scenario
    when "all_green" then green_jobs(now)
    when "hostile" then hostile_jobs
    else failure_jobs(now)
    end
  end

  def failure_jobs(now)
    [
      job("f/billing/sync_invoices", failed: true, minutes_ago: 25, error: "connection refused (billing database)"),
      job("f/reports/monthly_report", kind: "flow", failed: true, minutes_ago: 190, error: "Flow failed at step 3: the report template is missing"),
      job("u/ops/cleanup_files", failed: true, minutes_ago: 300, error: "disk quota exceeded"),
      job("u/ops/cleanup_files", minutes_ago: 240),
      job("f/crm/import_contacts", failed: true, minutes_ago: 600, error: "429 rate limited"),
      job("f/crm/import_contacts", failed: true, minutes_ago: 120, error: "429 rate limited by the CRM, retry after 3600 seconds, " + ("details " * 60)),
      job("f/legacy/old_export", failed: true, minutes_ago: 60 * 40, error: "this failure is older than the look-back window"),
      job("f/billing/nightly_sync", seconds_ago: seconds_since_daily_fire(now, 2) - 4, schedule: "f/billing/nightly_sync"),
      job("f/reports/hourly_metrics", failed: true, seconds_ago: seconds_since_hourly_fire(now) - 3, schedule: "f/reports/hourly_metrics", error: "dashboard API returned 500"),
      job("f/ops/heartbeat", minutes_ago: 180, schedule: "f/ops/heartbeat"),
      job("f/crm/weekly_digest", minutes_ago: 60 * 24 * 3, schedule: "f/crm/weekly_digest"),
      job("f/billing/sync_invoices", minutes_ago: 60 * 30)
    ]
  end

  def green_jobs(now)
    [
      job("f/billing/sync_invoices", minutes_ago: 25),
      job("f/reports/monthly_report", kind: "flow", minutes_ago: 190),
      job("f/billing/nightly_sync", seconds_ago: seconds_since_daily_fire(now, 2) - 4, schedule: "f/billing/nightly_sync"),
      job("f/reports/hourly_metrics", seconds_ago: seconds_since_hourly_fire(now) - 3, schedule: "f/reports/hourly_metrics"),
      job("f/ops/heartbeat", seconds_ago: 90, schedule: "f/ops/heartbeat"),
      job("f/crm/weekly_digest", minutes_ago: 60 * 24 * 3, schedule: "f/crm/weekly_digest")
    ]
  end

  def hostile_jobs
    [job(HOSTILE_PATH, failed: true, minutes_ago: 10, error: HOSTILE_ERROR)]
  end

  def job(path, minutes_ago: nil, seconds_ago: nil, failed: false, kind: "script", schedule: nil, error: nil)
    { path: path, kind: kind, success: !failed, seconds_ago: seconds_ago || (minutes_ago * 60), schedule: schedule, error: error }
  end

  # The same run has the same id on every call, so the list and get_result agree.
  def job_id(definition, index)
    hex = Digest::MD5.hexdigest("#{scenario}|#{index}|#{definition[:path]}")
    "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
  end

  # Seconds since the latest top of the hour that is at least 150 seconds ago (a due run gets a little time to start).
  def seconds_since_hourly_fire(now)
    elapsed = now.to_i % 3600
    elapsed >= 150 ? elapsed : elapsed + 3600
  end

  def seconds_since_daily_fire(now, hour_utc)
    elapsed = (now.to_i - (hour_utc * 3600)) % 86_400
    elapsed >= 150 ? elapsed : elapsed + 86_400
  end

  def render(definition, index, now)
    started = now - definition[:seconds_ago]
    { "id" => job_id(definition, index), "workspace_id" => WORKSPACE, "created_by" => definition[:schedule] ? "schedule" : "demo-user",
      "created_at" => started.utc.iso8601(6), "started_at" => started.utc.iso8601(6), "completed_at" => (started + 4).utc.iso8601(6),
      "duration_ms" => 4000, "success" => definition[:success], "script_path" => definition[:path], "job_kind" => definition[:kind],
      "schedule_path" => definition[:schedule], "is_flow_step" => false, "is_skipped" => false }.compact
  end

  def accept_loop
    loop do
      client = @server.accept
      Thread.new(client) { |connection| handle(connection) }
    rescue IOError, Errno::EBADF
      break
    end
  end

  def handle(client)
    request_line = client.gets.to_s
    headers = {}
    while (line = client.gets) && line != "\r\n"
      name, value = line.split(":", 2)
      headers[name.downcase] = value.to_s.strip
    end
    method, target = request_line.split(" ")
    status, body, extra_headers = respond(method, target.to_s, headers)
    client.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n#{extra_headers}Connection: close\r\n\r\n#{body}")
  rescue StandardError
    nil
  ensure
    client.close
  end

  def respond(method, target, headers)
    path, query_text = target.split("?", 2)
    query = URI.decode_www_form(query_text.to_s).to_h
    if method == "POST" && path.start_with?("/__scenario/")
      name = path.delete_prefix("/__scenario/")
      return ["404 Not Found", "{}"] unless SCENARIOS.include?(name)

      self.scenario = name
      ["200 OK", %({"scenario":"#{name}"})]
    elsif path == "/__requests"
      ["200 OK", request_count.to_s]
    elsif path.start_with?("/__redirect/")
      port = path.delete_prefix("/__redirect/").split("/").first
      ["302 Found", "{}", "Location: http://127.0.0.1:#{port}/api/w/#{WORKSPACE}/jobs/completed/list\r\n"]
    elsif path.start_with?("/api/w/#{WORKSPACE}/")
      api(path.delete_prefix("/api/w/#{WORKSPACE}"), query, headers)
    else
      ["404 Not Found", %({"error":"not found"})]
    end
  end

  def api(path, query, headers)
    @request_count += 1
    @authorizations << headers["authorization"]
    return ["503 Service Unavailable", %({"error":"windmill is unwell"})] if scenario == "unavailable"
    return ["401 Unauthorized", %({"error":"bad token"})] unless headers["authorization"] == "Bearer #{@token}"

    if path == "/jobs/completed/list"
      ["200 OK", JSON.generate(filter(jobs, query))]
    elsif path.start_with?("/jobs_u/completed/get_result/")
      result(path.delete_prefix("/jobs_u/completed/get_result/"))
    elsif path.start_with?("/schedules/get/")
      schedule(URI.decode_www_form_component(path.delete_prefix("/schedules/get/")))
    else
      ["404 Not Found", %({"error":"not found"})]
    end
  end

  def filter(all_jobs, query)
    selected = all_jobs
    selected = selected.select { |job| job["success"] == (query["success"] == "true") } if query.key?("success")
    selected = selected.select { |job| Time.iso8601(job["started_at"]) > Time.iso8601(query["started_after"]) } if query["started_after"]
    selected = selected.select { |job| query["script_path_start"].split(",").any? { |prefix| job["script_path"].start_with?(prefix) } } if query["script_path_start"]
    selected = selected.select { |job| job["script_path"] == query["script_path_exact"] } if query["script_path_exact"]
    selected = selected.select { |job| job["schedule_path"] == query["schedule_path"] } if query["schedule_path"]
    selected = selected.reverse unless query["order_desc"] == "true" # jobs come newest first already
    per_page = (query["per_page"] || 30).to_i.clamp(1, 100)
    selected.each_slice(per_page).to_a.fetch(query.fetch("page", "1").to_i - 1, [])
  end

  def result(requested_id)
    definitions = scenario_definitions(Time.now)
    index = definitions.each_index.find { |position| job_id(definitions[position], position) == requested_id }
    message = index ? definitions[index][:error] : nil
    ["200 OK", JSON.generate("error" => { "name" => "ExecutionErr", "message" => message || "unknown" })]
  end

  def schedule(path)
    definition = SCHEDULES[path]
    return ["404 Not Found", %({"error":"schedule not found"})] unless definition

    ["200 OK", JSON.generate("path" => path, "schedule" => definition[:cron], "timezone" => "UTC", "enabled" => definition[:enabled],
                             "script_path" => path, "is_flow" => false, "edited_by" => "demo", "email" => "demo@example.com",
                             "permissioned_as" => "u/demo", "extra_perms" => {})]
  end
end

if $PROGRAM_NAME == __FILE__
  server = FakeWindmillServer.new(token: ENV.fetch("FAKE_WINDMILL_TOKEN"), port: ENV.fetch("FAKE_WINDMILL_PORT", "9100").to_i,
                                  host: "0.0.0.0", scenario: ENV.fetch("FAKE_WINDMILL_SCENARIO", "failures")).start
  puts "Fake Windmill on port #{server.port}, scenario #{server.scenario}"
  $stdout.flush
  sleep
end
