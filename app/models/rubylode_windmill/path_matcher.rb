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

module RubylodeWindmill
  # Decides whether a request path is one of the pages an administrator listed. One pattern per entry:
  #
  #   /issues               exactly that page (a trailing slash and a query string are ignored)
  #   /projects/*/issues    * stands for anything inside one path segment
  #   /wiki/**              ** stands for anything, slashes included
  #
  # Sign-in, account, Administration and the settings are never matched by a wildcard: a pattern has to begin with
  # that path itself (for example /admin/*) to put the block there.
  class PathMatcher
    PROTECTED_PREFIXES = %w[/settings /admin /login /logout /account].freeze
    MAXIMUM_PATTERNS = 50
    MAXIMUM_LENGTH = 200
    PATTERN_CHARACTERS = %r{\A/[A-Za-z0-9\-._~%/*:@!$&'()+,;=]*\z}

    # Returns an error key (a symbol) or nil.
    def self.problem_with(pattern)
      return :too_long if pattern.length > MAXIMUM_LENGTH
      return :must_start_with_slash unless pattern.start_with?("/")
      return :no_host if pattern.start_with?("//")
      return :bad_characters unless pattern.match?(PATTERN_CHARACTERS)

      nil
    end

    # The patterns in a textarea: one per line, blank lines and lines starting with # skipped.
    def self.patterns_from(text)
      text.to_s.lines.map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
    end

    def initialize(patterns)
      @patterns = patterns.to_a.reject { |pattern| self.class.problem_with(pattern) }
    end

    def match?(request_path)
      path = normalize(request_path)
      @patterns.any? { |pattern| pattern_matches?(normalize(pattern), path) }
    end

    private

    def normalize(path)
      cleaned = path.to_s.split(/[?#]/, 2).first.to_s
      cleaned = cleaned.squeeze("/") unless cleaned.start_with?("//")
      cleaned.length > 1 ? cleaned.chomp("/") : cleaned
    end

    def pattern_matches?(pattern, path)
      return false if protected_path?(path) && !pattern.start_with?(*PROTECTED_PREFIXES)

      expression = pattern.split("**", -1).map { |part| part.split("*", -1).map { |literal| Regexp.escape(literal) }.join("[^/]*") }.join(".*")
      Regexp.new("\\A#{expression}\\z").match?(path)
    end

    def protected_path?(path)
      PROTECTED_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    end
  end
end
