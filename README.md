# Camoscope

A macOS CLI that audits a screen-share session for windows a capture/recording
tool would never show, even though they're on screen right now.

## What it does

- **Scans** for windows excluded from screen capture/sharing
  (`kCGWindowSharingState == 0`, read via `CGWindowListCopyWindowInfo` --
  the same WindowServer-level flag every screen-share tool actually
  consults). This is ground truth about the app, not the app's own claim
  about itself, so it works identically for a known tool or a completely
  unknown one.
- For each hidden app, shows an **identity check**: its real on-disk
  executable path (`proc_pidpath`, not the easily-truncated `ps -o comm=`)
  and its code-signing chain (`codesign`). A display name can be trivially
  spoofed (renamed to something like `python3.1`) -- that can't hide the
  window from detection, but it can fool a human glancing at a process
  list. This surfaces what a rename can't cheaply fake.
- Prints an inline **content preview** of the hidden app's live on-screen
  text via a generic recursive Accessibility (AX) tree read -- a second,
  independent pathway from the capture pipeline, unaffected by
  `sharingType`.
- Lets you **quit** a hidden app (graceful app-quit, then `SIGTERM`, then
  `SIGKILL`), or **stream** its content on an interval so you can watch it
  change without ever unhiding the window.

## Intended use / consent

Camoscope is meant to be run **by the person sharing their own screen**, to
audit their **own machine**, before or during their **own** call. It is
**not** a remote-deployment surveillance tool for auditing someone else's
machine without their knowledge or consent. Both the content-read and the
process-kill paths require the terminal/binary running Camoscope to hold
its own Accessibility permission (and process-kill requires being the
process owner or root) -- macOS's own consent prompts are the intended
gate on casual misuse; don't try to route around them.

Ad-hoc or non-Apple code signing is completely normal for legitimate dev
tooling (conda/pyenv/homebrew-installed interpreters, locally-built
binaries). The identity check's `[?]` flags are a "worth a manual look"
signal, not proof of anything -- treat them as a hint, not a verdict.

## Status

Private beta. This repository is private by design while the detection
approach and identity-check heuristics are still being iterated on.

## Install

```
pip install "git+ssh://git@github.com/rajiitmandi21/camoscope.git"
```

Or via Homebrew, once a tagged release exists (not yet functional --
`Formula/camoscope.rb` is currently a placeholder). This repo is deliberately
named `camoscope`, not `homebrew-camoscope`, so it does not qualify for
Homebrew's short-form tap name and needs the explicit URL form:

```
brew tap rajiitmandi21/camoscope https://github.com/rajiitmandi21/camoscope
brew install camoscope
```

## Usage

```
camoscope                 # scan + interactive menu
camoscope --watch          # rescan every 2s, no menu
camoscope --no-prompt      # scan once, print, exit
camoscope --quit PID
camoscope --dump PID
camoscope --stream PID [--interval SECONDS]
```

## License

MIT (see `LICENSE`). Provisional -- pending a final decision before any
distribution wider than private beta.
