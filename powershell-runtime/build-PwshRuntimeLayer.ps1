####################
# PwshRuntimeLayer #
####################
Write-Host "Downloading Powershell for PwshRuntimeLayer" -foregroundcolor "green"
Write-Host $PSScriptRoot
$PWSH_VERSION = "7.2.4"
$PWSH_ARCHITECTURE = "x64" #"x64" or #"arm64"
Invoke-WebRequest  -Uri https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-$PWSH_ARCHITECTURE.tar.gz -OutFile  $PSScriptRoot\powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz

Write-Host "Extracting Powershell"$PWSH_VERSION" for "$PWSH_ARCHITECTURE "to:" $PSScriptRoot/powershell -foregroundcolor "green"
if (!(Test-Path "$PSScriptRoot\pwsh-runtime\powershell")) {New-Item -ItemType Directory -Force -Path "$PSScriptRoot\pwsh-runtime\powershell" > $null}
tar zxf  $PSScriptRoot/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz -C  $PSScriptRoot/pwsh-runtime/powershell

Write-Host "Deleting PowerShell download" -foregroundcolor "green"
Remove-Item  $PSScriptRoot/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz

Write-Host "Merge all Private module content into a single .psm1 file to speed up module loading" -foregroundcolor "green"
If (!(Select-String -Path $PSScriptRoot/pwsh-runtime/modules/pwsh-runtime.psm1 -Pattern 'private:Get-Handler')) {
    Get-ChildItem -Path $PSScriptRoot/pwsh-runtime/modules/Private -Filter *.ps1 | ForEach-Object {Get-Content $_ | Select-Object -Skip 2 | Out-File -FilePath $PSScriptRoot/pwsh-runtime/modules/pwsh-runtime.psm1 -Append}
    Remove-Item  $PSScriptRoot/pwsh-runtime/modules/Private -Force -Recurse
} else {
    Write-Host "Private modules likely merged already, skipping" -foregroundcolor "green"
}
