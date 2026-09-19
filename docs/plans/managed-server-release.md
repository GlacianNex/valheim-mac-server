# Managed server release scope

Development only. Nothing in this plan means a feature has shipped. Keep the general mod catalog on its separate branch. Preserve existing installations and worlds; use isolated servers for validation.

## Existing scope

- Immediate Stopping → Updating → Starting feedback.
- Check Valve server versions every 10 minutes; optional automatic updates.
- Automatically install the tested BepInEx/RCON management package for new servers; explicitly enable management on existing stopped servers.
- Maintain compatible management packages, preserve configuration and credentials, and recover from failed upgrades.
- Warn players in chat and on screen at 15, 10, 5 and 1 minute before an update restart. No 10-second warning. When warnings are unavailable, automatic updates wait for all affected servers to be confirmed empty.
- Performance, moderation and server information. No gameplay/player-history feature.

## Scheduled restarts — issue #4

Source: https://github.com/GlacianNex/valheim-mac-server/issues/4

Added to this release scope at the user's request. Status: implemented locally. Deterministic schedule/workflow tests and AppKit smoke tests pass. See ../VERIFICATION.md for live test results and coverage limits. Not published.

### User-facing behavior

- A **Scheduled restart** setting for each server, disabled by default and independent of other servers.
- Daily, every N days, or selected weekdays, with a local time of day. Use weekday checkboxes; these satisfy the issue's optional checkbox/cron alternatives without requiring users to write cron expressions.
- Show the next scheduled restart, including its date and local time zone.
- Offer player handling: restart with warnings, skip this occurrence if players are online, or postpone until the server is empty. Unknown player counts must not be treated as empty.
- Reuse the 15/10/5/1-minute warning system. Scheduled-restart messages must say why the server is restarting, without claiming a Valheim update is available. When warnings cannot be delivered, leave an occupied server running and show why the restart is waiting.
- Save the world through the existing graceful shutdown path, wait for the old process to exit, then restart only the affected server. Never replace world files or forcibly terminate a server just to meet a schedule.
- Record the scheduled reason, server identity, outcome and current join code in the manager's operational log. This is maintenance logging, not the excluded gameplay-history feature.
- Refresh the existing join-code display after startup using the newly reported value, whether or not it differs from the previous code. Do not show a stale code as current while the server restarts. The issue's file/notification alternative is satisfied by the operational log and current menu display.
- A schedule does not start a server the user has deliberately stopped. Manual cancellation or stop must prevent a delayed scheduled restart from bringing it back.

### Coordination and persistence

- Persist schedules and handled occurrences across manager relaunches. Existing databases without schedules retain current behavior.
- Coordinate with manual start/stop, server updates, management-package updates and other schedules so the same server is never stopped twice or restarted concurrently.
- Keep runtime updates fleet-aware: a scheduled restart of one profile must not silently stop other profiles to update the shared Valve installation.
- Calculate every-N-days schedules by local calendar days, not fixed 24-hour durations. Define and test DST gaps/repeated hours, time-zone changes, sleep/wake and missed occurrences; never burst-replay missed restarts.
- Clearly disclose whether scheduling requires the manager to remain running. Do not imply that a timer in the menu app continues after that app quits.

### Required verification before release

- Deterministic clock tests for daily, every-N-days and weekday schedules, DST, relaunch deduplication and missed occurrences.
- Tests for all player-handling choices, unknown counts, failed warning delivery, cancellation and changes during a countdown.
- Concurrent profile and update tests proving unrelated servers remain running and no duplicate stop/restart occurs.
- Isolated real-server check: warning → graceful save/stop → restart → current join code and maintenance log.
- Final signed/notarized local build for user testing before publication. Do not close issue #4 or post a completion claim until the feature has actually been verified and released.
