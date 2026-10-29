Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!ifndef PAYLOAD
  !error "Define PAYLOAD, OUTPUT, VERSION, SIZE_KB and UNINSTALL_MANIFEST."
!endif
!define PRODUCT "FaceNow"
!define REGKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\FaceNow"
Name "FaceNow"
OutFile "${OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\FaceNow"
InstallDirRegKey HKCU "${REGKEY}" "InstallLocation"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64
SetDatablockOptimize on
CRCCheck force
ManifestDPIAware true
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "FaceNow"
VIAddVersionKey /LANG=1033 "FileDescription" "FaceNow Setup"
VIAddVersionKey /LANG=1033 "CompanyName" "XMAX.AI PTE. LTD."
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Copyright 2026 XMAX.AI PTE. LTD."
!define MUI_ICON "..\assets\FaceNow.ico"
!define MUI_UNICON "..\assets\FaceNow.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\FaceNow.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch FaceNow"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"
!include "${UNINSTALL_MANIFEST}"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "FaceNow requires 64-bit Windows 11."
    SetErrorLevel 2
    Abort
  ${EndIf}
  ReadRegStr $0 HKLM "SOFTWARE\Microsoft\Windows NT\CurrentVersion" "CurrentBuildNumber"
  ${If} $0 < 22000
    MessageBox MB_ICONSTOP "FaceNow requires Windows 11 or later."
    SetErrorLevel 2
    Abort
  ${EndIf}
  SetRegView 64
  SetShellVarContext current
  Call CheckRunning
FunctionEnd

!macro CheckRunning Prefix
Function ${Prefix}CheckRunning
  System::Call 'kernel32::OpenMutexW(i 0x100000, i 0, w "Local\XMAX.AI.FaceNow.Running") p.r0'
  ${If} $0 != 0
    System::Call 'kernel32::CloseHandle(p r0)'
    IfSilent +2
      MessageBox MB_ICONINFORMATION "Please close FaceNow before continuing."
    SetErrorLevel 2
    Abort
  ${EndIf}
FunctionEnd
!macroend
!insertmacro CheckRunning ""
!insertmacro CheckRunning "un."

Section "FaceNow"
  SetOutPath "$INSTDIR"
  SetOverwrite on
  File /r "${PAYLOAD}\*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortCut "$SMPROGRAMS\FaceNow.lnk" "$INSTDIR\FaceNow.exe" "" "$INSTDIR\Assets\FaceNow.ico"
  CreateShortCut "$DESKTOP\FaceNow.lnk" "$INSTDIR\FaceNow.exe" "" "$INSTDIR\Assets\FaceNow.ico"
  WriteRegStr HKCU "${REGKEY}" "DisplayName" "FaceNow"
  WriteRegStr HKCU "${REGKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${REGKEY}" "Publisher" "XMAX.AI PTE. LTD."
  WriteRegStr HKCU "${REGKEY}" "URLInfoAbout" "https://www.xmaxsi.com/"
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
  ${GetParameters} $0
  ClearErrors
  ${GetOptions} $0 "/KEEP_CAMERA" $1
  ${If} ${Errors}
    ${If} ${IsNativeARM64}
      ExecWait '$\"$INSTDIR\Camera\arm64\FaceNow.CameraControl.exe$\" --remove' $0
    ${Else}
      ExecWait '$\"$INSTDIR\Camera\x64\FaceNow.CameraControl.exe$\" --remove' $0
    ${EndIf}
    ${If} $0 != 0
      IfSilent +2
        MessageBox MB_ICONEXCLAMATION "The virtual camera could not be removed. Close apps using FaceNow, then try again."
      SetErrorLevel 2
      Abort
    ${EndIf}
  ${EndIf}
  !insertmacro RemovePayload
  Delete "$INSTDIR\Uninstall.exe"
  Delete "$SMPROGRAMS\FaceNow.lnk"
  Delete "$DESKTOP\FaceNow.lnk"
  DeleteRegKey HKCU "${REGKEY}"
  RMDir "$INSTDIR"
SectionEnd
