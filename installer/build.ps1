<#
.SYNOPSIS
  Builds the release application and packages it as a Windows installer.

.DESCRIPTION
  1. flutter build windows --release
  2. Stages the release folder together with the Visual C++ runtime DLLs the
     application needs (so it runs on machines without the VC++
     redistributable).
  3. Compiles installer\preview_cam.nsi with NSIS.

  Output: build\installer\PreviewCam-Setup-<version>.exe
          build\installer\PreviewCam-<version>-windows-portable.zip

.PARAMETER MakeNsis
  Path to makensis.exe. Defaults to the one on PATH or in the standard NSIS
  install folder. NSIS: https://nsis.sourceforge.io

.PARAMETER SkipBuild
  Package the existing release build instead of rebuilding it.
#>
param(
  [string]$MakeNsis,
  [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$release = Join-Path $root 'build\windows\x64\runner\Release'
$outDir = Join-Path $root 'build\installer'
$stage = Join-Path $outDir 'stage'

# --- Locate NSIS ---------------------------------------------------------
if (-not $MakeNsis) {
  $MakeNsis = (Get-Command makensis -ErrorAction SilentlyContinue).Source
}
if (-not $MakeNsis) {
  $MakeNsis = @(
    "${env:ProgramFiles(x86)}\NSIS\makensis.exe",
    "$env:ProgramFiles\NSIS\makensis.exe"
  ) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $MakeNsis -or -not (Test-Path $MakeNsis)) {
  throw 'makensis.exe not found. Install NSIS or pass -MakeNsis <path>.'
}

# --- Version from pubspec.yaml (1.2.3+4 -> 1.2.3) ------------------------
$versionLine = Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(\d+\.\d+\.\d+)'
if (-not $versionLine) { throw 'No version found in pubspec.yaml.' }
$version = $versionLine.Matches[0].Groups[1].Value

# --- Build ---------------------------------------------------------------
if (-not $SkipBuild) {
  # A previous build may have left plugin DLLs that are no longer used.
  if (Test-Path $release) {
    Get-ChildItem $release -Filter '*.dll' | Remove-Item -Force
  }
  Push-Location $root
  try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build failed.' }
  } finally {
    Pop-Location
  }
}
if (-not (Test-Path (Join-Path $release 'preview.exe'))) {
  throw "No release build at $release."
}

# --- Stage ---------------------------------------------------------------
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item (Join-Path $release '*') $stage -Recurse

# Visual C++ runtime, deployed app-locally. Prefer the redistributable copy
# shipped with Visual Studio; fall back to the system's.
$runtime = 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll'
$redist = Get-ChildItem "$env:ProgramFiles\Microsoft Visual Studio\*\*\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory -ErrorAction SilentlyContinue |
  Sort-Object FullName | Select-Object -Last 1
foreach ($dll in $runtime) {
  $source = if ($redist) { Join-Path $redist.FullName $dll } else { $null }
  if (-not $source -or -not (Test-Path $source)) {
    $source = Join-Path $env:SystemRoot "System32\$dll"
  }
  if (-not (Test-Path $source)) { throw "Visual C++ runtime file not found: $dll" }
  Copy-Item $source $stage
}

# --- Package -------------------------------------------------------------
$output = Join-Path $outDir "PreviewCam-Setup-$version.exe"
& $MakeNsis /V2 "/DAPP_VERSION=$version" "/DSOURCE_DIR=$stage" "/DOUTPUT_FILE=$output" (Join-Path $PSScriptRoot 'preview_cam.nsi')
if ($LASTEXITCODE -ne 0) { throw 'makensis failed.' }

# The same files as a zip, for running without installing.
$zip = Join-Path $outDir "PreviewCam-$version-windows-portable.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip

Remove-Item $stage -Recurse -Force
$size = '{0:N1} MB' -f ((Get-Item $output).Length / 1MB)
Write-Host "Installer: $output ($size)"
Write-Host "Portable:  $zip"
