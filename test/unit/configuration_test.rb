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

class RubylodeWindmill::ConfigurationTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  test "a fresh install has the documented defaults" do
    configuration = RubylodeWindmill::Configuration.new({})

    assert_equal 24, configuration.look_back_hours
    assert_equal 10, configuration.maximum_rows
    assert_equal 60, configuration.cache_seconds
    assert_equal 30, configuration.failure_cache_seconds
    assert_equal 2, configuration.timeout_seconds
    assert_equal "Windmill", configuration.block_title
    assert_equal "logged_in", configuration.visibility
    assert_equal "WINDMILL_API_TOKEN", configuration.token_environment_variable
    refute configuration.configured?
  end

  test "the address loses a trailing slash and is configured with a workspace" do
    configuration = configuration_with("windmill_url" => "https://windmill.example.com/")

    assert_equal "https://windmill.example.com", configuration.windmill_url
    assert configuration.configured?
    refute configuration_with("workspace_id" => "").configured?
  end

  test "numbers below their minimum or not numbers fall back" do
    configuration = configuration_with("look_back_hours" => "0", "maximum_rows" => "abc", "timeout_seconds" => "0", "cache_seconds" => "-5")

    assert_equal 1, configuration.look_back_hours
    assert_equal 10, configuration.maximum_rows
    assert_equal 1, configuration.timeout_seconds
    assert_equal 0, configuration.cache_seconds
  end

  test "only a variable name starting with WINDMILL_ is ever read from the environment" do
    ENV["SECRET_KEY_BASE"] = "must-never-be-read"
    ENV["DATABASE_PASSWORD"] = "must-never-be-read-either"
    %w[SECRET_KEY_BASE DATABASE_PASSWORD windmill_lower PATH].each do |name|
      configuration = configuration_with("token_environment_variable" => name)
      assert_nil configuration.token_environment_variable, name
      assert_equal "", configuration.token, name
    end
  ensure
    ENV.delete("SECRET_KEY_BASE")
    ENV.delete("DATABASE_PASSWORD")
  end

  test "an allowed variable name is read" do
    ENV["WINDMILL_UNIT_TEST_TOKEN"] = "abc"
    assert_equal "abc", configuration_with("token_environment_variable" => "WINDMILL_UNIT_TEST_TOKEN").token
  ensure
    ENV.delete("WINDMILL_UNIT_TEST_TOKEN")
  end

  test "an empty variable name means the default name" do
    assert_equal "WINDMILL_API_TOKEN", configuration_with("token_environment_variable" => " ").token_environment_variable
  end

  test "the token may go to the Windmill host and to the listed hosts, nowhere else" do
    configuration = configuration_with("allowed_hosts" => "Alias.example.com, other.example.com")

    assert_equal %w[windmill.example.com alias.example.com other.example.com], configuration.token_hosts
  end

  test "https is accepted, plain http only for loopback or when allowed" do
    strict = configuration_with
    assert strict.plain_http_acceptable?("https://windmill.example.com/api")
    refute strict.plain_http_acceptable?("http://windmill.example.com/api")
    assert strict.plain_http_acceptable?("http://localhost:8000/api")
    assert strict.plain_http_acceptable?("http://127.0.0.1:8000/api")
    refute strict.plain_http_acceptable?("ftp://windmill.example.com")
    assert configuration_with("allow_plain_http" => "1").plain_http_acceptable?("http://windmill.internal/api")
  end

  test "who may see the block" do
    everyone = configuration_with
    admins = configuration_with("visibility" => "admins")
    anonymous = User.anonymous
    regular = User.new.tap { |user| user.admin = false }
    regular.define_singleton_method(:logged?) { true }

    refute everyone.visible_to?(anonymous)
    assert everyone.visible_to?(regular)
    refute admins.visible_to?(regular)
  end

  test "the cache fingerprint changes with the settings that change the answer" do
    base = configuration_with.cache_fingerprint

    refute_equal base, configuration_with("path_prefix" => "f/").cache_fingerprint
    refute_equal base, configuration_with("look_back_hours" => "48").cache_fingerprint
    assert_equal base, configuration_with("block_title" => "Other").cache_fingerprint
  end
end

class RubylodeWindmill::ConfigurationPlacementTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  test "the block is shown nowhere extra on a fresh install" do
    configuration = RubylodeWindmill::Configuration.new({})

    refute configuration.show_on_welcome_page?
    refute configuration.show_on_my_page?
    refute configuration.show_on_project_overview?
    refute configuration.show_on_matching_pages?
    refute configuration.show_in_top_menu?
    assert_equal "right", configuration.welcome_page_column
    assert_equal "right", configuration.project_overview_column
  end

  test "placements are switched on by their flags and columns fall back to right" do
    configuration = configuration_with("show_on_welcome_page" => "1", "welcome_page_column" => "left", "show_on_project_overview" => "1",
                                       "project_overview_column" => "sideways", "show_in_top_menu" => "1")

    assert configuration.show_on_welcome_page?
    assert_equal "left", configuration.welcome_page_column
    assert_equal "right", configuration.project_overview_column
    assert configuration.show_in_top_menu?
  end

  test "matching pages need the flag and at least one path" do
    refute configuration_with("show_on_matching_pages" => "1").show_on_matching_pages?
    refute configuration_with("matching_page_paths" => "/issues").show_on_matching_pages?
    configuration = configuration_with("show_on_matching_pages" => "1", "matching_page_paths" => "# note\n/issues\n/projects/*/issues")

    assert configuration.show_on_matching_pages?
    assert_equal ["/issues", "/projects/*/issues"], configuration.matching_page_paths
  end
end
