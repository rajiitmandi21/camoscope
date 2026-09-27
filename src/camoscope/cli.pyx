"""Inspect macOS windows whose WindowServer sharing state is zero.

This is a metadata observation, not proof that every capture backend omits
the window. AX reads inspect the owning app's exposed windows, which may
include windows other than those found by the WindowServer scan.
"""
import argparse
import ctypes
import math
import os
import signal
import subprocess
import sys
import time

if sys.platform == "darwin":
    try:
        import ApplicationServices as AX
        import Quartz
        from AppKit import NSRunningApplication
    except ImportError:  # pragma: no cover - exercised by a missing macOS install
        AX = None
        Quartz = None
        NSRunningApplication = None
else:
    AX = None
    Quartz = None
    NSRunningApplication = None

_libproc = None


def _require_macos_runtime():
    """Raise a user-facing error when the macOS-only runtime is unavailable."""
    if sys.platform != "darwin":
        raise RuntimeError(
            "Camoscope's WindowServer and Accessibility audit requires macOS; "
            "the package can be installed on Linux, but this command is macOS-only."
        )
    if AX is None or Quartz is None or NSRunningApplication is None:
        raise RuntimeError(
            "Camoscope's macOS dependencies are missing. Reinstall from the private release or repository."
        )


def _text_attrs():
    _require_macos_runtime()
    return [AX.kAXValueAttribute, AX.kAXTitleAttribute, AX.kAXDescriptionAttribute]


def _libproc_library():
    global _libproc
    if _libproc is None:
        _require_macos_runtime()
        _libproc = ctypes.CDLL("/usr/lib/libproc.dylib")
    return _libproc


# ---------------------------------------------------------------------------
# Detection (WindowServer / CGWindowList -- the actual capture pipeline)
# ---------------------------------------------------------------------------

def scan_hidden_windows():
    """Return on-screen windows whose WindowServer sharing state is zero."""
    _require_macos_runtime()
    options = Quartz.kCGWindowListOptionOnScreenOnly
    window_list = Quartz.CGWindowListCopyWindowInfo(options, Quartz.kCGNullWindowID)
    if window_list is None:
        raise RuntimeError("WindowServer window enumeration failed; scan result is unknown")

    hidden = []
    for w in window_list:
        sharing_state = w.get("kCGWindowSharingState", 1)
        if sharing_state != 0:
            continue
        bounds = w.get("kCGWindowBounds", {})
        pid = w.get("kCGWindowOwnerPID")
        hidden.append(
            {
                "pid": pid,
                "owner": w.get("kCGWindowOwnerName", "?"),
                "name": w.get("kCGWindowName", "") or "(untitled)",
                "layer": w.get("kCGWindowLayer"),
                "w": int(bounds.get("Width", 0)),
                "h": int(bounds.get("Height", 0)),
                "identity": get_process_identity(pid) if pid else {},
            }
        )
    return hidden


# ---------------------------------------------------------------------------
# Identity check -- the process's *displayed* name is trivially spoofable
# (rename the binary / set CFBundleName to anything, e.g. "python3.1"), so
# the WindowServer scan above never trusted it for anything except display.
# This looks at what a rename can't cheaply fake: the real executable path
# and its code-signing chain.
# ---------------------------------------------------------------------------

def _real_executable_path(pid):
    """proc_pidpath(3) -- the actual on-disk executable, unlike `ps -o comm=`
    which macOS often truncates to a bare basename (e.g. "python3" instead
    of "/opt/miniconda3/bin/python3.10"), which would make every path-based
    check below silently useless.
    """
    libproc = _libproc_library()
    buf = ctypes.create_string_buffer(4096)
    ret = libproc.proc_pidpath(pid, buf, 4096)
    if ret <= 0:
        return None
    return buf.value.decode("utf-8", "replace")


def get_process_identity(pid):
    _require_macos_runtime()
    info = {"path": None, "signed": None, "adhoc": False, "team_id": None, "authority": None}
    path = _real_executable_path(pid)
    info["path"] = path or None
    if not path:
        return info

    try:
        result = subprocess.run(
            ["codesign", "-dv", "--verbose=2", path], capture_output=True, text=True, timeout=5
        )
        out = result.stderr or ""
    except Exception:
        return info

    if "not signed at all" in out or "code object is not signed" in out:
        info["signed"] = False
        return info

    if result.returncode != 0:
        return info
    if not any(line.startswith(("Signature=", "Authority=")) for line in out.splitlines()):
        return info
    info["signed"] = True
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("TeamIdentifier="):
            info["team_id"] = line.split("=", 1)[1]
        elif line.startswith("Authority=") and info["authority"] is None:
            info["authority"] = line.split("=", 1)[1]
        elif line == "Signature=adhoc":
            info["adhoc"] = True
    return info


