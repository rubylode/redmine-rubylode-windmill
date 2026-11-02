# Roadmap

## Goal

Show the state of a Windmill workspace inside Redmine: the failed runs that may need attention and the latest run of chosen schedules, without storing the token and without breaking a page when Windmill is down.

## Decisions

- **Needs attention** is a failed run in the look-back window with no later successful run of the same script or flow path. One row per path. See the README for the exact rule.
- **Read-only, one workspace.** Only GET requests; the workspace is a setting.
- **Token** from an environment variable whose name must start with `WINDMILL_`, bound to the saved host, https required except for localhost or an explicit tick, no redirects to other hosts.
- **Late schedules** come from the schedule's own cron expression (the last moment it should have fired), not from a typed interval. An unreadable expression means "interval unknown", never "late".
- The family of status plugins (this one and the Uptime Kuma one) share setting names for the placements and for the token rules.

## Done (0.1.0)

- Block, macro, page, My page block, partial (with a compact variant), placements, top menu link.
- Settings with validation, host-bound token, fake Windmill, demo, browser check, tests, screenshots.

## Ideas, not decided

- Use Windmill's own "resolved" marker on failed runs (newer Windmill versions) to hide failures someone has handled.
- A per-schedule expected interval in the watched list, for cron expressions the plugin cannot read.
- More than one workspace.
- Queue depth and currently running jobs.
- Translations beyond English.
