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
  # What this plugin hands to Rubylode Status: one state, one line and a list of items, taken from the same report the
  # block draws. The format is in the Status plugin's docs/widget-contract.md.
  #
  # A failed run is down. A watched schedule whose latest run failed is down, a late one is a warning, one that is not
  # found or cannot be read is unknown. The block is as bad as its worst item, and an unknown item makes it a warning.
  # Windmill not answering, or the plugin not set up, makes the block unknown.
  class StatusWidget
    PAGE_PATH = "/status/windmill".freeze
    PARTIAL = "rubylode_windmill/status".freeze
    SEVERITY = { "ok" => 0, "unknown" => 1, "warning" => 2, "down" => 3 }.freeze

    # Registers the widget when Rubylode Status is installed. Returns nil, and does nothing, when it is not.
    def self.register_with_status_plugin
      return unless defined?(RubylodeStatus::Registry)

      RubylodeStatus::Registry.register(
        key: Settings::SHORT_NAME,
        title: -> { Settings.current.block_title },
        path: PAGE_PATH,
        data: -> { data },
        partial: PARTIAL,
        visibility: -> { Settings.current.visibility }
      )
    end

    def self.data(settings = Settings.current)
      new(settings).data
    end

    def initialize(settings)
      @settings = settings
    end

    def data
      return { state: "unknown", summary: I18n.t("rubylode_windmill.status.not_set_up"), items: [] } unless @settings.configured?

      report = WindmillStatus.safe_report(@settings)
      return { state: "unknown", summary: report.summary, items: [] } if report.unavailable?

      items = report.rows.map { |row| failed_run_item(row) } + report.schedules.map { |schedule| schedule_item(schedule) }
      { state: block_state(items), summary: report.summary, items: items }
    end

    private

    def failed_run_item(row)
      detail = row.error.to_s
      detail = I18n.t("rubylode_windmill.status.failed_times", error: detail, count: row.failure_count) if row.failure_count > 1
      { name: row.path, state: "down", detail: detail }
    end

    def schedule_item(schedule)
      state, detail_key = schedule_state(schedule)
      { name: schedule.name, state: state, detail: detail_key && I18n.t("rubylode_windmill.status.#{detail_key}") }
    end

    def schedule_state(schedule)
      verdict = schedule.verdict
      return ["unknown", :unknown] if schedule.unreadable
      return ["unknown", :missing] unless schedule.found
      return ["down", :last_run_failed] if verdict.last_result == :failure
      return ["warning", :overdue] if verdict.overdue?

      ["ok", verdict.last_result == :none ? :none : nil]
    end

    def block_state(items)
      worst = items.map { |item| item[:state] }.max_by { |state| SEVERITY.fetch(state) } || "ok"
      worst == "unknown" ? "warning" : worst
    end
  end
end
