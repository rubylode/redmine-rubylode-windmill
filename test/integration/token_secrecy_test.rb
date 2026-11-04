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

# The token is never stored, rendered, logged or put in an error message, and goes only to the Windmill host.
class RubylodeWindmill::TokenSecrecyTest < Redmine::IntegrationTest
  include RubylodeWindmillTestHelpers

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :issue_statuses, :trackers, :projects_trackers, :enumerations, :enabled_modules

  setup do
    use_memory_cache
    start_fake_windmill
    @log_path = Rails.root.join("log", "#{Rails.env}.log")
    @log_offset = File.exist?(@log_path) ? File.size(@log_path) : 0
  end

  teardown do
    stop_fake_windmill
    @other_server&.stop
    ENV.delete("SECRET_KEY_BASE")
    restore_cache
  end

  def log_written_during_test
    Rails.logger.flush if Rails.logger.respond_to?(:flush)
    return "" unless File.exist?(@log_path)

    File.open(@log_path) { |file| file.seek(@log_offset); file.read.to_s }
  end

  test "with the right token the page works and the token is nowhere in the html or the log" do
    log_user("admin", "admin")
    get "/status/windmill"

    assert_select ".rubylode-windmill-status-summary", text: /failing/
    refute_includes response.body, @fake_token
    refute_includes log_written_during_test, @fake_token
    assert_equal ["Bearer #{@fake_token}"], @fake_windmill.authorizations.uniq
  end

  test "with a wrong token the page says unavailable and neither the html, the log nor the reason shows either token" do
    ENV[TOKEN_VARIABLE] = "wrong-token-also-secret-55"
    log_user("admin", "admin")
    get "/status/windmill"

    assert_select ".rubylode-windmill-status-summary", text: "Status unavailable"
    assert_select ".rubylode-windmill-status-hint", text: /401/
    [@fake_token, "wrong-token-also-secret-55"].each do |token|
      refute_includes response.body, token
      refute_includes log_written_during_test, token
    end
  end

  test "the settings page and the saved settings never hold the token" do
    log_user("admin", "admin")
    get "/settings/plugin/redmine_rubylode_windmill"
    refute_includes response.body, @fake_token
    assert_select "strong", text: "set in the environment"

    post "/settings/plugin/redmine_rubylode_windmill", params: { settings: Setting.send(:"plugin_#{PLUGIN_ID}") }
    refute_includes Setting.send(:"plugin_#{PLUGIN_ID}").to_s, @fake_token
    assert_empty Setting.where("value LIKE ?", "%#{@fake_token}%").to_a.map(&:name)
  end

  test "settings that name SECRET_KEY_BASE at runtime read nothing and send nothing" do
    ENV["SECRET_KEY_BASE"] = "rails-secret-key-base-value"
    configure_plugin("base_url" => @fake_windmill.base_url, "token_environment_variable" => "SECRET_KEY_BASE")
    log_user("admin", "admin")
    get "/status/windmill"

    assert_select ".rubylode-windmill-status-summary", text: "Status unavailable"
    assert_equal 0, @fake_windmill.request_count
    refute_includes response.body, "rails-secret-key-base-value"
  end

  test "a redirect to another host never receives the token" do
    @other_server = FakeWindmillServer.new(token: @fake_token).start
    # The first server answers 302 to the second one; the second is not a listed host.
    configure_plugin("base_url" => "#{@fake_windmill.base_url}/__redirect/#{@other_server.port}")
    log_user("admin", "admin")
    get "/status/windmill"

    assert_select ".rubylode-windmill-status-summary", text: "Status unavailable"
    assert_equal 0, @other_server.request_count, "the other host was never contacted"
    assert_empty @other_server.authorizations
  end
end
