# Changelog

All notable changes to this plugin. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.0.0] - 2026-11-04

### Changed

- The setting `windmill_url` is now `base_url`, labeled "Windmill address". The migration moves the saved value, and the reverse migration moves it back. Run `bundle exec rake redmine:plugins:migrate RAILS_ENV=production` when upgrading.
- New labels and hints, worded like the other Rubylode plugins: "Token variable" (was "Name of the token environment variable"), "Allowed hosts" (was "Other hosts that may receive the token"), "Allow plain http" (was "Allow plain http (internal network)"), "Show in the top menu" (was "Add a Windmill status link to the top menu").
- The placement settings are under "Show the block on" as Welcome page, My page, Project Overview page and Pages matching these paths. Each column choice has a visible "Column" label. The setting keys are unchanged.
- The token hint no longer says the token goes only to the Windmill address. It also goes to the allowed hosts.
- The page of its own moved from `/windmill_status` to `/status/windmill`. The old address redirects there with a 301 for one release. Update bookmarks and links. The `{{windmill_status}}` macro and the `rubylode_windmill/status` partial are unchanged.
- The top menu caption is the block title (Windmill by default) instead of "Windmill status".
- Plugin code is in `RubylodeWindmill`, and settings are read through `RubylodeWindmill::Settings` (was `RedmineRubylodeWindmill::Defaults` and `RubylodeWindmill::Configuration`). Locale keys moved to `rubylode_windmill.settings.<key>.label` and `.hint`. A theme or plugin that calls these names or keys needs the new ones.
- "Windmill's answer could not be read" replaces "Windmill answered something unreadable".

### Added

- The block shows on the Status page of Rubylode Status when that plugin is installed. The block is down when a run failed or a watched schedule's latest run failed, a warning when a schedule is late, and unknown when Windmill cannot be reached or the plugin is not set up.
- Without Rubylode Status nothing changes. With it, the plugin's own top menu item and its "Show in the top menu" setting go away, and the settings page and the plugin page say so.

### Upgrading

1. Run the plugin migration (above).
2. Change bookmarks and links from `/windmill_status` to `/status/windmill`.
3. Check the top menu caption: it now follows the block title.

## [1.1.1] - 2026-11-04

### Changed

- Needs Redmine 5.1 or newer instead of 5.0. Redmine 5.0 cannot be tested in CI (the sqlite3 gem it pins does not build
  there), and this plugin only claims what CI verifies. No code changed.

## [1.1.0] - 2026-11-04

### Changed

- Runs on Redmine 5.0 and newer. The plugin's own tests pass unchanged on those versions; no code changed.

## [1.0.1] - 2026-11-03

### Added

- A Rubylode thumbnail at the top of the README.

### Changed

- A plainer README and a license section.
- Rewrite the 0.1.0 to 1.0.0 changelog entries.
- Write the checksum file inside the build step of the release job.

## [1.0.0] - 2026-11-02

First stable release.

### Changed

- Show the project address on Administration, Plugins.
- Set the name, author and version to match the listing on redmine.org.

## [0.1.1] - 2026-11-02

### Fixed

- Log a warning instead of failing the page when the cache cannot be read or written (for example a cache file owned by another user). The block is built from a new request to Windmill, or shows "Status unavailable".

## [0.1.0] - 2026-11-01

First version. Redmine 7.0 and newer.

### Added

- A status block read from Windmill: failed runs of scripts and flows that still need attention (no later run of the same path has succeeded), with path, kind, failure time, a short error and a link to the run.
- A summary line above the failed runs.
- The latest run of each watched schedule, flagged when it has not run since its expected time.
- A `{{windmill_status}}` wiki macro, a page at `/windmill_status`, a My page block, and a partial for other plugins and themes, with a compact variant.
- Placements switched in the settings: the welcome page, the My page default layout, the project Overview, pages matching a path list (wildcards, validated on save) and a top menu link.
- Help in the settings page and the README: a place, how and setting table, with copy-paste snippets.
- A settings page that validates on save: address, workspace, token variable name, allowed hosts, plain http switch, look-back hours, maximum rows, path prefix, watched schedules, cache and timeout seconds, block title and who may see it.
- The token stays in the environment. Only `WINDMILL_*` names are read. It goes only to the saved Windmill host (and listed hosts), over https unless the host is local or plain http is allowed. Redirects to other hosts are refused.
- Theming through `--rubylode-windmill-*` custom properties, with dark mode.
- A demo with a fake Windmill (`ruby bin/demo up`, port 3015), a browser check and the README screenshots.

[2.0.0]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v1.1.1...v2.0.0
[1.1.1]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v0.1.1...v1.0.0
[0.1.1]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/rubylode/redmine-rubylode-windmill/releases/tag/v0.1.0
