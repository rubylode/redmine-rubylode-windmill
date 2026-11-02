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
  # Puts the status block into Redmine's default My page layout, when the settings ask for it. Only people who have no
  # layout of their own get it; everyone else adds the block themselves from the My page block list.
  module DefaultLayoutPatch
    BLOCK = "rubylode_windmill_status".freeze

    def default_layout
      layout = super
      return layout unless RubylodeWindmill::Configuration.current.show_on_my_page?

      layout.merge("top" => ((layout["top"] || []) + [BLOCK]).uniq)
    end
  end
end
