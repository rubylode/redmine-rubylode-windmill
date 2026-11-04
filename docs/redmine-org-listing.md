# Listing on www.redmine.org

The text to paste at www.redmine.org, Plugins, New plugin. Redmine's "Check for updates" asks that directory about every installed plugin, so the listing must carry the same name, author and version as the plugin.

| Field | Value |
|---|---|
| Name | Rubylode Windmill |
| Short description | The state of a Windmill workspace in Redmine: failed runs that need attention and the latest run of chosen schedules, as a wiki macro, a page, a My page block and a partial |
| Homepage | https://github.com/rubylode/redmine-rubylode-windmill |
| Compatible with | Redmine 5.0.x, 5.1.x, 6.0.x, 6.1.x, 7.0.x |
| License | GNU General Public License, version 2 or (at your option) any later version |
| Author | Rubylode |

## Notes for the first version

Version 1.1.0. The state of a Windmill workspace in Redmine: failed runs that need attention and the latest run of chosen schedules, as a wiki macro, a page, a My page block and a partial. Needs Redmine 5.0 or newer. Install and settings are described in the README at https://github.com/rubylode/redmine-rubylode-windmill.

## File to upload

`redmine_rubylode_windmill-1.1.0.zip`, the file the GitHub release workflow publishes when a `v1.1.0` tag is pushed. Upload the same file that is attached to the GitHub release.

## Checking the result

The name, author and version in the listing must match what the plugin registers (`Rubylode Windmill`, `Rubylode`, `1.1.0`). When they do, Administration, Plugins, Check for updates shows:

- a green tick: the installed version is the latest one listed on redmine.org;
- an amber warning: redmine.org lists a newer version than the installed one;
- a grey question mark: the plugin is not found, so the name or the listing needs a look.

The answer comes only from the redmine.org directory. Nothing in the plugin can change it, and it stays grey until the listing exists.
