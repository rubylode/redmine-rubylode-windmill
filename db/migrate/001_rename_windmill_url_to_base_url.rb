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

# Version 2.0.0 calls the Windmill address base_url, as the other Rubylode plugins do. This moves the saved value.
# It changes only settings that were saved: a fresh install has no row and gets none.
class RenameWindmillUrlToBaseUrl < ActiveRecord::Migration[6.1]
  SETTING_NAME = "plugin_redmine_rubylode_windmill".freeze

  def up
    rename_saved_key("windmill_url", "base_url")
  end

  def down
    rename_saved_key("base_url", "windmill_url")
  end

  private

  # A value already saved under the new key wins over the old one.
  def rename_saved_key(from, to)
    record = Setting.find_by(name: SETTING_NAME)
    return unless record

    values = record.value.to_h.stringify_keys
    return unless values.key?(from)

    old_value = values.delete(from)
    values[to] = old_value if values[to].to_s.empty?
    record.value = values
    record.save!
    Setting.clear_cache
  end
end
