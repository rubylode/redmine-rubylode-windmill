# Changelog

All notable changes to this plugin. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-11-01

First version. Redmine 7.0 and newer.

### Added

- A status block read from Windmill: failed runs of scripts and flows that still need attention (no later run of the same path has succeeded), with path, kind, failure time, a short error and a link to the run; a summary line; and the latest run of watched schedules, flagged when not run since the expected time.
- A wiki macro `{{windmill_status}}`, a page at `/windmill_status`, a My page block and a partial for other plugins and themes, with a compact variant.
- Placements switched in the settings: welcome page, My page default layout, project Overview, pages matching a path list (wildcards, validated on save), and a top menu link. Help with a place / how / needs-a-setting table and copy-paste snippets in the settings page and the README.
- A settings page with validation on save: address, workspace, token variable name, allowed hosts, plain http switch, look-back hours, maximum rows, path prefix, watched schedules, cache and timeout seconds, block title and who may see it.
- The token stays in the environment: only `WINDMILL_*` names are read, it is sent only to the saved Windmill host (and listed hosts), over https unless the host is local or plain http is allowed, and redirects to other hosts are refused.
- Theming through `--rubylode-windmill-*` custom properties, with dark mode.
- A demo with a fake Windmill (`ruby bin/demo up`, port 3015), a browser check and README screenshots.

[Unreleased]: https://github.com/rubylode/redmine-rubylode-windmill/compare/v0.1.0...main
[0.1.0]: https://github.com/rubylode/redmine-rubylode-windmill/releases/tag/v0.1.0
