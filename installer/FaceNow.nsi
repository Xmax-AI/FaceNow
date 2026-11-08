Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"
!include "WordFunc.nsh"
!insertmacro VersionCompare

!ifndef PAYLOAD
  !error "Define PAYLOAD, OUTPUT, VERSION, SIZE_KB and UNINSTALL_MANIFEST."
!endif
!ifndef WEBVIEW2_BOOTSTRAPPER
  !error "Define WEBVIEW2_BOOTSTRAPPER using the verified Microsoft Evergreen bootstrapper."
!endif
!ifdef OVERSEAS
!define PRODUCT "FaceNow Overseas"
!define PRODUCT_ID "FaceNowOverseas"
!define OTHER_ID "FaceNow"
!define WEBSITE "https://xmax.ai"
!define REQUIRE_WINDOWS "FaceNow requires Windows 10 version 2004 or later (x64), or 64-bit Windows 11."
!define CLOSE_FIRST "Please close FaceNow before continuing."
!define REMOVE_FAILED "The virtual camera could not be removed. Close apps using FaceNow, then try again."
!define LAUNCH_LABEL "Launch FaceNow"
!define WEBVIEW2_PROGRESS "Installing the security verification component..."
!define WEBVIEW2_FAILED "WebView2 could not be installed. FaceNow can still be installed. Download WebView2 from the sign-in dialog or sign in with an API Key."
!else
!define PRODUCT "FaceNow"
!define PRODUCT_ID "FaceNow"
!define OTHER_ID "FaceNowOverseas"
!define WEBSITE "https://xmaxai.com"
!define REQUIRE_WINDOWS "FaceNow 需要 Windows 10 2004 或更新版本（x64），或 64 位 Windows 11。"
!define CLOSE_FIRST "请先关闭 FaceNow 后继续。"
!define REMOVE_FAILED "无法移除虚拟摄像头，请关闭正在使用它的应用后重试。"
!define LAUNCH_LABEL "启动 FaceNow"
!define WEBVIEW2_PROGRESS "正在安装安全验证组件…"
!define WEBVIEW2_FAILED "未能安装 WebView2，FaceNow 将继续安装。你可以从登录页弹窗前往官网下载 WebView2，或使用 API Key 登录。"
!endif
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_ID}"
Name "${PRODUCT}"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\${PRODUCT_ID}"
InstallDirRegKey HKCU "${REGKEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64
SetDatablockOptimize on
CRCCheck force
ManifestDPIAware true
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${PRODUCT}"
VIAddVersionKey /LANG=1033 "FileDescription" "${PRODUCT} Setup"
VIAddVersionKey /LANG=1033 "CompanyName" "XMAX.AI PTE. LTD."
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright 2026 XMAX.AI PTE. LTD."
!define MUI_ICON "..\assets\FaceNow.ico"
!define MUI_UNICON "..\assets\FaceNow.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\FaceNow.exe"
!define MUI_FINISHPAGE_RUN_TEXT "${LAUNCH_LABEL}"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!ifdef OVERSEAS
!insertmacro MUI_LANGUAGE "English"
!else
!insertmacro MUI_LANGUAGE "SimpChinese"
!endif
!include "${UNINSTALL_MANIFEST}"
Var WebView2Present

; Microsoft documents these per-user and per-machine Evergreen registration locations.
Function CheckWebView2Version
  ${VersionCompare} "$0" "0.0.0.0" $1
  ${If} $0 != ""
  ${AndIf} $1 == 1
    StrCpy $WebView2Present 1
  ${EndIf}
FunctionEnd

Function DetectWebView2
  StrCpy $WebView2Present 0
  SetRegView 32
  ReadRegStr $0 HKLM "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"
  Call CheckWebView2Version
  ReadRegStr $0 HKCU "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"
  Call CheckWebView2Version
  SetRegView 64
  ReadRegStr $0 HKCU "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" "pv"
  Call CheckWebView2Version
FunctionEnd

Function EnsureWebView2
  Call DetectWebView2
  ${If} $WebView2Present == 1
    Return
  ${EndIf}
  DetailPrint "${WEBVIEW2_PROGRESS}"
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File /oname=MicrosoftEdgeWebview2Setup.exe "${WEBVIEW2_BOOTSTRAPPER}"
  ClearErrors
  ExecWait '$\"$PLUGINSDIR\MicrosoftEdgeWebview2Setup.exe$\" /silent /install' $2
  ; Verify registration instead of treating a successful process exit as installed.
  Call DetectWebView2
  ${If} $WebView2Present != 1
    DetailPrint "${WEBVIEW2_FAILED}"
  ${EndIf}
