; Preview Cam installer (NSIS 3, Unicode).
;
; Built by installer\build.ps1, which passes:
;   /DAPP_VERSION=1.0.0   version from pubspec.yaml
;   /DSOURCE_DIR=...      staged release files (application + VC++ runtime)
;   /DOUTPUT_FILE=...     path of the setup executable to write
;
; Installs per user, without administrator rights, into
; %LOCALAPPDATA%\Programs\Preview Cam.

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!include "MUI2.nsh"
!include "FileFunc.nsh"

!define APP_NAME "Preview Cam"
!define APP_EXE "preview.exe"
!define APP_PUBLISHER "uz.nurafshon"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\PreviewCam"
; Value written by the application's "Start with Windows" setting.
!define RUN_KEY "Software\Microsoft\Windows\CurrentVersion\Run"
!define RUN_VALUE "PreviewCam"
; Must match VCAM_CLSID_STRING in windows\vcam\vcam_protocol.h.
!define VCAM_CLSID "{5C2A7B1E-9D43-4E8A-B6F1-3A7C2D9E4F10}"

Name "${APP_NAME}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP_NAME}"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"
ShowInstDetails nevershow
ShowUninstDetails nevershow

VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "CompanyName" "${APP_PUBLISHER}"
VIAddVersionKey "FileDescription" "${APP_NAME} Setup"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 ${APP_PUBLISHER}"

!define MUI_ICON "..\windows\runner\resources\app_icon.ico"
!define MUI_UNICON "..\windows\runner\resources\app_icon.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!define MUI_FINISHPAGE_RUN_TEXT "Start ${APP_NAME}"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

; The overlay hides to the tray instead of closing, so a running copy has to
; be stopped before its files can be replaced or removed. Only the copy in
; the install folder is stopped; other programs that happen to be called
; preview.exe are left alone.
!macro StopRunningApp
  nsExec::Exec `powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Process preview -ErrorAction SilentlyContinue | Where-Object { $$_.Path -like '$INSTDIR\*' } | Stop-Process -Force"`
  Pop $0
  Sleep 500
!macroend

Section "${APP_NAME}" SecApp
  SectionIn RO
  !insertmacro StopRunningApp

  ; Start clean so files from an older version never linger.
  RMDir /r "$INSTDIR\data"
  SetOutPath "$INSTDIR"
  File /r "${SOURCE_DIR}\*.*"

  WriteUninstaller "$INSTDIR\uninstall.exe"
  CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"

  ; Entry in Settings > Apps > Installed apps.
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${APP_PUBLISHER}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" "$0"

  ; If "Start with Windows" was already on (e.g. for a copy run from another
  ; folder), point it at the installed application.
  ReadRegStr $0 HKCU "${RUN_KEY}" "${RUN_VALUE}"
  StrCmp $0 "" +2
    WriteRegStr HKCU "${RUN_KEY}" "${RUN_VALUE}" '"$INSTDIR\${APP_EXE}"'
SectionEnd

Section /o "Desktop shortcut" SecDesktop
  CreateShortcut "$DESKTOP\${APP_NAME}.lnk" "$INSTDIR\${APP_EXE}"
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecApp} "The camera overlay and a Start menu shortcut."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "Adds a shortcut to the desktop."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "Uninstall"
  !insertmacro StopRunningApp

  Delete "$SMPROGRAMS\${APP_NAME}.lnk"
  Delete "$DESKTOP\${APP_NAME}.lnk"
  DeleteRegValue HKCU "${RUN_KEY}" "${RUN_VALUE}"
  ; The "Preview Cam" virtual camera device (registered by the application
  ; when the setting is switched on) and its remembered output size.
  DeleteRegKey HKCU "Software\Classes\CLSID\{860BB310-5D01-11D0-BD3B-00A0C911CE86}\Instance\${VCAM_CLSID}"
  DeleteRegKey HKCU "Software\Classes\CLSID\${VCAM_CLSID}"
  DeleteRegKey HKCU "Software\PreviewCam"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"

  ; Only files this installer put there: the application's own folder.
  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\*.json"
  Delete "$INSTDIR\${APP_EXE}"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"

  ; Settings are kept unless the user asks (never asked in silent mode).
  IfSilent done
  MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 \
      "Also remove your ${APP_NAME} settings?" IDNO done
  RMDir /r "$APPDATA\${APP_PUBLISHER}\${APP_NAME}"
  RMDir "$APPDATA\${APP_PUBLISHER}"
  done:
SectionEnd
