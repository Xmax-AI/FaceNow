#!/usr/bin/env bash
set -euo pipefail
vm="${FACENOW_WINDOWS_VM:-Windows 11}"
source_root="${FACENOW_WINDOWS_SOURCE:?Set FACENOW_WINDOWS_SOURCE to the Windows path of this checkout's windows directory.}"
exec prlctl exec "$vm" --current-user powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$source_root\scripts\run.ps1" "$@"