def _identity_flag(h):
    """A short warning tag when the display name doesn't match what's actually running."""
    ident = h.get("identity") or {}
    path = ident.get("path") or ""
    looks_like_system_tool = h["owner"].split(".")[0].lower() in {
        "python3", "python", "bash", "zsh", "finder", "windowserver", "loginwindow", "dock",
    }
    if not looks_like_system_tool:
        return ""
    # NOTE: ad-hoc / non-Apple signing is also completely normal for
    # legitimate dev tooling (conda/pyenv/homebrew-installed interpreters,
    # locally-built binaries). This is a "worth a manual look" signal, not
    # proof of anything -- don't let an operator treat it as a verdict.
    if ident.get("signed") is False:
        return "  [?] unsigned binary claiming a system-tool-like name -- worth a manual look"
    if ident.get("adhoc"):
        return "  [?] ad-hoc signed (not Apple) -- common for dev tools too, but worth a manual look"
    authority = ident.get("authority") or ""
    if ident.get("signed") is None:
        return "  [?] signature inspection unavailable -- worth a manual look"
    if "Apple" not in authority and "Software Signing" not in authority:
        return f"  [?] signed by '{authority or 'unknown'}', not Apple -- worth a manual look"
    if not path.startswith(("/usr/", "/System/", "/bin/", "/sbin/")):
        return f"  [?] running from {path}, not a standard system location"
    return ""


def _dedupe_by_app(hidden):
    """Collapse multiple hidden windows owned by the same pid into one entry
    (e.g. a HUD + a separate recording-bar panel from the same app), since
    they're one app to quit/inspect either way."""
    by_pid = {}
    order = []
    for h in hidden:
        pid = h["pid"]
        if pid not in by_pid:
            by_pid[pid] = {**h, "windows": [h["name"]], "count": 1}
            order.append(pid)
        else:
            entry = by_pid[pid]
            entry["windows"].append(h["name"])
            entry["count"] += 1
            entry["w"], entry["h"] = h["w"], h["h"]
    return [by_pid[pid] for pid in order]


def print_report(apps, total_windows=None, show_content=True, content_lines=15):
    ts = time.strftime("%H:%M:%S")
    if total_windows is None:
        total_windows = sum(a["count"] for a in apps)
    print(f"\n[{ts}] scan complete -- {len(apps)} app(s), {total_windows} window(s) with WindowServer sharing state 0")
    if not apps:
        return
    print(f"  {'#':<3} {'PID':<8} {'OWNER':<28} {'SIZE':<10} WINDOW(S)")
    print(f"  {'-'*3} {'-'*8} {'-'*28} {'-'*10} {'-'*20}")
    for i, h in enumerate(apps):
        size = f"{h['w']}x{h['h']}"
        windows = ", ".join(dict.fromkeys(h["windows"]))
        if h["count"] > 1:
            windows += f"  ({h['count']} windows)"
        print(f"  {i:<3} {h['pid']:<8} {h['owner']:<28} {size:<10} {windows}{_identity_flag(h)}")
        ident = h.get("identity") or {}
        if ident.get("path"):
            sig = "inspection unavailable" if ident.get("signed") is None else ("unsigned" if ident.get("signed") is False else (
                "adhoc" if ident.get("adhoc") else (ident.get("authority") or "signed, authority unknown")
            ))
            print(f"      path: {ident['path']}")
            print(f"      signature: {sig}" + (f"  team: {ident['team_id']}" if ident.get("team_id") else ""))
        if show_content and h["pid"]:
            lines = dump_ax_content(h["pid"])
            print("      content:")
            for line in lines[:content_lines]:
                print(f"        {line}")
            if len(lines) > content_lines:
                print(f"        ... ({len(lines) - content_lines} more lines, run --dump {h['pid']} for full)")


# ---------------------------------------------------------------------------
# Content read (Accessibility tree -- independent of sharingType/capture)
# ---------------------------------------------------------------------------

def _ax_get(elem, attr):
    _require_macos_runtime()
    err, val = AX.AXUIElementCopyAttributeValue(elem, attr, None)
    return val if err == 0 else None


