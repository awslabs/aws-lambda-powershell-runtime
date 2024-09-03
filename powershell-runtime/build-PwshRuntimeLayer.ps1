<#
    .SYNOPSIS
    A script to create a folder to be used as the PowerShell Runtime Layer.
#>
param (
    # The version of PowerShell to use for the runtime
    [string]$PwshVersion = '7.4.5',

    # The desired CPU architecture for the runtime
    [ValidateSet('arm64', 'x64')]
    [string]$PwshArchitecture = 'x64',

    [ValidateNotNullOrEmpty()]
    [string]$LayerPath = ([System.IO.Path]::Combine($PSScriptRoot, 'layers', 'runtimeLayer'))
)

function Log {
    param (
        [Parameter(Position=0)]
        $Message,
        $ForegroundColor = 'Green'
    )
    Write-Host "PwshRuntimeLayer: $Message" -ForegroundColor $ForegroundColor
}

$ProgressPreference = 'SilentlyContinue'
Log 'Starting to build the PowerShell Runtime layer.' -ForegroundColor 'Yellow'

$sourcePath = Join-Path -Path $PSScriptRoot -ChildPath 'source'

Log "Using the layer path: '$LayerPath'."

# Copy the source files into the layer path, then change the source path to the layerpath
if (Test-Path -Path $LayerPath) {
    Log 'Cleaning the layer path.'
    $null = Remove-Item -Path $LayerPath -Recurse
}

$null = New-Item -Path $LayerPath -ItemType Directory -Force
Log 'Copying the PwshRuntime source to the layer path.'
Copy-Item -Path (Join-Path -Path $sourcePath -ChildPath '*') -Destination $LayerPath -Recurse

Log "Using the layer path: '$LayerPath'."
$modulePath = Join-Path -Path $LayerPath -ChildPath 'modules'
$moduleFilePath = Join-Path -Path $modulePath -ChildPath 'pwsh-runtime.psm1'
$privateFunctionPath = Join-Path -Path $modulePath -ChildPath 'Private'

$powershellPath = Join-Path -Path $LayerPath -ChildPath 'powershell'
$tarFile = Join-Path -Path $LayerPath -ChildPath "powershell-$PwshVersion-$PwshArchitecture.tar.gz"

$githubSource = "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/powershell-$PwshVersion-linux-$PwshArchitecture.tar.gz"
Log "Downloading the PowerShell runtime from '$githubSource'."
Invoke-WebRequest -Uri $githubSource -OutFile $tarFile

Log "Extracting the PowerShell runtime to '$powershellPath'."
if (-not(Test-Path -Path $powershellPath)) {$null = New-Item -ItemType Directory -Force -Path $powershellPath}
tar zxf $tarFile -C $powershellPath
Remove-Item -Path $tarFile -Force

Log 'Copying additional runtime files, including bootstrap.'
if (-not(Select-String -Path $moduleFilePath -Pattern 'private:Get-Handler')) {
    Get-ChildItem -Path $privateFunctionPath -Filter '*.ps1' | ForEach-Object {
        Get-Content $_.FullName | Select-Object -Skip 2 | Out-File -FilePath $moduleFilePath -Append -Encoding ascii
    }
    Remove-Item -Path $privateFunctionPath -Force -Recurse
} else {
    Log 'Private modules likely merged already, skipping.'
}

Log 'Removing the Makefile from the layer path.'
Remove-Item -Path (Join-Path -Path $LayerPath -ChildPath 'Makefile') -ErrorAction SilentlyContinue

Log 'Updating the SAM template ContentUri.'
$samTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath 'template.yml'
(Get-Content -Path $samTemplatePath -Raw).replace(
    'ContentUri: ./source', 'ContentUri: ./layers/runtimeLayer') | Set-Content -Path $samTemplatePath -Encoding ascii

Log 'Finished building the PowerShell Runtime layer.' -ForegroundColor 'Yellow'
