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
  # What the block shows: the failed runs that still need attention, and the latest run of each watched schedule.
  #
  # Windmill is asked through a loader and the answer (a plain hash, no times in the future, no secrets) is cached. A
  # failed answer is cached too, for a shorter time, so a broken Windmill is not hammered. Judging the schedules (late or
  # not) happens when the report is built, from the cached times, so "late" stays right between refreshes.
  class WindmillStatus
    ScheduleState = Struct.new(:name, :path, :description, :found, :unreadable, :verdict, :last_run_id) do
      def needs_attention?
        unreadable || !found || verdict&.needs_attention? || false
      end
    end
    Report = Struct.new(:rows, :shown_rows, :hidden_count, :schedules, :summary, :summary_state, :unavailable, :failure_reason) do
      alias_method :unavailable?, :unavailable

      def failing_count
        rows.size
      end
    end

    FAILURE_MARKER = "windmill-unavailable".freeze
    MAXIMUM_PATHS_CHECKED = 30

    class << self
      attr_writer :cache

      def cache
        @cache ||= Rails.cache
      end

      def cache_key_for(configuration)
        "rubylode_windmill/status/#{configuration.cache_fingerprint}"
      end

      # The report for a page. Whatever goes wrong while building it, the page gets a "status unavailable" report and never an error.
      def safe_report(configuration = Configuration.current)
        current(configuration).report
      rescue StandardError => error
        Rails.logger.warn("Rubylode Windmill: could not build the status block: #{error.class}: #{error.message}")
        Report.new([], [], 0, [], I18n.t("rubylode_windmill.status.unavailable"), :unavailable, true, error.class.name)
      end

      def current(configuration = Configuration.current)
        new(configuration: configuration, cache: cache)
      end
    end

    def initialize(configuration:, cache:, client: nil)
      @configuration = configuration
      @cache = cache
      @client = client
    end

    def report(now: Time.current)
      snapshot = cached_snapshot
      rows = snapshot["failing"].map { |row| row_from(row) }
      schedules = snapshot["schedules"].map { |entry| schedule_state_from(entry, now) }
      shown = rows.first(@configuration.maximum_rows)
      Report.new(rows, shown, rows.size - shown.size, schedules, summary_for(rows, schedules),
                 rows.empty? && schedules.none?(&:needs_attention?) ? :ok : :attention, false, nil)
    rescue WindmillClient::Unavailable => error
      Report.new([], [], 0, [], I18n.t("rubylode_windmill.status.unavailable"), :unavailable, true, error.message)
    end

    private

    def cached_snapshot
      snapshot = read_cache
      if snapshot.nil?
        begin
          snapshot = load_snapshot
          write_cache(snapshot, @configuration.cache_seconds)
        rescue WindmillClient::Unavailable => error
          snapshot = "#{FAILURE_MARKER}|#{error.message}"
          write_cache(snapshot, @configuration.failure_cache_seconds)
        end
      end
      raise WindmillClient::Unavailable, failure_reason_from(snapshot) if snapshot.is_a?(String)

      snapshot
    end

    # A cache that cannot be read or written (a file owned by another user, a full disk) is a miss, not an error.
    def read_cache
      @cache.read(self.class.cache_key_for(@configuration))
    rescue StandardError => error
      log_cache_problem("read", error)
      nil
    end

    def write_cache(value, seconds)
      @cache.write(self.class.cache_key_for(@configuration), value, expires_in: seconds) if seconds.positive?
    rescue StandardError => error
      log_cache_problem("write", error)
    end

    def log_cache_problem(action, error)
      Rails.logger.warn("Rubylode Windmill: cache #{action} failed, carrying on without it: #{error.class}: #{error.message}")
    end

    def failure_reason_from(marker)
      reason = marker.split("|", 2)[1].to_s
      reason.empty? ? I18n.t("rubylode_windmill.errors.windmill_did_not_answer") : reason
    end

    def client
      @client ||= WindmillClient.from_configuration(@configuration)
    end

    def load_snapshot
      { "failing" => failing_rows.map { |row| row_to_hash(row) }, "schedules" => @configuration.watched_schedules.map { |watched| schedule_entry(watched) } }
    end

    def failing_rows
      checked = 0
      recovered = lambda do |run|
        checked += 1
        checked <= MAXIMUM_PATHS_CHECKED && client.recovered?(run)
      end
      rows = AttentionRule.call(client.failed_runs, recovered: recovered)
      rows.each_with_index.map do |row, index|
        next row unless row.error.nil?
        next row.tap { |unfetched| unfetched.error = I18n.t("rubylode_windmill.errors.no_error_message") } if index >= @configuration.maximum_rows

        row.tap { |fetched| fetched.error = fetch_error(row.run_id) }
      end
    end

    def fetch_error(run_id)
      client.error_summary_for(run_id)
    rescue WindmillClient::Unavailable
      I18n.t("rubylode_windmill.errors.no_error_message")
    end

    def row_to_hash(row)
      { "run_id" => row.run_id, "path" => row.path, "kind" => row.kind, "started_at" => row.started_at.to_f,
        "failed_at" => row.failed_at.to_f, "error" => row.error, "failure_count" => row.failure_count }
    end

    def row_from(hash)
      AttentionRule::Row.new(hash["run_id"], hash["path"], hash["kind"], Time.at(hash["started_at"]), Time.at(hash["failed_at"]),
                             hash["error"], hash["failure_count"])
    end

    def schedule_entry(watched)
      entry = { "name" => watched.name, "path" => watched.path, "description" => watched.description, "found" => false, "unreadable" => false }
      schedule = client.schedule(watched.path)
      return entry if schedule.nil?

      run = client.latest_schedule_run(watched.path)
      entry.merge("found" => true, "enabled" => schedule[:enabled], "cron" => schedule[:cron], "timezone" => schedule[:timezone],
                  "last_run" => run && { "id" => run[:id], "success" => run[:success], "started_at" => run[:started_at].to_f })
    rescue WindmillClient::Unavailable
      entry.merge("unreadable" => true)
    end

    def schedule_state_from(entry, now)
      verdict = if entry["found"]
        last_run = entry["last_run"] && { id: entry["last_run"]["id"], success: entry["last_run"]["success"],
                                          started_at: Time.at(entry["last_run"]["started_at"]) }
        ScheduleCheck.verdict(enabled: entry["enabled"], cron_expression: entry["cron"], timezone: entry["timezone"], last_run: last_run, now: now)
      end
      ScheduleState.new(entry["name"], entry["path"], entry["description"], entry["found"], entry["unreadable"], verdict,
                        verdict&.last_run_id)
    end

    def summary_for(rows, schedules)
      problems = schedules.count(&:needs_attention?)
      return I18n.t("rubylode_windmill.status.nothing_needs_attention") if rows.empty? && problems.zero?

      parts = []
      parts << I18n.t("rubylode_windmill.status.failing", count: rows.size) if rows.any?
      parts << I18n.t("rubylode_windmill.status.schedules_need_a_look", count: problems) if problems.positive?
      parts.join(", ")
    end
  end
end
