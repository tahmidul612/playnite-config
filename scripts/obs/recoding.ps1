param(
    [string]$scene,
    [string]$obsPath,
    [string]$obsWorkingDirectory,
    [string]$webSocket,
    [string]$action
)

# Load config file
$configPath = "$PSScriptRoot\obs-config.ps1"
if (-Not (Test-Path $configPath)) {
    Write-Host "Configuration file not found at $configPath. Please create it with required values (cfgScene, cfgObsPath, cfgObsWorkingDirectory, cfgWebSocket, cfgAction)."
    exit
}
. $configPath

$missingParams = @()

if (-not $scene) {
    if ($cfgScene) { $scene = $cfgScene } else { $missingParams += "cfgScene (scene)" }
}
if (-not $obsPath) {
    if ($cfgObsPath) { $obsPath = $cfgObsPath } else { $missingParams += "cfgObsPath (obsPath)" }
}
if (-not $obsWorkingDirectory) {
    if ($cfgObsWorkingDirectory) { $obsWorkingDirectory = $cfgObsWorkingDirectory } else { $missingParams += "cfgObsWorkingDirectory (obsWorkingDirectory)" }
}
if (-not $webSocket) {
    if ($cfgWebSocket) { $webSocket = $cfgWebSocket } else { $missingParams += "cfgWebSocket (webSocket)" }
}
if (-not $action) {
    if ($cfgAction) { $action = $cfgAction } else { $missingParams += "cfgAction (action)" }
}

if ($missingParams.Count -gt 0) {
    Write-Host "Missing configuration for: " + ($missingParams -join ", ")
    exit
}

Import-Module obs-powershell -PassThru -Force
$obs = Get-Process "obs64"
if ($action -eq "start") {
    if (-Not $obs) {
        Start-Process $obsPath -WorkingDirectory $obsWorkingDirectory -ArgumentList "--scene $scene --startrecording"
        Start-Sleep -Seconds 5
    }
    else {
        Connect-OBS -WebSocketToken $webSocket
        $recording = (Get-OBSRecordStatus).outputActive
        if ($recording) {
            Stop-OBSRecord -NoResponse
        }
        Set-OBSCurrentProgramScene -SceneName $scene
        Start-OBSRecord -NoResponse
    }
}
elseif ($action -eq "stop") {
    if ($obs) {
        Connect-OBS -WebSocketToken $webSocket
        Stop-OBSRecord -NoResponse
    }
}