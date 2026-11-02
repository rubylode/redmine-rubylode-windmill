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

# Demo data for the throwaway Redmine in docker-compose.yml: one project with a wiki page that uses the macro, a second
# person, the plugin set up against the fake Windmill next door, and the block on the administrator's My page.
# Everything is made up.
#
#   ruby bin/demo seed      (or: docker compose exec redmine bin/rails runner plugins/redmine_rubylode_windmill/test/seed.rb)
#
# Safe to run twice: it does nothing when the demo project is already there.

DEMO_PASSWORD = "demo-password-1".freeze
PROJECT_IDENTIFIER = "demo-operations".freeze

Redmine::DefaultData::Loader.load("en") if Tracker.none?

if Project.exists?(identifier: PROJECT_IDENTIFIER)
  puts "demo data already loaded"
  return
end

ActiveRecord::Base.transaction do
  Setting.default_language = "en"
  Setting.notified_events = [] # no mail from the demo
  Setting.welcome_text = "A throwaway Redmine with made-up data, for trying the Rubylode Windmill plugin."

  admin = User.find_by!(login: "admin")
  admin.update_columns(must_change_passwd: false)
  User.current = admin

  dana = User.new(login: "dana", firstname: "Dana", lastname: "Scully", mail: "dana@example.com", language: "en")
  dana.password = dana.password_confirmation = DEMO_PASSWORD
  dana.must_change_passwd = false
  dana.save!

  project = Project.create!(name: "Operations", identifier: PROJECT_IDENTIFIER, is_public: true,
                            description: "Where the automation is watched.")
  project.enabled_module_names = %w[issue_tracking wiki]
  project.trackers = Tracker.all
  Member.create!(project: project, principal: dana, roles: [Role.find_by!(name: "Developer")])

  wiki = project.wiki || Wiki.create!(project: project, start_page: "Wiki")
  page = WikiPage.new(wiki: wiki, title: "Automation")
  page.content = WikiContent.new(author: admin, text: <<~TEXTILE)
    h1. Automation

    The state of the workflow engine, straight from Windmill:

    {{windmill_status}}
  TEXTILE
  page.save!

  Setting.send(:plugin_redmine_rubylode_windmill=, RedmineRubylodeWindmill::Defaults::SETTINGS.merge(
    "windmill_url" => "http://fake_windmill:9100",
    "allow_plain_http" => "1", # the fake Windmill is plain http on the demo network
    "workspace_id" => "demo",
    "show_in_top_menu" => "1",
    "show_on_welcome_page" => "1", "welcome_page_column" => "left",
    "cache_seconds" => "5", "failure_cache_seconds" => "5",
    "watched_schedules" => <<~TEXT
      Nightly sync | f/billing/nightly_sync | Copies the day's invoices at 02:00
      Hourly metrics | f/reports/hourly_metrics | Refreshes the dashboard every hour
      Heartbeat | f/ops/heartbeat | Pings the office every five minutes
      Weekly digest | f/crm/weekly_digest | Mails the Tuesday summary (paused)
    TEXT
  ))

  preference = admin.pref
  preference.my_page_layout = { "top" => ["rubylode_windmill_status"], "left" => ["issuesassignedtome"], "right" => [] }
  preference.save!
end

puts "demo data loaded"
