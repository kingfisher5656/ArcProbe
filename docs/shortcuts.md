# Automatic tracking with Shortcuts

ArcProbe cannot see when Arcaea is running. Two personal automations in the Shortcuts app tell it, and a small loop asks ArcProbe to check for a new play about once a minute while Arcaea is open.

Set up the tracker account first (ArcProbe → gear button → Tracker account).

## 1. The shortcut

Create a shortcut named **ArcProbe tracking** with these actions:

| # | Action | Setting |
|---|---|---|
| 1 | **Start Arcaea Tracking** | — |
| 2 | **Repeat** | 1000 times |
| 3 | &nbsp;&nbsp;**Check Recent Play** | Session = result of *Start Arcaea Tracking* |
| 4 | &nbsp;&nbsp;**If** *Check Recent Play* **is less than** 1 → **Stop This Shortcut** → **End If** | |
| 5 | &nbsp;&nbsp;**Wait** | duration = result of *Check Recent Play* |
| 6 | **End Repeat** | |

That is the whole shortcut. There is nothing to tune: no random number, no dictionary parsing, no status list.

## 2. The automations

| When | Do |
|---|---|
| Arcaea **is opened** | Run the shortcut **ArcProbe tracking** |
| Arcaea **is closed** | **Stop Arcaea Tracking** |

Set both to **Run Immediately** and turn **Notify When Run** off.

## How it behaves

- **ArcProbe owns the timing.** *Check Recent Play* fetches when a check is due (every 65–80 seconds) and returns how many seconds to wait. If it is called early it fetches nothing and returns the remaining time.
- **Reopening quickly is safe.** Every open starts a new loop that takes over. Older loops get `0` from their next check and stop. The schedule is shared, so closing and reopening Arcaea five times in a row does not postpone the next fetch, and a fetch that was already on its way is still saved.
- **Closing.** After *Stop Arcaea Tracking* the running loop makes two more checks, about a minute apart, to catch a play that was uploaded just before closing. Then *Check Recent Play* returns `0` and the shortcut ends.
- **Problems you must fix stop the shortcut with a message**: the tracker account has to sign in again, or no tracker account is set up. ArcProbe → Settings shows the same warning.
- **Temporary problems do not stop it**: no connection, a server error page, or a rate limit only make the loop wait longer. Only three failures in a row that look like a login problem stop it.

Settings → Automatic tracking shows the current state: *Tracking plays*, *Waiting for Arcaea to open*, *Arcaea closed · final checks*, or *Arcaea is open, but the Shortcut stopped checking* when iPadOS has killed the loop.

## Limits

- iPadOS may suspend or end a long-running automation. Reopening Arcaea starts a fresh loop.
- Arcaea Online only exposes the single newest play. If two songs finish between two checks, the first one is missed. Songs are longer than the check interval, so this needs a stalled loop to happen.
- On system versions where the *is closed* automation also fires for things like Control Center, the loop ends after its closing checks even though Arcaea is still open. Reopening Arcaea restarts it.

## Other actions

- **Fetch Recent Play Once** — one request, returns a one-line summary. For a home-screen button; not used in the loop.
- **Start Notification Tracking** / **Process Tracking Notification** — an experimental alternative for systems that end automations after a few minutes: instead of waiting inside one shortcut, each check schedules a silent notification and a Notification automation runs the next check. Setup steps are in ArcProbe → Settings → Shortcut setup → Notification method. Not verified on a real device.

## Coming from 0.2.x

The old actions (*Set Tracking Active*, *Get Tracking Status*, *Fetch Recent Play* with a generation) are gone. Delete the old "poll recent score" shortcut and build the one above; change the *is closed* automation to **Stop Arcaea Tracking**.
