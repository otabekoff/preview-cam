# Code signing

Windows SmartScreen warns about downloads that are not signed by a publisher
it trusts. Preview Cam releases can be signed free of charge through the
[SignPath Foundation](https://signpath.org) programme for open-source
projects: SignPath signs the binaries with a certificate issued to SignPath
Foundation, after checking that they were built from this repository by
GitHub Actions.

The release workflow already contains the signing steps. They stay inactive
until the two repository settings in step 4 exist, so releases keep working
(unsigned) in the meantime.

## One-time setup

1. **Apply.** Fill in the form at <https://signpath.org/apply> for
   `https://github.com/otabekoff/preview-cam`. SignPath Foundation reviews
   the project against its [terms](https://signpath.org/terms) and decides
   whether to accept it; this is a manual review on their side.
   What the terms ask of the project, and where it is covered:

   | Requirement | Status |
   | --- | --- |
   | OSI-approved licence, no proprietary parts | MIT, see `LICENSE` |
   | Released and documented | GitHub releases, `README.md` |
   | "Code signing policy" on the project page | `README.md` |
   | Privacy statement | `README.md` (no network use) |
   | Product name and version in every signed binary | `Runner.rc`, `windows/vcam/vcam.rc`, installer version keys |
   | Uninstaller | provided by the installer |
   | Multi-factor authentication for all team members | enable on GitHub and SignPath |
   | Each signing request approved by a team member | done in SignPath per release |

2. **Create the project in SignPath** (after acceptance) with these names,
   which the workflow expects:

   - project slug: `preview-cam`
   - signing policy slug: `release-signing`
   - artifact configuration `app`: contents of `installer/signpath/app.xml`
   - artifact configuration `installer`: contents of
     `installer/signpath/installer.xml`

3. **Connect GitHub.** Install the SignPath GitHub App for this repository,
   add "GitHub.com" as a trusted build system in the SignPath organisation
   and link it to the project.

4. **Add the repository settings** (GitHub → Settings → Secrets and
   variables → Actions):

   - secret `SIGNPATH_API_TOKEN`: API token of a SignPath user allowed to
     submit signing requests
   - variable `SIGNPATH_ORGANIZATION_ID`: the SignPath organisation id

## What a release does once signing is configured

1. Builds the application.
2. Sends `preview.exe` and `preview_vcam.dll` to SignPath and waits; an
   approver confirms the request in SignPath.
3. Builds the installer and the portable zip from the signed binaries.
4. Sends the installer to SignPath (second approval) and publishes the
   signed files as the GitHub release.

## Building locally

Local builds are never signed; `installer\build.ps1` produces the same files
without a signature.
