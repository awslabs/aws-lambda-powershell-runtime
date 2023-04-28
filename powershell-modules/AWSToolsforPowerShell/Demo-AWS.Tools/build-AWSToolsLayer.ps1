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
    [string]$AWSToolsSource = 'https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip'
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

if (Test-Path -Path $LayerPath -PathType Container) {
    $null = Remove-Item -Path $LayerPath -Recurse
}

$stagePath = Join-Path -Path $LayerPath -ChildPath 'staging'
Log "Using the staging path: '$stagePath'."
Log "Using the layer path: '$LayerPath'."
$LayerPath, $stagePath | ForEach-Object {
    $null = New-Item -Path $_ -ItemType Directory -Force
}

Log "Downloading the AWS.Tools modules from '$AWSToolsSource'."
$zipFile = Join-Path -Path $stagePath -ChildPath 'AWS.Tools.zip'
Invoke-WebRequest -Uri $AWSToolsSource -OutFile $zipFile

Log 'Expanding the AWS.Tools zip file to the staging path.'
Expand-Archive -Path $zipFile -DestinationPath $stagePath -Force

$ModuleList | ForEach-Object {
    Log "Moving the '$_' module to the layer path."
    $modulePath = Join-Path -Path $stagePath -ChildPath $_
    if (-not(Test-Path -Path $modulePath -PathType Container)) {
        throw "Cannot find the module '$_' in the staging path '$stagePath'."
    }
    Move-Item -Path $modulePath -Destination $LayerPath -Force
}

Log 'Updating the SAM template ContentUri.'
$samTemplatePath = Join-Path -Path $PSScriptRoot -ChildPath 'template.yml'
(Get-Content -Path $samTemplatePath -Raw).replace(
    'ContentUri: ./buildlayer', 'ContentUri: ./layers/modulesLayer') | Set-Content -Path $samTemplatePath -Encoding utf8

Remove-Item -Path $stagePath -Recurse -Force

Log 'Finished building the AWS.Tools layer.' -ForegroundColor 'Yellow'
