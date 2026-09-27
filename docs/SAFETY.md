# Safety and interpretation

Camoscope is for a person to inspect their own Mac before or during their own
screen-share session. It has no background service, installer hook, or network
client. Installing or importing the package does not inspect windows or act
on processes. Results are printed locally to the terminal and are not saved
or transmitted by Camoscope.

## Commands and effects

| Command | Reads | May change system state |
| --- | --- | --- |
| `--no-prompt --no-content` | On-screen WindowServer window metadata, owning process path and code-signing metadata | No |
| Default scan | The same metadata plus exposed AX text for matching apps | No |
| `--dump PID` / `--stream PID` | Exposed AX text from the owning app's windows | No |
| `--quit PID` | Current flagged-window list and target process identity | Yes: requests app termination, then may send `SIGTERM` and `SIGKILL` |

The interactive menu also requires an explicit `q` selection before quitting
an app. `--quit` rejects nonpositive PIDs and PIDs absent from the current
sharing-state-zero scan. It checks the target app's launch date before signal
escalation to reduce PID reuse risk. A race between the final check and a
signal cannot be completely removed by this Python process. Use `--quit`
only for a process you own and intend to stop.

## Permissions

WindowServer may limit metadata available to a process. AX text access
requires Accessibility permission for the terminal or executable that runs
Camoscope. Process termination requires ordinary macOS ownership or elevated
permission; it does not require Accessibility permission. An AX denial,
WindowServer enumeration failure, or termination failure returns a nonzero
exit status instead of being reported as a clean result.

## What the output means

The scan reports windows whose observed `kCGWindowSharingState` is `0`.
This is a WindowServer metadata value. Different capture paths and macOS
versions may behave differently, and a zero-result scan cannot prove that a
screen share is free of private overlays or other unseen content. AX can
expose all windows of an owning app, not only the flagged window, and may
expose no text for a custom-rendered app. Code-signing metadata is a clue
for manual review, not a signature-validity or maliciousness verdict.

For consequential use, compare Camoscope's report with the actual capture
or recording backend on the same Mac and OS version. Keep the comparison
recorded and avoid making claims beyond what was observed.
