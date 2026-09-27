import pytest
from types import SimpleNamespace

from camoscope import __version__
from camoscope import cli


def test_version_is_exposed():
    assert __version__ == "0.1.3"


def test_version_flag_is_available(capsys):
    with pytest.raises(SystemExit) as raised:
        cli.main(["--version"])

    assert raised.value.code == 0
    assert capsys.readouterr().out.strip() == "camoscope 0.1.3"


def test_linux_install_has_a_clear_runtime_message(monkeypatch, capsys):
    monkeypatch.setattr(cli.sys, "platform", "linux")

    assert cli.main(["--no-prompt"]) == 2
    assert "not supported" in capsys.readouterr().err


def test_macos_install_without_optional_dependencies_has_a_clear_message(monkeypatch, capsys):
    monkeypatch.setattr(cli.sys, "platform", "darwin")
    monkeypatch.setattr(cli, "AX", None)
    monkeypatch.setattr(cli, "Quartz", None)

    assert cli.main(["--no-prompt"]) == 2
    assert "macOS dependencies are missing" in capsys.readouterr().err


def test_dedupe_keeps_one_row_per_process():
    hidden = [
        {"pid": 42, "name": "HUD", "w": 500, "h": 100},
        {"pid": 42, "name": "Recording Bar", "w": 700, "h": 60},
        {"pid": 99, "name": "Other", "w": 300, "h": 200},
    ]

    result = cli._dedupe_by_app(hidden)

    assert [item["pid"] for item in result] == [42, 99]
    assert result[0]["windows"] == ["HUD", "Recording Bar"]
    assert result[0]["count"] == 2
    assert result[0]["w"] == 700
    assert result[0]["h"] == 60


def test_identity_flag_is_a_hint_for_unsigned_system_named_process():
    hidden = {
        "owner": "python3.1",
        "identity": {"path": "/tmp/python3.1", "signed": False},
    }

    assert "unsigned binary" in cli._identity_flag(hidden)


def test_macos_only_operations_fail_cleanly_off_macos(monkeypatch):
    monkeypatch.setattr(cli.sys, "platform", "linux")

    with pytest.raises(RuntimeError, match="not supported"):
        cli.scan_hidden_windows()

    with pytest.raises(RuntimeError, match="not supported"):
        cli.dump_ax_content(123)


def test_scan_quit_dump_and_stream_routes(monkeypatch, capsys):
    hidden = [{"pid": 42, "owner": "Recorder", "name": "HUD", "w": 10, "h": 20}]
    calls = []

    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(cli, "scan_hidden_windows", lambda: hidden)
    monkeypatch.setattr(cli, "print_report", lambda apps, **kwargs: calls.append(("scan", apps, kwargs)))
    monkeypatch.setattr(cli, "quit_process", lambda pid, owner: calls.append(("quit", pid, owner)) or True)
    monkeypatch.setattr(cli, "dump_ax_content", lambda pid: [f"content for {pid}"])
    monkeypatch.setattr(
        cli,
        "stream_content",
        lambda pid, owner, interval: calls.append(("stream", pid, owner, interval)),
    )

    assert cli.main(["--no-prompt", "--no-content"]) == 0
    assert cli.main(["--quit", "42"]) == 0
    assert cli.main(["--dump", "42"]) == 0
    assert cli.main(["--stream", "42", "--interval", "1.5"]) == 0

    assert calls[0][0] == "scan"
    assert calls[1] == ("quit", 42, "Recorder")
    assert calls[2] == ("stream", 42, "Recorder", 1.5)
    assert "content for 42" in capsys.readouterr().out


@pytest.mark.parametrize("option", ["--quit", "--dump", "--stream"])
@pytest.mark.parametrize("pid", ["0", "-1", "abc"])
def test_invalid_pid_rejected_before_runtime_or_scan(monkeypatch, option, pid):
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: pytest.fail("runtime reached"))
    with pytest.raises(SystemExit) as raised:
        cli.main([option, pid])
    assert raised.value.code == 2


@pytest.mark.parametrize("value", ["0", "-1", "nan", "inf"])
def test_invalid_stream_interval_rejected(value):
    with pytest.raises(SystemExit) as raised:
        cli.main(["--stream", "42", "--interval", value])
    assert raised.value.code == 2


