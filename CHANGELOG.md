# Changelog

All notable changes to this plugin. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.1.0] - 2026-11-04

### Changed

- Runs on Redmine 5.0 and newer. The plugin's own tests pass unchanged on those versions; no code changed.

## [1.0.1] - 2026-11-03

### Added

- Show a Rubylode thumbnail at the top of the README.

### Changed

- Make the README plainer and add a licence section.
- Word the changelog entries more plainly.
- Write the checksum file inside the build step of the release job.

## [1.0.0] - 2026-11-02

First stable release.

### Changed

- Show the project address on Administration, Plugins.
- Set the name, author and version to match the listing on redmine.org.

## [0.1.1] - 2026-11-02

### Fixed

- Log a warning instead of failing the page when the cache cannot be read or written (for example a cache file owned by another user). The block is built from a live fetch, or shows "Status unavailable".

## [0.1.0] - 2026-11-01

First version. Redmine 7.0 and newer.

### Added

- A status block read from Windmill: failed runs of scripts and flows that still need attention (no later run of the same path has succeeded), with path, kind, failure time, a short error and a link to the run. It has a summary line and the latest run of each watched schedule, flagged when it has not run since its expected time.
- A `{{windmill_status}}` wiki macro, a page at `/windmill_status`, a My page block, and a partial for other plugins and themes, with a compact variant.
- Placements switched in the settings: the welcome page, the My page default layout, the project Overview, pages matching a path list (wildcards, validated on save) and a top menu link.
- Help in the settings page and the README: a place, how and setting table, with copy-paste snippets.
- A settings page that validates on save: address, workspace, token variable name, allowed hosts, plain http switch, look-back hours, maximum rows, path prefix, watched schedules, cache and timeout seconds, block title and who may see it.
- The token stays in the environment. Only `WINDMILL_*` names are read. It goes only to the saved Windmill host (and listed hosts), over https unless the host is local or plain http is allowed. Redirects to other hosts are refused.
- Theming through `--rubylode-windmill-*` custom properties, with dark mode.
- A demo with a fake Windmill (`ruby bin/demo up`, port 3015), a browser check and the README screenshots.

[Unreleased]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v1.0.0...main
[1.0.0]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v0.1.1...v1.0.0
[0.1.0]: https://github.com/rubylode/redmine-rubylode-windmill/releases/tag/v0.1.0
