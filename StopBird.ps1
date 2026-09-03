$currentScript = $MyInvocation.MyCommand.Path
$installRoot = Split-Path -Parent $currentScript
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $PID -and
        $_.Name -match '^powershell(\.exe)?$' -and
        $_.CommandLine -like "*$installRoot\CodexBirdPet.ps1*"
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
