####################
# PwshRuntimeLayer #
####################
$ProgressPreference = 'SilentlyContinue'

Write-Host "Downloading Powershell for PwshRuntimeLayer" -ForegroundColor 'Green'
Write-Host $PSScriptRoot

# PWSH_VERSION is version of PowerShell to use for the runtime
$PWSH_VERSION = "7.2.11"

# PWSH_ARCHITECTURE can be 'x64' or 'arm64'
$PWSH_ARCHITECTURE = "x64"

$sourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'source'

$modulePath = Join-Path -Path $sourcePath -ChildPath 'modules'
$moduleFilePath = Join-Path -Path $modulePath -ChildPath 'pwsh-runtime.psm1'
$privateFunctionPath = Join-Path -Path $modulePath -ChildPath 'Private'

$powershellPath = Join-Path -Path $sourcePath -ChildPath 'powershell'
$tarFile = Join-Path -Path $sourcePath -ChildPath "powershell-$PWSH_VERSION-$PWSH_ARCHITECTURE.tar.gz"

$githubSource = "https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-$PWSH_ARCHITECTURE.tar.gz"
Invoke-WebRequest -Uri $githubSource -OutFile $tarFile

Write-Host "Extracting Powershell $PWSH_VERSION for $PWSH_ARCHITECTURE to $powershellPath" -ForegroundColor 'Green'
if (-not(Test-Path -Path $powershellPath)) {$null = New-Item -ItemType Directory -Force -Path $powershellPath}
tar zxf $tarFile -C $powershellPath

Write-Host "Deleting PowerShell download" -ForegroundColor 'Green'
Remove-Item -Path $tarFile -Force

Write-Host "Copy additional runtime files, including bootstrap. Remove Makefile from destination" -ForegroundColor 'Green'

if (-not(Select-String -Path $moduleFilePath -Pattern 'private:Get-Handler')) {
    Get-ChildItem -Path $privateFunctionPath -Filter '*.ps1' | ForEach-Object {
        Get-Content $_.FullName | Select-Object -Skip 2 | Out-File -FilePath $moduleFilePath -Append -Encoding utf8
    }
    Remove-Item -Path $privateFunctionPath -Force -Recurse
} else {
    Write-Host "Private modules likely merged already, skipping" -ForegroundColor 'Green'
}
