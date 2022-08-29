$ProgressPreference = 'SilentlyContinue'

#################
# AWSToolsLayer #
#################
Write-Host "Downloading AWSToolsLayer" -foregroundcolor "green"
Write-Host $PSScriptRoot

$stagePath = Join-Path -Path $PSScriptRoot -ChildPath 'stage'
$modulesPath = Join-Path -Path $PSScriptRoot -ChildPath 'modules'

New-Item -Path $stagePath -ItemType Directory -Force | Out-Null
Invoke-WebRequest -Uri https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip -OutFile $stagePath\AWS.Tools.zip

### Extract entire AWS.Tools modules to stage area
#Write-Host "Extracting full AWSTools module to: $modulesPath"
#Expand-Archive -Path $stagePath\AWS.Tools.zip -DestinationPath $modulesPath

### Extract entire AWS.Tools modules to stage area but only move over select AWS.Tools modules (AWS.Tools.Common required)
Write-Host "Extracting full AWSTools module to stage area: $stagePath" -foregroundcolor "green"
Expand-Archive -Path $stagePath\AWS.Tools.zip -DestinationPath $stagePath -Force

Write-Host "Moving selected AWSTools modules to modules directory: $modulesPath" -foregroundcolor "green"
New-Item -ItemType Directory -Force -Path $modulesPath | Out-Null
Move-Item -Path "$stagePath\AWS.Tools.Common" -Destination $modulesPath -Force
# Move-Item -Path "$stagePath\AWS.Tools.S3" -Destination $modulesPath -Force
# Move-Item -Path "$stagePath\AWS.Tools.EventBridge" -Destination $modulesPath -Force

Write-Host "Deleting AWSTools stage area" -foregroundcolor "green"
Remove-Item -Path $stagePath -Recurse
