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
    [string]$LayerPath = ([System.IO.Path]::Combine($PSScriptRoot, 'layers', 'runtimeLayer')),

    # Skip downloading PowerShell runtime (useful for unit testing)
    [switch]$SkipRuntimeSetup
)

function Log {
    param (
        [Parameter(Position = 0)]
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

if (-not $SkipRuntimeSetup) {
    $powershellPath = Join-Path -Path $LayerPath -ChildPath 'powershell'
    $tarFile = Join-Path -Path $LayerPath -ChildPath "powershell-$PwshVersion-$PwshArchitecture.tar.gz"

    $githubSource = "https://github.com/PowerShell/PowerShell/releases/download/v$PwshVersion/powershell-$PwshVersion-linux-$PwshArchitecture.tar.gz"
    Log "Downloading the PowerShell runtime from '$githubSource'."
    Invoke-WebRequest -Uri $githubSource -OutFile $tarFile

    Log "Extracting the PowerShell runtime to '$powershellPath'."
    if (-not(Test-Path -Path $powershellPath)) { $null = New-Item -ItemType Directory -Force -Path $powershellPath }
    tar zxf $tarFile -C $powershellPath
    Remove-Item -Path $tarFile -Force
}
else {
    Log 'Skipping PowerShell runtime download (SkipRuntimeSetup specified).' -ForegroundColor 'Cyan'
}

Log 'Merging private functions into the module.'

# Always perform the merge operation - get the base module content
$moduleContent = Get-Content -Path $moduleFilePath -Raw

# Remove development-only code from the base module
$exclusionMarker = '##### All code below this comment is excluded from the build process'
$markerIndex = $moduleContent.IndexOf($exclusionMarker)
if ($markerIndex -ge 0) {
    $cleanedContent = $moduleContent.Substring(0, $markerIndex).TrimEnd()
    Log 'Removed development-only code from base module.'
}
else {
    $cleanedContent = $moduleContent
    Log 'Build exclusion marker not found - using full module content.' -ForegroundColor 'Yellow'
}

# Collect all private function content
$privateFunctionContent = @()
$privateFunctionContent += "`n# Private functions merged from Private directory during build process"

Get-ChildItem -Path $privateFunctionPath -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
    Log "Merging private function: $($_.Name)"
    $functionContent = Get-Content $_.FullName | Select-Object -Skip 2  # Skip copyright header
    $privateFunctionContent += "`n# === $($_.Name) ==="
    $privateFunctionContent += $functionContent
    $privateFunctionContent += ""  # Add blank line between functions
}

# Combine base module content with private functions
$finalContent = $cleanedContent + "`n" + ($privateFunctionContent -join "`n")

# Write the merged content to the module file
Set-Content -Path $moduleFilePath -Value $finalContent -Encoding ascii

# Remove the Private directory since functions are now merged
Remove-Item -Path $privateFunctionPath -Force -Recurse
Log 'Successfully merged all private functions into the module.'

Log 'Removing the Makefile from the layer path.'
Remove-Item -Path (Join-Path -Path $LayerPath -ChildPath 'Makefile') -ErrorAction SilentlyContinue

if (-not $SkipRuntimeSetup) {
    Log 'Updating the SAM template ContentUri.'
    $samTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath 'template.yml'
    (Get-Content -Path $samTemplatePath -Raw).replace(
        'ContentUri: ./source', 'ContentUri: ./layers/runtimeLayer') | Set-Content -Path $samTemplatePath -Encoding ascii
}
else {
    Log 'Skipping SAM template update (SkipRuntimeSetup specified).' -ForegroundColor 'Cyan'
}

Log 'Finished building the PowerShell Runtime layer.' -ForegroundColor 'Yellow'
