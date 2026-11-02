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

class RubylodeWindmill::WindmillStatusTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  NOW = Time.utc(2026, 11, 4, 12, 7, 30)

  # Stands in for the client: answers from plain data and counts how often it is asked.
  class StubClient
    attr_reader :asked

    def initialize(failed:, recovered: [], schedules: {}, runs: {}, unavailable: false)
      @failed = failed
      @recovered = recovered
      @schedules = schedules
      @runs = runs
      @unavailable = unavailable
      @asked = 0
    end

    def failed_runs(**)
      @asked += 1
      raise RubylodeWindmill::WindmillClient::Unavailable, "Windmill answered 503" if @unavailable

      @failed
    end

    def recovered?(run)
      @recovered.include?(run.path)
    end

    def error_summary_for(_run_id)
      "fetched error"
    end

    def schedule(path)
      @schedules[path]
    end

    def latest_schedule_run(path)
      @runs[path]
    end
  end

  def failed(path, minutes_ago)
    started = NOW - (minutes_ago * 60)
    RubylodeWindmill::AttentionRule::FailedRun.new("id-#{path}", path, "script", started, started, nil)
  end

  def status_for(client, overrides = {})
    @cache = ActiveSupport::Cache::MemoryStore.new
    RubylodeWindmill::WindmillStatus.new(configuration: configuration_with(overrides), cache: @cache, client: client)
  end

  test "no failures and no schedules says nothing needs attention" do
    report = status_for(StubClient.new(failed: [])).report(now: NOW)

    assert_equal "Nothing needs attention", report.summary
    assert_equal :ok, report.summary_state
    refute report.unavailable?
  end

  test "failures are counted and recovered ones are left out" do
    client = StubClient.new(failed: [failed("f/a/one", 10), failed("f/a/two", 20), failed("f/a/three", 30)], recovered: ["f/a/two"])
    report = status_for(client).report(now: NOW)

    assert_equal "2 failing", report.summary
    assert_equal :attention, report.summary_state
    assert_equal %w[f/a/one f/a/three], report.rows.map(&:path)
    assert_equal ["fetched error"], report.rows.map(&:error).uniq
  end

  test "the rows are cut at the maximum and the rest is counted" do
    client = StubClient.new(failed: (1..5).map { |number| failed("f/a/job#{number}", number) })
    report = status_for(client, "maximum_rows" => "2").report(now: NOW)

    assert_equal "5 failing", report.summary
    assert_equal 2, report.shown_rows.size
    assert_equal 3, report.hidden_count
  end

  test "a watched schedule shows its last run and is flagged when late" do
    schedules = { "f/reports/hourly_metrics" => { enabled: true, cron: "0 0 * * * *", timezone: "UTC" },
                  "f/ops/heartbeat" => { enabled: true, cron: "0 */5 * * * *", timezone: "UTC" },
                  "f/billing/nightly_sync" => nil }
    runs = { "f/reports/hourly_metrics" => { id: "r1", success: true, started_at: NOW - 400 },
             "f/ops/heartbeat" => { id: "r2", success: true, started_at: NOW - (3 * 3600) } }
    report = status_for(StubClient.new(failed: [], schedules: schedules, runs: runs), "watched_schedules" => SAMPLE_SCHEDULES).report(now: NOW)
    by_path = report.schedules.index_by(&:path)

    refute by_path["f/reports/hourly_metrics"].needs_attention?
    assert by_path["f/ops/heartbeat"].verdict.overdue?
    assert by_path["f/billing/nightly_sync"].needs_attention?
    refute by_path["f/billing/nightly_sync"].found
    assert_equal "2 schedules need a look", report.summary
  end

  test "failing runs and late schedules appear together in the summary" do
    schedules = { "f/ops/heartbeat" => { enabled: true, cron: "0 */5 * * * *", timezone: "UTC" } }
    client = StubClient.new(failed: [failed("f/a/one", 5)], schedules: schedules, runs: {})
    report = status_for(client, "watched_schedules" => "Heartbeat | f/ops/heartbeat | x").report(now: NOW)

    assert_equal "1 failing, 1 schedule needs a look", report.summary
  end

  test "an unavailable Windmill gives the fallback report with the reason" do
    report = status_for(StubClient.new(failed: [], unavailable: true)).report(now: NOW)

    assert report.unavailable?
    assert_equal "Status unavailable", report.summary
    assert_equal :unavailable, report.summary_state
    assert_equal "Windmill answered 503", report.failure_reason
  end

  test "an answer is cached for the cache seconds and a failure for the failure seconds" do
    client = StubClient.new(failed: [failed("f/a/one", 5)])
    status = status_for(client)
    2.times { status.report(now: NOW) }
    assert_equal 1, client.asked

    broken = StubClient.new(failed: [], unavailable: true)
    broken_status = status_for(broken)
    2.times { broken_status.report(now: NOW) }
    assert_equal 1, broken.asked
  end

  test "zero cache seconds asks every time" do
    client = StubClient.new(failed: [])
    status = status_for(client, "cache_seconds" => "0")
    2.times { status.report(now: NOW) }

    assert_equal 2, client.asked
  end

  test "an unreadable schedule does not take the failures down with it" do
    client = StubClient.new(failed: [failed("f/a/one", 5)])
    def client.schedule(_path)
      raise RubylodeWindmill::WindmillClient::Unavailable, "boom"
    end
    report = status_for(client, "watched_schedules" => "Heartbeat | f/ops/heartbeat | x").report(now: NOW)

    refute report.unavailable?
    assert report.schedules.first.unreadable
    assert_equal 1, report.rows.size
  end
end
