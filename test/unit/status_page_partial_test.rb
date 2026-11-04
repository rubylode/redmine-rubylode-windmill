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

# On the Status page the page draws the title and the summary, so the partial must not repeat them.
class RubylodeWindmill::StatusPagePartialTest < ActiveSupport::TestCase
  include RubylodeWindmillTestHelpers

  fixtures :users, :email_addresses

  def render_partial(locals = {})
    configure_plugin
    report = RubylodeWindmill::WindmillStatus::Report.new([], [], 0, [], "Nothing needs attention", :ok, false, nil)
    User.current = User.find(1)
    replacing_method(RubylodeWindmill::WindmillStatus, :safe_report, ->(*) { report }) do
      ApplicationController.render(partial: "rubylode_windmill/status", locals: locals)
    end
  ensure
    User.current = nil
  end

  test "outside the Status page the partial draws its title and summary" do
    html = render_partial

    assert_includes html, "rubylode-windmill-status-title"
    assert_includes html, "Nothing needs attention"
  end

  test "on the Status page, where a widget local is passed, the title and summary are left to the page" do
    html = render_partial(widget: Object.new)

    refute_includes html, "rubylode-windmill-status-title"
    refute_includes html, "rubylode-windmill-status-summary"
  end
end
