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
load File.expand_path("../../db/migrate/001_rename_windmill_url_to_base_url.rb", __dir__)

class RubylodeWindmill::SettingsMigrationTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  SETTING_NAME = "plugin_#{PLUGIN_ID}".freeze

  setup do
    Setting.where(name: SETTING_NAME).delete_all
    Setting.clear_cache
  end

  def saved_settings
    Setting.clear_cache
    Setting.find_by(name: SETTING_NAME)&.value
  end

  def save_settings(hash)
    record = Setting.find_or_initialize_by(name: SETTING_NAME)
    record.value = hash
    record.save!
    Setting.clear_cache
  end

  def migrate(direction)
    ActiveRecord::Migration.suppress_messages { RenameWindmillUrlToBaseUrl.new.public_send(direction) }
  end

  test "up moves the saved address to base_url and keeps every other setting" do
    save_settings("windmill_url" => "https://windmill.example.com", "workspace_id" => "ops", "block_title" => "Automation")

    migrate(:up)

    assert_equal({ "base_url" => "https://windmill.example.com", "workspace_id" => "ops", "block_title" => "Automation" }, saved_settings)
  end

  test "down moves base_url back to windmill_url" do
    save_settings("base_url" => "https://windmill.example.com", "workspace_id" => "ops")

    migrate(:down)

    assert_equal({ "windmill_url" => "https://windmill.example.com", "workspace_id" => "ops" }, saved_settings)
  end

  test "up and then down gives back the settings that were saved" do
    original = { "windmill_url" => "https://windmill.example.com", "workspace_id" => "ops" }
    save_settings(original)

    migrate(:up)
    migrate(:down)

    assert_equal original, saved_settings
  end

  test "nothing is written when nothing was saved" do
    migrate(:up)
    assert_nil saved_settings

    migrate(:down)
    assert_nil saved_settings
  end

  test "nothing changes when the settings were saved without the old key" do
    save_settings("base_url" => "https://windmill.example.com")

    migrate(:up)

    assert_equal({ "base_url" => "https://windmill.example.com" }, saved_settings)
  end

  test "a base_url that is already filled in is kept" do
    save_settings("windmill_url" => "https://old.example.com", "base_url" => "https://new.example.com")

    migrate(:up)

    assert_equal({ "base_url" => "https://new.example.com" }, saved_settings)
  end
end
