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

class RubylodeWindmill::PathMatcherTest < ActiveSupport::TestCase
  def matcher(*patterns)
    RubylodeWindmill::PathMatcher.new(patterns)
  end

  test "an exact path matches only that page" do
    assert matcher("/issues").match?("/issues")
    refute matcher("/issues").match?("/issues/1")
    refute matcher("/issues").match?("/projects")
  end

  test "a query string, a fragment and a trailing slash are ignored on both sides" do
    assert matcher("/issues").match?("/issues?set_filter=1&status_id=o")
    assert matcher("/issues").match?("/issues/")
    assert matcher("/issues/").match?("/issues")
    assert matcher("/issues").match?("/issues#top")
    assert matcher("/").match?("/")
  end

  test "a star stands for one path segment" do
    pattern = matcher("/projects/*/issues")

    assert pattern.match?("/projects/ecookbook/issues")
    refute pattern.match?("/projects/ecookbook/sub/issues")
    refute pattern.match?("/projects/issues")
  end

  test "two stars stand for anything, slashes included" do
    pattern = matcher("/projects/ecookbook/wiki/**")

    assert pattern.match?("/projects/ecookbook/wiki/Page/History")
    assert pattern.match?("/projects/ecookbook/wiki/Page")
  end

  test "any listed pattern may match" do
    assert matcher("/issues", "/news").match?("/news")
  end

  test "sign-in, account, administration and settings are never matched by a wildcard" do
    wildcard = matcher("/**", "/*", "/*/*")

    %w[/settings /settings/plugin/redmine_rubylode_windmill /admin /admin/projects /login /logout /account /account/register].each do |path|
      refute wildcard.match?(path), path
    end
    assert wildcard.match?("/issues")
  end

  test "a protected page is matched when it is listed explicitly" do
    assert matcher("/admin/*").match?("/admin/projects")
    assert matcher("/login").match?("/login")
    refute matcher("/admin/*").match?("/settings")
  end

  test "invalid patterns are dropped, never turned into a match-all" do
    assert_equal :must_start_with_slash, RubylodeWindmill::PathMatcher.problem_with("issues")
    assert_equal :must_start_with_slash, RubylodeWindmill::PathMatcher.problem_with("https://evil.example.com/issues")
    assert_equal :no_host, RubylodeWindmill::PathMatcher.problem_with("//evil.example.com/issues")
    assert_equal :bad_characters, RubylodeWindmill::PathMatcher.problem_with("/issues<script>")
    assert_equal :too_long, RubylodeWindmill::PathMatcher.problem_with("/#{'a' * 300}")
    assert_nil RubylodeWindmill::PathMatcher.problem_with("/projects/*/issues")
    refute matcher("issues", "//evil.example.com").match?("/issues")
  end

  test "patterns come from a textarea, one per line, without blanks or comments" do
    assert_equal ["/issues", "/news"], RubylodeWindmill::PathMatcher.patterns_from("# where\n/issues\n\n  /news  \n")
  end
end