FunctionEnd

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "${REQUIRE_WINDOWS}"
    SetErrorLevel 2
    Abort
  ${EndIf}
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"
  ${If} $0 < 19041
    MessageBox MB_ICONSTOP "${REQUIRE_WINDOWS}"
    SetErrorLevel 2
    Abort
  ${EndIf}
  ${If} $0 < 22000
  ${AndIf} ${IsNativeARM64}
    MessageBox MB_ICONSTOP "${REQUIRE_WINDOWS}"
    SetErrorLevel 2
    Abort
  ${EndIf}
  SetRegView 64
  SetShellVarContext current
  Call CheckRunning
FunctionEnd

!macro CheckRunning Prefix
Function ${Prefix}CheckRunning
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\XMAX.AI.${PRODUCT_ID}.Running") p.r0'
  ${If} $0 != 0
    System::Call 'kernel32::CloseHandle(p r0)'
    IfSilent +2
      MessageBox MB_ICONINFORMATION "${CLOSE_FIRST}"
    SetErrorLevel 2
    Abort
  ${EndIf}
FunctionEnd
!macroend
!insertmacro CheckRunning ""
!insertmacro CheckRunning "un."

Section "FaceNow"
  Call EnsureWebView2
  SetOutPath "$INSTDIR"
  SetOverwrite on
  ; Remove the application-owned helper when upgrading to SDK beauty.
  Delete "$INSTDIR\FaceNow.BeautyWorker.exe"
  ClearErrors
  File /r "${PAYLOAD}\*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortCut "$SMPROGRAMS\${PRODUCT}.lnk" "$INSTDIR\FaceNow.exe" "" "$INSTDIR\Assets\FaceNow.ico"
  CreateShortCut "$DESKTOP\${PRODUCT}.lnk" "$INSTDIR\FaceNow.exe" "" "$INSTDIR\Assets\FaceNow.ico"
  WriteRegStr HKCU "${REGKEY}" "DisplayName" "${PRODUCT}"
  WriteRegStr HKCU "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${REGKEY}" "Publisher" "XMAX.AI PTE. LTD."
  WriteRegStr HKCU "${REGKEY}" "URLInfoAbout" "${WEBSITE}"
  WriteRegStr HKCU "${REGKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${REGKEY}" "DisplayIcon" "$INSTDIR\FaceNow.exe"
  WriteRegStr HKCU "${REGKEY}" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
  WriteRegStr HKCU "${REGKEY}" "QuietUninstallString" '$\"$INSTDIR\Uninstall.exe$\" /S'
  WriteRegDWORD HKCU "${REGKEY}" "EstimatedSize" ${SIZE_KB}
  WriteRegDWORD HKCU "${REGKEY}" "NoModify" 1
  WriteRegDWORD HKCU "${REGKEY}" "NoRepair" 1
SectionEnd

Function un.onInit
  SetRegView 64
  SetShellVarContext current
  Call un.CheckRunning
FunctionEnd

Section "Uninstall"
  ; Both editions share one camera. Do not remove it while the other product is installed.
  ReadRegStr $2 HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${OTHER_ID}" "InstallLocation"
  StrCmp $2 "" check_camera_remove
  IfFileExists "$2\FaceNow.exe" keep_shared_camera check_camera_remove
check_camera_remove:
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/KEEP_CAMERA" $1
  ${If} ${Errors}
    ClearErrors
    ReadRegStr $1 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"
    StrCpy $0 0
    ${If} $1 >= 22000
      ${If} ${IsNativeARM64}
        ExecWait '$\"$INSTDIR\Camera\arm64\FaceNow.CameraControl.exe$\" --remove' $0
      ${Else}
        ExecWait '$\"$INSTDIR\Camera\x64\FaceNow.CameraControl.exe$\" --remove' $0
      ${EndIf}
    ${EndIf}
    ${IfNot} ${Errors}
    ${AndIf} $0 == 0
    ${AndIf} ${FileExists} "$INSTDIR\Camera\directshow-x64\FaceNow.CameraControl.exe"
      ; Also remove a DirectShow device left after an upgrade from Windows 10 to 11.
      ExecWait '$\"$INSTDIR\Camera\directshow-x64\FaceNow.CameraControl.exe$\" --remove' $0
    ${EndIf}
    ${If} ${Errors}
    ${OrIf} $0 != 0
      IfSilent +2
        MessageBox MB_ICONEXCLAMATION "${REMOVE_FAILED}"
      SetErrorLevel 2
      Abort
    ${EndIf}
  ${EndIf}
keep_shared_camera:
  !insertmacro RemovePayload
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$SMPROGRAMS\${PRODUCT}.lnk"
  Delete "$DESKTOP\${PRODUCT}.lnk"
  DeleteRegKey HKCU "${REGKEY}"
  RMDir "$INSTDIR"
SectionEnd
