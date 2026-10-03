# Download

Preview Cam runs on **Windows 10 and Windows 11 (64-bit)**. It is free and
open source.

<p class="download-actions">
  <a class="download-button" href="https://github.com/otabekoff/preview-cam/releases/latest">Download the latest release</a>
</p>

On the release page, choose one of:

| File | What it is |
| --- | --- |
| `PreviewCam-Setup-<version>.exe` | Installer. Installs for your user account, no administrator rights needed, adds a Start menu entry and an uninstaller. |
| `PreviewCam-<version>-windows-portable.zip` | Portable build. Unzip anywhere and run `preview.exe`. |

All versions are listed on the
[releases page](https://github.com/otabekoff/preview-cam/releases). Every
release is built from the public source code by
[GitHub Actions](https://github.com/otabekoff/preview-cam/actions/workflows/release.yml).

## Code signing

Free code signing provided by [SignPath.io](https://signpath.io), certificate
by [SignPath Foundation](https://signpath.org).

::: warning Not signed yet
Preview Cam is applying to the SignPath Foundation programme for open-source
projects. Until it is accepted, the downloads are **not** signed and Windows SmartScreen
shows an "unknown publisher" warning the first time you run them: choose
**More info → Run anyway**. See the
[code signing policy](/code-signing) for details.
:::

## Install

1. Run `PreviewCam-Setup-<version>.exe` and follow the wizard.
2. Start **Preview Cam** from the Start menu. The overlay opens in the
   bottom-right corner of your main screen.
3. Continue with [Getting started](/guide/getting-started).

## Update

Run the newer installer over the existing installation. Your settings are
kept.

## Uninstall

Windows **Settings → Apps → Installed apps → Preview Cam → Uninstall**. The
uninstaller removes the application, its shortcuts, the "Start with Windows"
entry and the virtual camera device, and asks whether to delete your settings
as well.

## Build it yourself

The source code and build instructions are in the
[GitHub repository](https://github.com/otabekoff/preview-cam#build-and-run).

<style scoped>
.download-actions { margin: 24px 0; }
.download-actions a.download-button {
  display: inline-block;
  border-radius: 20px;
  padding: 0 20px;
  line-height: 38px;
  font-size: 14px;
  font-weight: 600;
  text-decoration: none;
  color: var(--vp-button-brand-text);
  background-color: var(--vp-button-brand-bg);
}
.download-actions a.download-button:hover { background-color: var(--vp-button-brand-hover-bg); }
</style>
