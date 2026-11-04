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

require File.expand_path("../../../test/test_helper", __dir__)
require "logger"
require "stringio"
require_relative "support/fake_windmill_server"

module RubylodeWindmillTestHelpers
  PLUGIN_ID = RubylodeWindmill::Settings::PLUGIN_ID
  TOKEN_VARIABLE = "WINDMILL_TEST_TOKEN".freeze

  SAMPLE_SCHEDULES = <<~TEXT.freeze
    Nightly sync | f/billing/nightly_sync | Copies invoices at 02:00
    Hourly metrics | f/reports/hourly_metrics | Refreshes the dashboard
    Heartbeat | f/ops/heartbeat | Pings the office
  TEXT

  def configuration_with(overrides = {})
    RubylodeWindmill::Settings.new(
      RubylodeWindmill::Settings::DEFAULTS.merge(
        "base_url" => "https://windmill.example.com", "workspace_id" => "demo"
      ).merge(overrides.transform_keys(&:to_s))
    )
  end

  def configure_plugin(overrides = {})
    settings = RubylodeWindmill::Settings::DEFAULTS.merge(
      "base_url" => "https://windmill.example.com",
      "workspace_id" => "demo",
      "token_environment_variable" => TOKEN_VARIABLE,
      "watched_schedules" => SAMPLE_SCHEDULES
    ).merge(overrides.transform_keys(&:to_s))
    Setting.send(:"plugin_#{PLUGIN_ID}=", settings)
  end

  def use_memory_cache
    @original_cache = RubylodeWindmill::WindmillStatus.cache
    RubylodeWindmill::WindmillStatus.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def restore_cache
    RubylodeWindmill::WindmillStatus.cache = @original_cache
  end

  # A cache store that fails the way a cache file owned by another user does.
  class UnwritableCache
    def initialize(read: true, write: true)
      @fail_read = read
      @fail_write = write
    end

    def read(*)
      raise Errno::EACCES, "@ apply2files - /var/cache/entry" if @fail_read
    end

    def write(*)
      raise Errno::EACCES, "@ apply2files - /var/cache/entry" if @fail_write
    end
  end

  # Runs the block with Rails.logger writing into a string, and returns that string.
  def captured_log
    output = StringIO.new
    replacing_method(Rails, :logger, ->(*) { Logger.new(output) }) { yield }
    output.string
  end

  # Minitest 6 ships without stubs, so a singleton method is swapped by hand for the length of the block.
  def replacing_method(target, name, replacement)
    original = target.method(name)
    target.define_singleton_method(name) { |*arguments, &block| replacement.call(*arguments, &block) }
    yield
  ensure
    target.define_singleton_method(name) { |*arguments, &block| original.call(*arguments, &block) }
  end

  # Starts the fake Windmill, puts its address and token into the settings and the environment, and cleans up after.
  def start_fake_windmill(scenario: "failures", token: "sample-token-DO-NOT-LEAK-7f3a91", **overrides)
    @fake_windmill = FakeWindmillServer.new(token: token, scenario: scenario).start
    @fake_token = token
    ENV[TOKEN_VARIABLE] = token
    configure_plugin({ "base_url" => @fake_windmill.base_url }.merge(overrides))
  end

  def stop_fake_windmill
    ENV.delete(TOKEN_VARIABLE)
    @fake_windmill&.stop
  end

  # Stands in for the Status plugin: this plugin is tested alone, so the registry it would register with is a plain
  # object that remembers the arguments. The real one is checked by the Status plugin's own tests.
  def with_fake_status_registry
    raise "RubylodeStatus is already defined" if defined?(RubylodeStatus)

    installed = false
    registry = Module.new do
      @widgets = {}
      class << self
        attr_reader :widgets

        def register(key:, title:, path:, data:, partial: nil, visibility: "logged_in")
          @widgets[key.to_s] = { title: title, path: path, data: data, partial: partial, visibility: visibility }
        end
      end
    end
    Object.const_set(:RubylodeStatus, Module.new)
    installed = true
    RubylodeStatus.const_set(:Registry, registry)
    yield registry
  ensure
    Object.send(:remove_const, :RubylodeStatus) if installed
  end

  def at_hour(hour_utc, minute = 30)
    now = Time.now.utc
    Time.utc(now.year, now.month, now.day, hour_utc, minute, 0)
  end
end
