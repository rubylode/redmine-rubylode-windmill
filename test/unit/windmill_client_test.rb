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

class RubylodeWindmill::WindmillClientTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  TOKEN = "unit-token-DO-NOT-LEAK-91ac".freeze
  RUN_ID = "0b6a2b8e-7d52-4d0e-9c0f-3a1f6f1d2e44".freeze

  setup do
    ENV[TOKEN_VARIABLE] = TOKEN
    @calls = []
  end

  teardown do
    ENV.delete(TOKEN_VARIABLE)
    ENV.delete("SECRET_KEY_BASE")
  end

  def client_for(answers, overrides = {})
    configuration = configuration_with({ "token_environment_variable" => TOKEN_VARIABLE }.merge(overrides))
    transport = lambda do |url, token|
      @calls << [url, token]
      answers.respond_to?(:call) ? answers.call(url, token) : answers
    end
    RubylodeWindmill::WindmillClient.new(configuration: configuration, http_client: transport)
  end

  def job_json(overrides = {})
    { "id" => RUN_ID, "script_path" => "f/a/one", "job_kind" => "script", "success" => false,
      "started_at" => "2026-11-04T11:00:00.123456Z", "completed_at" => "2026-11-04T11:00:04.000000Z" }.merge(overrides)
  end

  test "failed runs are asked for with the bearer token and the documented filters" do
    client = client_for([200, [job_json].to_json])
    client.failed_runs(now: Time.utc(2026, 11, 4, 12, 0, 0))

    url, token = @calls.first
    assert_equal TOKEN, token
    uri = URI(url)
    assert_equal "/api/w/demo/jobs/completed/list", uri.path
    query = URI.decode_www_form(uri.query).to_h
    assert_equal "false", query["success"]
    assert_equal "false", query["is_flow_step"]
    assert_equal "2026-11-03T12:00:00.000Z", query["started_after"]
    assert_equal "100", query["per_page"]
    refute query.key?("script_path_start")
  end

  test "a path prefix is passed on" do
    client = client_for([200, "[]"], "path_prefix" => "f/billing/")
    client.failed_runs

    assert_equal "f/billing/", URI.decode_www_form(URI(@calls.first.first).query).to_h["script_path_start"]
  end

  test "a failed run is read into path, kind and times, with the error when the list carries the result" do
    run = client_for([200, [job_json("result" => { "error" => { "message" => "boom" } }), job_json("id" => "x", "job_kind" => "flow")].to_json]).failed_runs.first

    assert_equal ["f/a/one", "script", "boom"], [run.path, run.kind, run.error]
    assert_equal Time.utc(2026, 11, 4, 11, 0, 0, 123_456), run.started_at
    assert_equal Time.utc(2026, 11, 4, 11, 0, 4), run.failed_at
  end

  test "a list without results leaves the error empty to be fetched later" do
    assert_nil client_for([200, [job_json].to_json]).failed_runs.first.error
  end

  test "recovered asks for a success of the same path after the failure" do
    client = client_for([200, [job_json("success" => true)].to_json])
    failed = RubylodeWindmill::AttentionRule::FailedRun.new("1", "f/a/one", "script", Time.utc(2026, 11, 4, 11, 0, 0), Time.utc(2026, 11, 4, 11, 0, 4), nil)

    assert client.recovered?(failed)
    query = URI.decode_www_form(URI(@calls.first.first).query).to_h
    assert_equal "true", query["success"]
    assert_equal "f/a/one", query["script_path_exact"]
    assert_equal "2026-11-04T11:00:00.000Z", query["started_after"]
    refute client_for([200, "[]"]).recovered?(failed)
  end

  test "the error of one run is fetched from the result endpoint" do
    client = client_for([200, { "error" => { "message" => "kaput" } }.to_json])

    assert_equal "kaput", client.error_summary_for(RUN_ID)
    assert_equal "/api/w/demo/jobs_u/completed/get_result/#{RUN_ID}", URI(@calls.first.first).path
  end

  test "a schedule is read from its path, a missing one is nil" do
    body = { "path" => "f/a/nightly", "schedule" => "0 0 2 * * *", "timezone" => "UTC", "enabled" => true, "script_path" => "f/a/job", "is_flow" => false }.to_json
    schedule = client_for([200, body]).schedule("f/a/nightly")

    assert_equal "/api/w/demo/schedules/get/f/a/nightly", URI(@calls.first.first).path
    assert_equal ["0 0 2 * * *", "UTC", true], [schedule[:cron], schedule[:timezone], schedule[:enabled]]
    assert_nil client_for([404, "{}"]).schedule("f/a/none")
  end

  test "the latest run of a schedule" do
    run = client_for([200, [job_json("success" => true)].to_json]).latest_schedule_run("f/a/nightly")

    assert_equal [RUN_ID, true], [run[:id], run[:success]]
    assert_equal "f/a/nightly", URI.decode_www_form(URI(@calls.first.first).query).to_h["schedule_path"]
    assert_nil client_for([200, "[]"]).latest_schedule_run("f/a/nightly")
  end

  test "a non 200 answer, a bad body and a network error are each Unavailable" do
    assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for([500, ""]).failed_runs }
    assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for([200, "not json"]).failed_runs }
    assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for([200, "{}"]).failed_runs }
    error = assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for(->(*) { raise Errno::ECONNREFUSED }).failed_runs }
    assert_includes error.message, "Errno::ECONNREFUSED"
  end

  test "a missing token is Unavailable and names the variable, never a value" do
    ENV.delete(TOKEN_VARIABLE)
    error = assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for([200, "[]"]).failed_runs }

    assert_includes error.message, TOKEN_VARIABLE
    assert_empty @calls
  end

  test "the token never appears in an error message" do
    error = assert_raises(RubylodeWindmill::WindmillClient::Unavailable) do
      client_for(->(*) { raise RubylodeWindmill::WindmillClient::Unavailable, "echo #{TOKEN}" }).failed_runs
    end
    refute_includes error.message, TOKEN
    assert_includes error.message, "[filtered]"
  end

  test "SECRET_KEY_BASE as the variable name is ignored: nothing is read and nothing is sent" do
    ENV["SECRET_KEY_BASE"] = "the-rails-secret-key-base"
    error = assert_raises(RubylodeWindmill::WindmillClient::Unavailable) do
      client_for([200, "[]"], "token_environment_variable" => "SECRET_KEY_BASE").failed_runs
    end

    assert_empty @calls
    refute_includes error.message, "the-rails-secret-key-base"
  end

  test "plain http to a host that is not loopback is refused before anything is sent" do
    assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for([200, "[]"], "base_url" => "http://windmill.internal").failed_runs }
    assert_empty @calls

    client_for([200, "[]"], "base_url" => "http://windmill.internal", "allow_plain_http" => "1").failed_runs
    assert_equal 1, @calls.size
    @calls.clear
    client_for([200, "[]"], "base_url" => "http://localhost:8000").failed_runs
    assert_equal 1, @calls.size
  end

  test "a redirect to another host is refused and the token is never sent there" do
    answers = lambda do |url, _token|
      URI(url).host == "windmill.example.com" ? [302, "", "https://evil.example.net/steal"] : [200, "[]"]
    end
    error = assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for(answers).failed_runs }

    assert_equal ["windmill.example.com"], @calls.map { |url, _| URI(url).host }
    assert_includes error.message, "evil.example.net"
  end

  test "a redirect to a listed host is followed, one to plain http on that host is not" do
    to_alias = ->(url, _token) { URI(url).host == "windmill.example.com" ? [302, "", "https://alias.example.com/api/x"] : [200, "[]"] }
    client_for(to_alias, "allowed_hosts" => "alias.example.com").failed_runs
    assert_equal %w[windmill.example.com alias.example.com], @calls.map { |url, _| URI(url).host }

    @calls.clear
    downgrade = ->(url, _token) { URI(url).scheme == "https" ? [302, "", "http://windmill.example.com/api/x"] : [200, "[]"] }
    assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for(downgrade).failed_runs }
    assert_equal 1, @calls.size
  end

  test "redirect loops stop" do
    assert_raises(RubylodeWindmill::WindmillClient::Unavailable) { client_for([302, "", "https://windmill.example.com/loop"]).failed_runs }
    assert_equal 4, @calls.size
  end
end
