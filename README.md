# Camoscope

Camoscope is an opt-in local macOS audit utility. Installing or importing the
package does not scan windows, read Accessibility content, or quit apps. It
does not send scan results to a server. Those actions happen only when you
run the corresponding CLI command.

Camoscope is a macOS command-line tool for inspecting on-screen windows whose
WindowServer `kCGWindowSharingState` is `0`. It lists the owning process,
executable path and available code-signing metadata. With Accessibility
permission, it can also read text exposed by the owning app's Accessibility
(AX) tree.

The sharing-state flag is a useful audit signal. It is **not** a guarantee
about what every screen-sharing, screenshot or recording backend captures.
Test the capture method you rely on before drawing a conclusion. A scan that
finds no matching windows means only that this scan observed none.

## Intended use and permissions

Run Camoscope on your own Mac to inspect your own screen-share session. Do
not deploy it to inspect someone else's machine without their knowledge and
consent.

- Scanning uses macOS WindowServer metadata. macOS may restrict the metadata
  available to a process; check a real capture when the result matters.
- `--dump`, `--stream`, and the default scan's content preview need
  **Accessibility** permission for the terminal or executable running
  Camoscope. AX can expose text from **all windows of the owning app**, not
  just the flagged window. Apps may expose no readable AX text.
- `--quit` uses a PID-bound macOS app termination request, then `SIGTERM` and
  `SIGKILL` if necessary. Signals require permission to act on the process,
  usually ownership. Camoscope checks the process start time before
  escalation to reduce the chance of targeting a reused PID. Quit is
  destructive and is allowed only for a PID present in the current scan;
  verify the PID before using it. It does not require Accessibility
  permission. `--quit` is never run during installation or a scan; it must
  be explicitly selected in the interactive menu or supplied on the command
  line.
- Code-signing output is inspection metadata, **not** a signature validity
  verdict. Unknown, ad-hoc, or unsigned status alone does not establish that
  an app is malicious.

## Install

On macOS with CPython 3.9 through 3.14 (Apple Silicon or Intel):

```sh
python3 -m pip install camoscope==0.1.1
camoscope --version
```

Installation includes PyObjC dependencies for WindowServer, AX and PID-bound
app termination. Public distribution is through compiled **macOS wheels
only**; Linux and other platforms have no compatible wheel. There is no
Homebrew release yet.

For a local checkout:

```sh
python3 -m pip install -e ".[test]"
python3 -m pytest -q
```

## Usage

```sh
camoscope --help
camoscope --no-prompt --no-content  # one scan without AX content
camoscope                           # scan with AX preview, then interactive menu
camoscope --watch --no-content      # rescan every 2 seconds
camoscope --dump PID                 # read the app's exposed AX text once
camoscope --stream PID --interval 3  # repeat until stopped or PID exits
camoscope --quit PID                 # terminate the selected process
```

Use `--no-content` for a metadata-only scan. The default scan tries to read
AX content for matching apps, so it requires Accessibility permission. A
denied permission or failed WindowServer enumeration is an error, not a
negative finding. Camoscope prints results to the terminal and does not save
them automatically.

PIDs must be positive integers. `--interval` must be a positive finite
number. `--quit` returns a nonzero exit status if the process cannot be
terminated. Scan and AX permission failures also return nonzero status.
The CLI never silently treats a failed WindowServer enumeration as an empty
result.

## Release status

Version `0.1.1` is a public beta. Automated tests cover CLI routing and
important safety/error paths. A controlled matrix comparing the flag with
actual capture output across macOS versions and capture backends is still
pending, so this tool should be treated as an audit aid rather than a
conclusive screen-share integrity verdict. The package is built and uploaded
through PyPI Trusted Publishing from a tagged release. The PyPI release
contains compiled extension wheels and no source archive. The Python audit
implementation is not included as readable `.py` files, but compiled code
can still be reverse engineered; no local software can guarantee secrecy
against someone who has the binary.

## License

MIT. The license text is included in the distribution.
