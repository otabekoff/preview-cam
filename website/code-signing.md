# Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io), certificate
by [SignPath Foundation](https://signpath.org).

::: info Status
Preview Cam is applying to the SignPath Foundation programme for open-source
projects. Releases are unsigned until the project has been accepted; this
page describes how signing works once it is.
:::

## What gets signed

Only files built from the public source code at
[github.com/otabekoff/preview-cam](https://github.com/otabekoff/preview-cam)
by the project's
[release workflow](https://github.com/otabekoff/preview-cam/blob/main/.github/workflows/release.yml)
on GitHub Actions:

- `preview.exe` — the application
- `preview_vcam.dll` — the "Preview Cam" virtual camera
- `PreviewCam-Setup-<version>.exe` — the installer

Nothing built on a developer's machine is signed, and no third-party
binaries are signed.

## Team roles

| Role | Members |
| --- | --- |
| Committers and reviewers | [Otabek Sadiridinov](https://github.com/otabekoff) |
| Approvers | [Otabek Sadiridinov](https://github.com/otabekoff) |

Contributions from anyone else arrive as pull requests and are reviewed by a
committer before they are merged. Every signing request is approved
individually by an approver.

## Privacy

This program will not transfer any information to other networked systems
unless specifically requested by the user. The full statement is in the
[privacy policy](/privacy).

## Reporting a problem

If you believe a signed Preview Cam binary is malicious or was not built from
the published source, please
[open an issue](https://github.com/otabekoff/preview-cam/issues) or use
GitHub's private
[security advisory form](https://github.com/otabekoff/preview-cam/security/advisories/new).
