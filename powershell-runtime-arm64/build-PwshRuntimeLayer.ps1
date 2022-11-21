####################
# PwshRuntimeLayer #
####################
Write-Host "Downloading Powershell for PwshRuntimeLayer" -foregroundcolor "green"
Write-Host $PSScriptRoot
$PWSH_VERSION = "7.3.0"
$PWSH_ARCHITECTURE = "arm64" #"x64" or #"arm64"
Invoke-WebRequest  -Uri https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-$PWSH_ARCHITECTURE.tar.gz -OutFile  $PSScriptRoot\powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz

Write-Host "Extracting Powershell"$PWSH_VERSION" for "$PWSH_ARCHITECTURE "to:" $PSScriptRoot/powershell -foregroundcolor "green"
If (!(Test-Path "$PSScriptRoot\pwsh-runtime\powershell")) {New-Item -ItemType Directory -Force -Path "$PSScriptRoot\pwsh-runtime\powershell" > $null}
tar zxf  $PSScriptRoot/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz -C  $PSScriptRoot/pwsh-runtime/powershell

Write-Host "Deleting PowerShell download" -foregroundcolor "green"
Remove-Item  $PSScriptRoot/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz