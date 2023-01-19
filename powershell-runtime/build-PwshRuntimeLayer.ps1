####################
# PwshRuntimeLayer #
####################
Write-Host "Downloading Powershell for PwshRuntimeLayer" -foregroundcolor "green"
Write-Host $PSScriptRoot
# PWSH_VERSION is version of PowerShell to download
$PWSH_VERSION = "7.2.4"
# PWSH_ARCHITECTURE can be 'x64' or 'arm64'
$PWSH_ARCHITECTURE = "x64"

$sourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'source'
New-Item -Path $sourcePath -ItemType Directory -Force | Out-Null

Invoke-WebRequest  -Uri https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-$PWSH_ARCHITECTURE.tar.gz -OutFile  $sourcePath\powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz

Write-Host "Extracting Powershell"$PWSH_VERSION" for "$PWSH_ARCHITECTURE "to:" $sourcePath -foregroundcolor "green"
if (!(Test-Path "$sourcePath\powershell")) {New-Item -ItemType Directory -Force -Path "$sourcePath\powershell" > $null}
tar zxf  $sourcePath/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz -C  $sourcePath/powershell

Write-Host "Deleting PowerShell download" -foregroundcolor "green"
Remove-Item  $sourcePath/powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz

Write-Host "Copy additional runtime files, including bootstrap. Remove Makefile from destination" -foregroundcolor "green"

# cp -R ./pwsh-runtime/* $(ARTIFACTS_DIR)

If (!(Select-String -Path $sourcePath/modules/pwsh-runtime.psm1 -Pattern 'private:Get-Handler')) {
   Get-ChildItem -Path $sourcePath/modules/Private -Filter *.ps1 | ForEach-Object {Get-Content $_ | Select-Object -Skip 2 | Out-File -FilePath $sourcePath/modules/pwsh-runtime.psm1 -Append}
   Remove-Item  $sourcePath/modules/Private -Force -Recurse
} else {
   Write-Host "Private modules likely merged already, skipping" -foregroundcolor "green"
}