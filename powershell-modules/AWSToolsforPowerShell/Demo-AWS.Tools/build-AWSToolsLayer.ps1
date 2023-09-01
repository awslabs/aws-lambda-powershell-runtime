<#
    .SYNOPSIS
    A script to create a folder to be used as a Lambda layer containing the specified AWS.Tools modules.
#>
param (
    # A list of AWS.Tools modules to embed in the Lambda layer.
    [string[]]$ModuleList = @('AWS.Tools.Common'),

    # The folder path where the layer content should be created.
    [ValidateNotNullOrEmpty()]
    [string]$LayerPath = ([System.IO.Path]::Combine($PSScriptRoot, 'layers', 'modulesLayer')),

    # The URL to the AWS.Tools zip file.
    [string]$AWSToolsSource = 'https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip',

    # The staging path where the AWS Tools for PowerShell will be extracted
    [string]$ModuleStagingPath = ([System.IO.Path]::Combine($PSScriptRoot, 'layers', 'staging')),

    # Can be used to prevent the downloading and expansions of the AWS.Tools source.
    [switch]$SkipZipFileExpansion
)

function Log {
    param (
        [Parameter(Position=0)]
        $Message,
        $ForegroundColor = 'Green'
    )
    Write-Host "AWSToolsLayer: $Message" -ForegroundColor $ForegroundColor
}

$ProgressPreference = 'SilentlyContinue'
Log 'Starting to build the AWS.Tools layer.' -ForegroundColor 'Yellow'

Log "Using the layer path: '$LayerPath'."
Log "Using the staging path: '$ModuleStagingPath'."

if (Test-Path -Path $LayerPath -PathType Container) {
    $null = Remove-Item -Path $LayerPath -Recurse
}

$layerModulePath = Join-Path -Path $LayerPath -ChildPath 'modules'
$LayerPath, $ModuleStagingPath | ForEach-Object {
    $null = New-Item -Path $_ -ItemType Directory -Force
}

if (-not $SkipZipFileExpansion) {
    Log "Downloading the AWS.Tools modules from '$AWSToolsSource'."
    $zipFile = Join-Path -Path $ModuleStagingPath -ChildPath 'AWS.Tools.zip'
    if (Test-Path -Path $AWSToolsSource -PathType Leaf) {
        $zipFile = $AWSToolsSource
    } else {
        Invoke-WebRequest -Uri $AWSToolsSource -OutFile $zipFile
    }

    Log 'Expanding the AWS.Tools zip file to the staging path.'
    Expand-Archive -Path $zipFile -DestinationPath $ModuleStagingPath -ErrorAction SilentlyContinue
}

$ModuleList | ForEach-Object {
    Log "Copying the '$_' module to the layer path."
    $awsModulePath = (Join-Path -Path $ModuleStagingPath -ChildPath $_)
    if (-not(Test-Path -Path $awsModulePath -PathType Container)) {
        throw "Cannot find the module '$_' in the staging path '$ModuleStagingPath'."
    }
    $destinationPath = Join-Path -Path $layerModulePath -ChildPath $_
    $null = New-Item -Path $destinationPath -ItemType Directory
    Copy-Item -Path (Join-Path -Path $awsModulePath -ChildPath '*') -Destination $destinationPath -Recurse -Force
}

Log 'Updating the SAM template ContentUri.'
$samTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath 'template.yml'
(Get-Content -Path $samTemplatePath -Raw).replace(
    'ContentUri: ./buildlayer', 'ContentUri: ./layers/modulesLayer') | Set-Content -Path $samTemplatePath -Encoding ascii

Remove-Item -Path $ModuleStagingPath -Recurse -Force

Log 'Finished building the AWS.Tools layer.' -ForegroundColor 'Yellow'