def test_failed_quit_is_failure_exit(monkeypatch):
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(cli, "scan_hidden_windows", lambda: [{"pid": 42, "owner": "Fixture"}])
    monkeypatch.setattr(cli, "quit_process", lambda pid, owner: False)
    assert cli.main(["--quit", "42"]) == 1


def test_window_enumeration_failure_is_not_empty_scan(monkeypatch, capsys):
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(
        cli, "Quartz",
        SimpleNamespace(
            kCGWindowListOptionOnScreenOnly=1,
            kCGNullWindowID=0,
            CGWindowListCopyWindowInfo=lambda *_: None,
        ),
    )
    assert cli.main(["--no-prompt"]) == 1
    assert "window scan failed" in capsys.readouterr().err


def test_scan_selects_only_zero_sharing_state(monkeypatch):
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    windows = [
        {"kCGWindowOwnerPID": 42, "kCGWindowOwnerName": "Fixture", "kCGWindowSharingState": 0},
        {"kCGWindowOwnerPID": 43, "kCGWindowOwnerName": "Other", "kCGWindowSharingState": 1},
        {"kCGWindowOwnerPID": 44, "kCGWindowOwnerName": "Unspecified"},
    ]
    monkeypatch.setattr(
        cli, "Quartz",
        SimpleNamespace(
            kCGWindowListOptionOnScreenOnly=1,
            kCGNullWindowID=0,
            CGWindowListCopyWindowInfo=lambda *_: windows,
        ),
    )
    monkeypatch.setattr(cli, "get_process_identity", lambda pid: {})
    assert [item["pid"] for item in cli.scan_hidden_windows()] == [42]


def test_quit_requires_pid_in_current_scan(monkeypatch, capsys):
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(cli, "scan_hidden_windows", lambda: [])
    monkeypatch.setattr(cli, "quit_process", lambda *args: pytest.fail("quit reached"))
    assert cli.main(["--quit", "42"]) == 1
    assert "no window" in capsys.readouterr().err


def test_signature_inspection_failure_stays_unknown(monkeypatch):
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(cli, "_real_executable_path", lambda pid: "/tmp/fixture")
    monkeypatch.setattr(
        cli.subprocess, "run",
        lambda *args, **kwargs: SimpleNamespace(returncode=1, stderr="codesign failed"),
    )
    assert cli.get_process_identity(42)["signed"] is None


def test_quit_uses_pid_bound_app_handle_and_stops_after_exit(monkeypatch):
    calls = []
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(cli, "_process_start", lambda pid: "start" if len(calls) == 0 else None)
    monkeypatch.setattr(cli, "_pid_alive", lambda pid: False)
    app = SimpleNamespace(terminate=lambda: calls.append("terminate"))
    monkeypatch.setattr(
        cli, "NSRunningApplication",
        SimpleNamespace(runningApplicationWithProcessIdentifier_=lambda pid: app),
    )
    monkeypatch.setattr(cli.os, "kill", lambda *args: pytest.fail("signal sent"))
    assert cli.quit_process(42, 'odd " name', grace_seconds=0.1) is True
    assert calls == ["terminate"]


def test_quit_refuses_signal_if_pid_fingerprint_changed(monkeypatch):
    calls = []
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(cli, "_process_start", lambda pid: "first" if not calls else "second")
    monkeypatch.setattr(cli, "_pid_alive", lambda pid: True)
    monkeypatch.setattr(
        cli, "NSRunningApplication",
        SimpleNamespace(runningApplicationWithProcessIdentifier_=lambda pid: SimpleNamespace(terminate=lambda: calls.append("terminate"))),
    )
    monkeypatch.setattr(cli.os, "kill", lambda *args: pytest.fail("signal sent"))
    assert cli.quit_process(42, "Fixture", grace_seconds=0) is False


def test_ax_denial_fails_dump_command(monkeypatch, capsys):
    monkeypatch.setattr(cli, "_require_macos_runtime", lambda: None)
    monkeypatch.setattr(cli, "AX", SimpleNamespace(AXIsProcessTrusted=lambda: False))
    assert cli.main(["--dump", "42"]) == 1
    assert "Accessibility access is denied" in capsys.readouterr().err