def _walk(elem, depth, max_depth, max_nodes, counter, lines, seen):
    if counter[0] >= max_nodes or depth > max_depth:
        return
    counter[0] += 1
    key = id(elem)
    if key in seen:
        return
    seen.add(key)

    role = _ax_get(elem, AX.kAXRoleAttribute) or ""
    texts = []
    for attr in _text_attrs():
        v = _ax_get(elem, attr)
        if isinstance(v, str) and v.strip():
            texts.append(v.strip())
    if texts:
        unique = list(dict.fromkeys(texts))
        lines.append(f"{'  ' * depth}[{role}] " + " | ".join(unique))

    for c in _ax_get(elem, AX.kAXChildrenAttribute) or []:
        _walk(c, depth + 1, max_depth, max_nodes, counter, lines, seen)


def dump_ax_content(pid, max_depth=25, max_nodes=1500):
    """Generic recursive read of everything with text in an app's AX tree.

    Works for any app, known or not -- it makes no assumption about window
    names or UI structure, it just walks whatever hierarchy exists.
    """
    _require_macos_runtime()
    if not AX.AXIsProcessTrusted():
        raise RuntimeError("Accessibility access is denied; grant this terminal access in System Settings -> Privacy & Security -> Accessibility")

    app = AX.AXUIElementCreateApplication(pid)
    windows = _ax_get(app, AX.kAXWindowsAttribute) or []
    if not windows:
        return ["(no AX windows exposed for this pid -- app may be backgrounded or expose no AX tree)"]

    lines = []
    counter = [0]
    seen = set()
    for w in windows:
        title = _ax_get(w, AX.kAXTitleAttribute) or "(untitled window)"
        lines.append(f"--- window: {title} ---")
        _walk(w, 0, max_depth, max_nodes, counter, lines, seen)

    if not any(line.strip() and not line.startswith("---") for line in lines):
        lines.append("(no text content found -- app may render via a custom GPU surface with no AX text)")
    return lines


def stream_content(pid, owner_name, interval=3):
    print(f"streaming AX content of pid {pid} ({owner_name}) every {interval}s. Ctrl+C to stop.\n")
    last = None
    try:
        while True:
            if not _pid_alive(pid):
                raise RuntimeError(f"pid {pid} is no longer running")
            snapshot = "\n".join(dump_ax_content(pid))
            ts = time.strftime("%H:%M:%S")
            if snapshot != last:
                print(f"\n=== [{ts}] {owner_name} (pid {pid}) -- content changed ===")
                print(snapshot)
                last = snapshot
            else:
                print(f"[{ts}] (no change)")
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\nstopped streaming.")


# ---------------------------------------------------------------------------
# Quit (PID-bound app termination -> SIGTERM -> SIGKILL)
# ---------------------------------------------------------------------------

def _positive_pid(value):
    try:
        pid = int(value)
    except (TypeError, ValueError):
        raise argparse.ArgumentTypeError("PID must be a positive integer")
    if pid <= 0:
        raise argparse.ArgumentTypeError("PID must be a positive integer")
    return pid


def _positive_interval(value):
    try:
        interval = float(value)
    except (TypeError, ValueError):
        raise argparse.ArgumentTypeError("interval must be a positive finite number")
    if not math.isfinite(interval) or interval <= 0:
        raise argparse.ArgumentTypeError("interval must be a positive finite number")
    return interval


def _process_start(pid):
    """Use the app's native launch date as a PID-reuse guard."""
    app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
    if app is None or app.launchDate() is None:
        return None
    return app.launchDate().timeIntervalSinceReferenceDate()


def _same_process(pid, start):
    return start is not None and _process_start(pid) == start


def _target_state(pid, start):
    if _same_process(pid, start):
        return "running"
    return "changed" if _pid_alive(pid) else "exited"

def _pid_alive(pid):
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


