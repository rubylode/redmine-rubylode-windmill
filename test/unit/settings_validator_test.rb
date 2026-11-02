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

class RubylodeWindmill::SettingsValidatorTest < ActiveSupport::TestCase
  GOOD = RedmineRubylodeWindmill::Defaults::SETTINGS.merge(
    "windmill_url" => "https://windmill.example.com", "workspace_id" => "demo",
    "watched_schedules" => "Sync | f/billing/sync | Copies"
  ).freeze

  def errors_for(overrides = {})
    RubylodeWindmill::SettingsValidator.errors_for(GOOD.merge(overrides))
  end

  test "good settings and an empty fresh install have no errors" do
    assert_empty errors_for
    assert_empty RubylodeWindmill::SettingsValidator.errors_for(RedmineRubylodeWindmill::Defaults::SETTINGS)
  end

  test "SECRET_KEY_BASE and DATABASE_PASSWORD are refused as the token variable" do
    %w[SECRET_KEY_BASE DATABASE_PASSWORD RAILS_MASTER_KEY WINDMILL-TOKEN windmill_token].each do |name|
      assert errors_for("token_environment_variable" => name).any? { |message| message.include?("WINDMILL_") }, name
    end
    assert_empty errors_for("token_environment_variable" => "WINDMILL_PRODUCTION_TOKEN")
  end

  test "plain http is refused unless the host is loopback or plain http is allowed" do
    assert errors_for("windmill_url" => "http://windmill.internal").any? { |message| message.include?("https") }
    assert_empty errors_for("windmill_url" => "http://localhost:8000")
    assert_empty errors_for("windmill_url" => "http://windmill.internal", "allow_plain_http" => "1")
  end

  test "a bad address, workspace, host list, title, visibility and numbers are each reported" do
    assert errors_for("windmill_url" => "ftp://x").any?
    assert errors_for("workspace_id" => "has space").any?
    assert errors_for("allowed_hosts" => "bad host!").any?
    assert errors_for("block_title" => " ").any?
    assert errors_for("visibility" => "everyone").any?
    assert errors_for("look_back_hours" => "0").any?
    assert errors_for("maximum_rows" => "ten").any?
  end

  test "a bad schedule line gives a message with the line number" do
    messages = errors_for("watched_schedules" => "Sync | f/a/b | x\nbroken")

    assert_equal 1, messages.size
    assert_includes messages.first, "line 2"
  end
end

class RubylodeWindmill::SettingsValidatorPlacementTest < ActiveSupport::TestCase
  GOOD_PLACEMENT = RubylodeWindmill::SettingsValidatorTest::GOOD.merge("show_on_matching_pages" => "1", "matching_page_paths" => "/issues\n/projects/*/issues")

  def errors_for(overrides = {})
    RubylodeWindmill::SettingsValidator.errors_for(GOOD_PLACEMENT.merge(overrides))
  end

  test "good paths and columns pass" do
    assert_empty errors_for
    assert_empty errors_for("welcome_page_column" => "left", "project_overview_column" => "right")
  end

  test "a path without a leading slash, with a host or a scheme is refused with its line number" do
    ["issues", "//evil.example.com/x", "https://evil.example.com/x", "/has space", "/a<b"].each do |bad|
      messages = errors_for("matching_page_paths" => "/issues\n#{bad}")
      assert_equal 1, messages.size, bad
      assert_includes messages.first, "line 2", bad
    end
  end

  test "an over-long path and too many paths are refused" do
    assert errors_for("matching_page_paths" => "/#{'a' * 250}").any?
    assert errors_for("matching_page_paths" => (1..60).map { |number| "/page#{number}" }.join("\n")).any? { |message| message.include?("At most") }
  end

  test "a column must be left or right" do
    assert errors_for("welcome_page_column" => "middle").any?
  end
end
