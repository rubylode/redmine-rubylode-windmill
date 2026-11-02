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

module RedmineRubylodeWindmill
  # Redmine saves plugin settings without asking the plugin. This checks ours first: when something is wrong the form is
  # shown again with what the person typed and a list of the problems, and nothing is saved.
  module SettingsControllerPatch
    def plugin
      return super unless request.post? && params[:id].to_s == PLUGIN_ID.to_s

      submitted = params[:settings] ? params[:settings].permit!.to_h : {}
      errors = RubylodeWindmill::SettingsValidator.errors_for(submitted)
      return super if errors.empty?

      @plugin = Redmine::Plugin.find(params[:id])
      @partial = @plugin.settings[:partial]
      @settings = submitted
      @validation_errors = errors
      render "settings/plugin", status: :unprocessable_entity
    end
  end
end