def quit_process(pid, owner_name, grace_seconds=3):
    _require_macos_runtime()
    if pid <= 0:
        raise ValueError("PID must be positive")
    start = _process_start(pid)
    if start is None:
        print(f"  pid {pid} is not a running macOS app with an inspectable launch date.")
        return False
    print(f"attempting graceful quit of '{owner_name}' (pid {pid})...")
    try:
        app = NSRunningApplication.runningApplicationWithProcessIdentifier_(pid)
        if app is not None:
            app.terminate()
    except Exception as e:
        print(f"  (graceful quit attempt errored: {e})")

    deadline = time.time() + grace_seconds
    while time.time() < deadline:
        state = _target_state(pid, start)
        if state == "exited":
            print("  quit succeeded (graceful).")
            return True
        if state == "changed":
            print("  target changed; refusing to signal it.")
            return False
        time.sleep(0.3)

    print("  still running -- sending SIGTERM...")
    state = _target_state(pid, start)
    if state != "running":
        print("  target exited before SIGTERM." if state == "exited" else "  target changed; refusing to signal it.")
        return state == "exited"
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        print("  quit succeeded (process already gone).")
        return True
    except PermissionError:
        print("  permission denied sending SIGTERM (not the owner of this process?).")
        return False

    deadline = time.time() + grace_seconds
    while time.time() < deadline:
        state = _target_state(pid, start)
        if state == "exited":
            print("  quit succeeded (SIGTERM).")
            return True
        if state == "changed":
            print("  target changed; refusing to signal it.")
            return False
        time.sleep(0.3)

    print("  still running -- sending SIGKILL (force quit)...")
    state = _target_state(pid, start)
    if state != "running":
        print("  target exited before SIGKILL." if state == "exited" else "  target changed; refusing to signal it.")
        return state == "exited"
    try:
        os.kill(pid, signal.SIGKILL)
        deadline = time.time() + grace_seconds
        while time.time() < deadline:
            state = _target_state(pid, start)
            if state == "exited":
                print("  force-killed.")
                return True
            if state == "changed":
                print("  target changed after SIGKILL.")
                return False
            time.sleep(0.3)
        print("  process still appears to be running after SIGKILL.")
        return False
    except (ProcessLookupError, PermissionError) as e:
        print(f"  could not force-kill: {e}")
        return False


# ---------------------------------------------------------------------------
# Interactive menu
# ---------------------------------------------------------------------------

def interactive_menu(apps):
    if not apps:
        return
    print("\nSelect an app to act on (number), or Enter to skip:")
    choice = input("> ").strip()
    if not choice:
        return
    try:
        index = int(choice)
        if index < 0:
            raise IndexError
        target = apps[index]
    except (ValueError, IndexError):
        print("invalid selection.")
        return

    print(f"\nSelected: pid {target['pid']} ({target['owner']})")
    action = input("Action -- [q]uit app, [d]ump content once, [s]tream content, [Enter] cancel: ").strip().lower()
    if action == "q":
        quit_process(target["pid"], target["owner"])
    elif action == "d":
        for line in dump_ax_content(target["pid"]):
            print(line)
    elif action == "s":
        stream_content(target["pid"], target["owner"])
    else:
        print("cancelled.")


# ---------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="camoscope",
        description="Inspect on-screen macOS windows with WindowServer sharing state zero.",
    )
    parser.add_argument("--version", action="version", version="%(prog)s 0.1.1")
    parser.add_argument("--watch", action="store_true", help="continuously rescan for hidden windows")
    parser.add_argument("--no-prompt", action="store_true", help="scan once, print, and exit (no menu)")
    parser.add_argument("--quit", type=_positive_pid, metavar="PID", help="quit the process at PID non-interactively")
    parser.add_argument("--dump", type=_positive_pid, metavar="PID", help="dump AX content of PID once, non-interactively")
    parser.add_argument("--stream", type=_positive_pid, metavar="PID", help="stream AX content of PID, non-interactively")
    parser.add_argument("--interval", type=_positive_interval, default=3, help="seconds between --stream refreshes (default 3)")
    parser.add_argument("--no-content", action="store_true", help="one-shot scan: skip the AX content preview")
    parser.add_argument("--content", action="store_true", help="--watch mode: also print AX content each rescan (off by default -- noisier/slower)")
    args = parser.parse_args(argv)

    try:
        _require_macos_runtime()
    except RuntimeError as error:
        print(f"camoscope: {error}", file=sys.stderr)
        return 2

    def owner_for(pid):
        for h in scan_hidden_windows():
            if h["pid"] == pid:
                return h["owner"]
        return None

    try:
        if args.quit is not None:
            owner = owner_for(args.quit)
            if owner is None:
                raise RuntimeError(f"pid {args.quit} has no window with WindowServer sharing state zero")
            return 0 if quit_process(args.quit, owner) else 1
        if args.dump is not None:
            for line in dump_ax_content(args.dump):
                print(line)
            return 0
        if args.stream is not None:
            stream_content(args.stream, owner_for(args.stream) or str(args.stream), interval=args.interval)
            return 0

        if args.watch:
            print("Watching for WindowServer sharing-state-zero windows (Ctrl+C to stop)...")
            try:
                while True:
                    print_report(_dedupe_by_app(scan_hidden_windows()), show_content=args.content)
                    time.sleep(2)
            except KeyboardInterrupt:
                print("\nstopped.")
            return 0

        apps = _dedupe_by_app(scan_hidden_windows())
        print_report(apps, show_content=not args.no_content)
        if not args.no_prompt:
            interactive_menu(apps)
        return 0
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"camoscope: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
