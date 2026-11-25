$ErrorActionPreference = 'Stop'
foreach ($existing in @(Get-Process -Name FaceNow -ErrorAction SilentlyContinue)) {
    if ($existing.HasExited) { continue }
    if (!$existing.CloseMainWindow() -or !$existing.WaitForExit(30000)) {
        throw "Close the existing FaceNow instance (PID $($existing.Id)) before opening another build."
    }
}
if (@(Get-Process -Name FaceNow -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'FaceNow is still running. Close it before opening another build.'
}
