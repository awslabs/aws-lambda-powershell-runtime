#################
# AWSToolsLayer #
#################
Write-Host "Downloading AWSToolsLayer" -foregroundcolor "green"
Write-Host $PSScriptRoot
$stagePath = Join-Path -Path $PSScriptRoot -ChildPath '\buildlayer\stage'
New-Item -Path $stagePath -ItemType Directory -Force | Out-Null
$modulesPath = Join-Path -Path $PSScriptRoot -ChildPath '\buildlayer\modules'
New-Item -Path $modulesPath -ItemType Directory -Force | Out-Null

Write-Host "Downloading full AWSTools module to stage area:" $stagePath -foregroundcolor "green"
Invoke-WebRequest  -Uri https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip -OutFile $stagePath\AWS.Tools.zip

### Extract entire AWS.Tools modules to stage area but only move over select AWS.Tools modules (AWS.Tools.Common required)
Write-Host "Extracting full AWSTools module to stage area:" $stagePath -foregroundcolor "green"
Expand-Archive $stagePath\AWS.Tools.zip $stagePath -Force

Write-Host "Moving selected AWSTools modules to modules directory:"$modulesPath -foregroundcolor "green"
Move-Item "$stagePath\AWS.Tools.Common" "$modulesPath" -Force
# Move-Item "$stagePathe\AWS.Tools.S3" "$modulesPath" -Force
# Move-Item "$stagePath\AWS.Tools.EventBridge" "$modulesPath" -Force

Write-Host "Deleting AWSTools stage area" -foregroundcolor "green"
Remove-Item $stagePath -Recurse