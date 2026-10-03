# Publishing Camoscope to PyPI

The `publish.yml` GitHub Actions workflow uses PyPI Trusted Publishing.
It has no stored PyPI API token. It publishes only from a version tag, checks
that the tag matches `pyproject.toml`, builds native macOS wheels, audits
their contents and platform coverage, and checks their metadata before
entering the `pypi` GitHub environment. Only the publish job receives OIDC
`id-token: write` permission. **Do not upload a source distribution.**

## Trusted Publisher configuration

`camoscope` is already published on PyPI through GitHub Actions Trusted
Publishing. Keep the publisher configuration aligned with these values:

| Field | Value |
| --- | --- |
| PyPI project | `camoscope` |
| GitHub owner | `rajiitmandi21` |
| GitHub repository | `camoscope` |
| Workflow file | `publish.yml` |
| GitHub environment | `pypi` |

In the GitHub repository, restrict the `pypi` environment to tags matching
`v*`. The workflow uses a manual
`workflow_dispatch` input named `publish` (default `false`) as the release
gate. Only `rajiitmandi21` can reach the publish job: both the original actor and
rerun actor must match that account. The `pypi` environment also requires
that account’s approval and disallows administrator bypass. Because the
owner dispatches and approves the release, self-approval is permitted. Keep
the release workflow reviewable: a contributor who can change it can affect
what gets published.

The GitHub repository is public under the MIT license. Source is available
for inspection and contribution. PyPI continues to distribute compiled macOS
wheels without a source archive; that packaging is a distribution choice,
not a source-secrecy claim. Review changes to the release workflow before
merging or dispatching a publication.

## Release steps

1. Confirm the release version has never been uploaded to PyPI. Bump the version in `pyproject.toml`,
   `src/camoscope/__init__.py`, the CLI `--version` string, and its tests.
2. Run tests, build a local macOS wheel, run `scripts/audit_wheels.py` and
   `twine check --strict`, and perform a clean macOS install smoke. Review
   the README and wheel contents for accurate permissions, local-only
   behavior, supported platform claims, and absence of readable audit source.
3. Push the reviewed commit, then dispatch `publish.yml` on `main` with
   `publish=false`. Inspect the complete wheel matrix and the audit job.
4. Create and push the matching annotated version tag. Dispatch
   `publish.yml` on that tag with `publish=true`. The build and audit jobs
   must pass again before the upload job runs in the tag-restricted `pypi`
   environment. PyPI matches the workflow's OIDC identity to the registered
   publisher.
5. Confirm the PyPI project page, version, compiled wheel files,
   provenance/attestations, and `python -m pip install camoscope==<version>`
   in fresh Intel and Apple Silicon macOS environments. There should be no
   source archive or Linux wheel on PyPI.
   Record the exact tag, workflow run, file digests, and install output.

Do not replace a published file in place. PyPI does not permit reusing a
distribution filename; make a new version for corrections. If PyPI
quarantines the release, use its documented appeal route rather than
altering the package to conceal its behavior.
