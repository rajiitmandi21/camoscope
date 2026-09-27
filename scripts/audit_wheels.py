"""Fail a release if a wheel exposes the implementation or lacks coverage."""

import argparse
from pathlib import Path
import re
import tomllib
from zipfile import ZipFile


PYTHONS = {"39", "310", "311", "312", "313", "314"}
ARCHES = {"arm64", "x86_64"}
ALLOWED_PYTHON = {"camoscope/__init__.py", "camoscope/__main__.py"}


def audit(directory: Path, require_complete_matrix: bool) -> None:
    with open("pyproject.toml", "rb") as source:
        version = tomllib.load(source)["project"]["version"]
    files = sorted(path for path in directory.iterdir() if not path.name.startswith("."))
    if not files or any(path.suffix != ".whl" for path in files):
        raise SystemExit("release directory must contain wheels only")

    coverage = set()
    for wheel in files:
        pattern = rf"camoscope-{re.escape(version)}-cp(3(?:9|10|11|12|13|14))-cp\1-macosx_\d+_\d+_(arm64|x86_64)\.whl"
        match = re.fullmatch(pattern, wheel.name)
        if match is None:
            raise SystemExit(f"unexpected wheel name or platform: {wheel.name}")
        coverage.add((match.group(1), match.group(2)))

        with ZipFile(wheel) as archive:
            names = archive.namelist()
            implementation = [name for name in names if name.startswith("camoscope/")]
            if not any(name.startswith("camoscope/cli.") and name.endswith(".so") for name in implementation):
                raise SystemExit(f"compiled CLI missing from {wheel.name}")
            exposed = [name for name in names if name.endswith((".py", ".pyx", ".c", ".h")) and name not in ALLOWED_PYTHON]
            if exposed:
                raise SystemExit(f"readable implementation found in {wheel.name}: {exposed}")
        print(f"audited {wheel.name}")

    expected = {(python, arch) for python in PYTHONS for arch in ARCHES}
    if require_complete_matrix and coverage != expected:
        raise SystemExit(f"wheel coverage differs: missing={sorted(expected - coverage)}, extra={sorted(coverage - expected)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--require-complete-matrix", action="store_true")
    arguments = parser.parse_args()
    audit(arguments.directory, arguments.require_complete_matrix)
