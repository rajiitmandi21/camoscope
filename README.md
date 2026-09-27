# Camoscope

[Project page and documentation](https://pypi.org/project/camoscope/) ·
[Get help](https://www.rajsharma.space/#contact) ·
[Support this and other apps](https://github.com/sponsors/rajiitmandi21)

Camoscope helps interviewers and proctors investigate app windows a participant
may be concealing from a screen share, including during online interviews.
Run with the participant's knowledge and consent on their Mac, it identifies
windows marked as excluded from capture, shows the owning app and available
app details, and can show text exposed to Accessibility tools.

It flags on-screen windows for which macOS reports WindowServer
`kCGWindowSharingState` as `0`. That flag is a clue to investigate, not a
measurement of what a particular screen-sharing or recording app captures.

Installing or importing Camoscope does not scan windows, read app text, or
quit apps. It does not send scan results to a server. Those actions happen
only when you run the corresponding command.

A result is a reason to investigate; it does **not** prove what the interviewer's
screen-share view contains or establish misconduct. A scan with no results does
not prove that every window or browser tab is visible. Compare findings with
the actual share or recording before drawing a conclusion.

## Intended use and permissions

Run Camoscope locally on the participant's Mac with their knowledge and
consent. It cannot remotely inspect a participant's computer from the
interviewer's Mac.

- A scan checks window information supplied by macOS. Permissions and the
  current desktop session can affect what is available.
- `--dump`, `--stream`, and the default scan's content preview need
  **Accessibility** permission for the terminal or executable running
  Camoscope. The text may come from **other windows of the same app**, not
  just the window reported by the scan. Some apps expose no readable text.
- `--quit` first asks the selected app to close, then may force it to stop.
  This can discard unsaved work. It is allowed only for an app found in the
  current scan and requires permission to control that app. Check the PID
  before using it. It does not need Accessibility permission and never runs
  during installation or an ordinary scan.
- Code-signing output is inspection metadata, **not** a signature validity
  verdict. Unknown, ad-hoc, or unsigned status alone does not establish that
  an app is malicious.

## Install

On macOS with CPython 3.9 through 3.14 (Apple Silicon or Intel):

```sh
python3 -m pip install camoscope==0.1.2
camoscope --version
```

Public distribution is through compiled **macOS wheels only**. Linux and
other platforms have no compatible wheel. There is no Homebrew release yet.

## First check

Run a scan without reading app text:

```sh
camoscope --no-prompt --no-content
```

The command prints a summary and exits. If it reports a window, compare it
with what the interviewer can see in the actual share or recording. If it
reports no windows, that is only the result of this scan. It does not detect
every concealed browser tab or guarantee that every app window is visible.

## Usage

```sh
camoscope --help
camoscope --no-prompt --no-content  # one scan without app text
camoscope                           # scan with text preview, then interactive menu
camoscope --watch --no-content      # rescan every 2 seconds
camoscope --dump PID                 # show text exposed by the app once
camoscope --stream PID --interval 3  # repeat until stopped or PID exits
camoscope --quit PID                 # terminate the selected process
```

Use `--no-content` to scan without reading app text. The default scan tries
to show available text for matching apps, so it needs Accessibility
permission. A denied permission or failed window scan is an error, not a
negative finding. Camoscope prints results to the terminal and does not save
them automatically.

PIDs must be positive integers. `--interval` must be a positive finite
number. `--quit` returns a nonzero exit status if the process cannot be
terminated. Scan and Accessibility failures also return nonzero status.
The CLI never treats a failed window scan as an empty result.

## Permissions and troubleshooting

- **Accessibility denied:** `--dump`, `--stream`, and the default scan's text
  preview need permission for the terminal or app running Camoscope. Open
  **System Settings → Privacy & Security → Accessibility** and allow that
  app. You can still scan without text using `--no-content`. See
  [Apple's Accessibility permission guide](https://support.apple.com/guide/mac-help/mh43185/mac).
- **Scan failed or seems incomplete:** run Camoscope from a signed-in desktop
  session. Check **System Settings → Privacy & Security → Screen & System
  Audio Recording** if macOS asks for access. Window information can be
  limited even when the command returns successfully. Compare against a real
  share or recording. See [Apple's screen-recording permission guide](https://support.apple.com/guide/mac-help/mchld6aa7d23/mac).
- **`camoscope` command not found:** use `python3 -m camoscope` with the same
  Python you used for installation, or activate its virtual environment.
- **Quit refused:** Camoscope only quits a process found in the current scan
  when macOS identifies it as a running app. It will refuse an unknown or
  changed process rather than send it a signal.

If you need help, use the [shared developer contact page](https://www.rajsharma.space/#contact).

## Release status

Version `0.1.2` is a public beta. Automated tests cover command behavior and
important safety cases. A broader comparison with actual screen-sharing
and recording apps across macOS versions is still pending. Treat Camoscope
as an investigation aid, not a conclusive visibility or misconduct verdict.
The PyPI release contains compiled macOS wheels and no source archive.
Compiled code can still be reverse engineered.

## License

MIT. The license text is included in the distribution.

## Support the apps

If Camoscope or another app I build is useful to you, you can
[sponsor their continued development](https://github.com/sponsors/rajiitmandi21).
For questions, bug reports, or collaboration, use the
[developer contact page](https://www.rajsharma.space/#contact).
