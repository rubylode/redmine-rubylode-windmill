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
require_relative "lib/redmine_rubylode_windmill/defaults"

Redmine::Plugin.register :redmine_rubylode_windmill do
  name "Rubylode Windmill"
  author "Rubylode"
  author_url "https://github.com/rubylode"
  url "https://github.com/rubylode/redmine-rubylode-windmill"
  description "The state of a Windmill workspace in Redmine: failed runs that need attention and the latest run of chosen schedules, as a wiki macro, a page, a My page block and a partial"
  version "1.1.1"
  requires_redmine version_or_higher: "5.1.0"

  menu :top_menu, :rubylode_windmill_status, { controller: "rubylode_windmill_status", action: "show" },
       caption: :"rubylode_windmill.page_title",
       if: proc {
         configuration = RubylodeWindmill::Configuration.current
         configuration.show_in_top_menu? && configuration.configured? && configuration.visible_to?(User.current)
       }

  settings default: RedmineRubylodeWindmill::Defaults::SETTINGS, partial: "settings/rubylode_windmill"
end

require_relative "lib/redmine_rubylode_windmill/macros"
RedmineRubylodeWindmill::Macros.register
require_relative "lib/redmine_rubylode_windmill/default_layout_patch"
Redmine::MyPage.singleton_class.prepend RedmineRubylodeWindmill::DefaultLayoutPatch unless Redmine::MyPage.singleton_class.include?(RedmineRubylodeWindmill::DefaultLayoutPatch)
require_relative "lib/redmine_rubylode_windmill/hooks"
require_relative "lib/redmine_rubylode_windmill/settings_controller_patch"

# Plugins load after the boot-time prepare callbacks have run, so apply the patch now and again after each code reload.
apply_settings_controller_patch = lambda do
  unless SettingsController.include?(RedmineRubylodeWindmill::SettingsControllerPatch)
    SettingsController.prepend RedmineRubylodeWindmill::SettingsControllerPatch
  end
end
apply_settings_controller_patch.call
Rails.configuration.to_prepare(&apply_settings_controller_patch)
