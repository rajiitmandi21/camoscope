# Publishing Camoscope to PyPI

The `publish.yml` GitHub Actions workflow uses PyPI Trusted Publishing.
It has no stored PyPI API token. It publishes only from a version tag, checks
that the tag matches `pyproject.toml`, builds native macOS wheels, audits
their contents and platform coverage, and checks their metadata before
entering the `pypi` GitHub environment. Only the publish job receives OIDC
`id-token: write` permission. **Do not upload a source distribution.**

## One-time account setup

1. Use a PyPI account with a verified email and register a **pending Trusted
   Publisher** for the new project `camoscope` at
   <https://pypi.org/manage/account/publishing/>. Select GitHub Actions and
   enter exactly:

   | Field | Value |
   | --- | --- |
   | PyPI project | `camoscope` |
   | GitHub owner | `rajiitmandi21` |
   | GitHub repository | `camoscope` |
   | Workflow file | `publish.yml` |
   | GitHub environment | `pypi` |

2. In the GitHub repository, protect the `pypi` environment with a required
   human reviewer and restrict deployment to tags matching `v*`. Keep the
   release workflow reviewable: a contributor who can change it can affect
   what gets published. PyPI's trusted-publisher guidance recommends this
   manual approval gate.

The GitHub repository remains private. PyPI receives only compiled macOS
wheels. The wheel contains a small Python entry-point stub and the compiled
audit extension, with no readable `cli.py` or `.pyx` source. Compiled code
can still be reverse engineered; this packaging limits casual source
inspection rather than guaranteeing secrecy.

## Release steps

1. Confirm the package name is available and the release version has never
   been uploaded to PyPI. Bump the version in `pyproject.toml`,
   `src/camoscope/__init__.py`, the CLI `--version` string, and its tests.
2. Run tests, build a local macOS wheel, run `scripts/audit_wheels.py` and
   `twine check --strict`, and perform a clean macOS install smoke. Review
   the README and wheel contents for accurate permissions, local-only
   behavior, supported platform claims, and absence of readable audit source.
3. Push the reviewed commit and matching annotated version tag.
4. Dispatch `publish.yml` on that tag. The build job must pass before a human
   approves the protected `pypi` environment. PyPI matches the workflow's
   OIDC identity to the pending publisher and creates the project on first
   successful upload.
5. Confirm the PyPI project page, version, compiled wheel files,
   provenance/attestations, and `python -m pip install camoscope==<version>`
   in fresh Intel and Apple Silicon macOS environments. There should be no
   source archive or Linux wheel on PyPI.
   Record the exact tag, workflow run, file digests, and install output.

Do not replace a published file in place. PyPI does not permit reusing a
distribution filename; make a new version for corrections. If PyPI
quarantines the release, use its documented appeal route rather than
altering the package to conceal its behavior.
