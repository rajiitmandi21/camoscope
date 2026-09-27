# Camoscope

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
  verify the PID before using it. It does not require
  Accessibility permission.
- Code-signing output is inspection metadata, **not** a signature validity
  verdict. Unknown, ad-hoc, or unsigned status alone does not establish that
  an app is malicious.

## Install

The current distribution is a private Python package. With access to the
private repository and an SSH key authorized for it:

```sh
python3 -m pip install "git+ssh://git@github.com/rajiitmandi21/camoscope.git@v0.1.0"
camoscope --version
```

On macOS, installation includes PyObjC dependencies for WindowServer, AX and
PID-bound app termination. On Linux, package metadata and `--help` work, but
audit commands exit with a macOS-only error. A private Homebrew tap is not yet
available. There is no public PyPI package to install.

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

PIDs must be positive integers. `--interval` must be a positive finite
number. `--quit` returns a nonzero exit status if the process cannot be
terminated. Scan and AX permission failures also return nonzero status.
The CLI never silently treats a failed WindowServer enumeration as an empty
result.

## Release status

Version `0.1.0` is the first private-beta candidate. Automated tests cover
CLI routing and important safety/error paths. A full macOS capture-backend
matrix and private Homebrew distribution are pending. See the repository's
GitHub release for the exact commit and attached Python artifacts when a
release is published.

## License

MIT; see [LICENSE](LICENSE). The release owner should confirm the license
before wider distribution.
