# Roadmap

## Goal

Show the state of a Windmill workspace inside Redmine: the failed runs that may need attention and the latest run of chosen schedules. The token is never stored, and a page does not break when Windmill is down.

## Decisions

- A run needs attention when it failed in the look-back window and no later run of the same script or flow path has succeeded. One row per path. The README has the exact rule.
- Read-only, one workspace: only GET requests, and the workspace is a setting.
- The token comes from an environment variable whose name must start with `WINDMILL_`. It is bound to the saved host, needs https except for localhost or an explicit setting, and is never sent along a redirect to another host.
- A late schedule is judged from the schedule's own cron expression (the last moment it should have fired), not from a typed interval. An unreadable expression means "interval unknown", never "late".

## Done

- The block, the macro, the page at `/status/windmill`, the My page block, the partial (with a compact variant), the placements and the top menu link.
- Settings with validation, the host-bound token, a fake Windmill, a demo, a browser check, tests and screenshots.
- The standard setting names and labels shared by the Rubylode plugins, and a migration from the 1.x settings (2.0.0).
- The block on the Rubylode Status page, when that plugin is installed (2.0.0).

## Ideas, not decided

- Use Windmill's own "resolved" marker on failed runs (newer Windmill versions) to hide failures someone has handled.
- A per-schedule expected interval in the watched list, for cron expressions the plugin cannot read.
- More than one workspace.
- Queue depth and currently running jobs.
- Translations beyond English.
