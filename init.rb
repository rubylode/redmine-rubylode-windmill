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

require "redmine"
require_relative "lib/rubylode_windmill/settings"

Redmine::Plugin.register :redmine_rubylode_windmill do
  name "Rubylode Windmill"
  author "Rubylode"
  author_url "https://github.com/rubylode"
  url "https://github.com/rubylode/redmine-rubylode-windmill"
  description "Shows failed Windmill runs that need attention and the latest run of chosen schedules, as a wiki macro, a page, a My page block and a partial"
  version "2.0.0"
  requires_redmine version_or_higher: "5.1.0"

  # The caption is the block title. With the Status plugin installed the block is on its page and this item goes.
  menu :top_menu, :rubylode_windmill_status, { controller: "rubylode_windmill_status", action: "show" },
       caption: proc { RubylodeWindmill::Settings.current.block_title },
       if: proc {
         settings = RubylodeWindmill::Settings.current
         !RubylodeWindmill::Settings.status_plugin_installed? && settings.show_in_top_menu? && settings.configured? && settings.visible_to?(User.current)
       }

  settings default: RubylodeWindmill::Settings::DEFAULTS, partial: "settings/rubylode_windmill"
end

require_relative "lib/rubylode_windmill/macros"
RubylodeWindmill::Macros.register
require_relative "lib/rubylode_windmill/default_layout_patch"
Redmine::MyPage.singleton_class.prepend RubylodeWindmill::DefaultLayoutPatch unless Redmine::MyPage.singleton_class.include?(RubylodeWindmill::DefaultLayoutPatch)
require_relative "lib/rubylode_windmill/hooks"
require_relative "lib/rubylode_windmill/settings_controller_patch"

# Plugins load after the boot-time prepare callbacks have run, so apply the patch now and again after each code reload.
apply_settings_controller_patch = lambda do
  unless SettingsController.include?(RubylodeWindmill::SettingsControllerPatch)
    SettingsController.prepend RubylodeWindmill::SettingsControllerPatch
  end
end
apply_settings_controller_patch.call
Rails.configuration.to_prepare(&apply_settings_controller_patch)

# Puts the block on the Status page when Rubylode Status is installed. See its docs/widget-contract.md.
Rails.application.config.after_initialize do
  RubylodeWindmill::StatusWidget.register_with_status_plugin
end
