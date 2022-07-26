#################
# AWSToolsLayer #
#################
Write-Host "Downloading AWSToolsLayer" -foregroundcolor "green"
Write-Host $PSScriptRoot
Invoke-WebRequest  -Uri https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip -OutFile $PSScriptRoot\stage\AWS.Tools.zip

### Extract entire AWS.Tools modules to stage area
#Write-Host 'Extracting full AWSTools module to: '$PSScriptRoot\modules
#Expand-Archive $PSScriptRoot\stage\AWS.Tools.zip $PSScriptRoot\modules

### Extract entire AWS.Tools modules to stage area but only move over select AWS.Tools modules (AWS.Tools.Common required)
Write-Host "Extracting full AWSTools module to stage area:"$PSScriptRoot\stage -foregroundcolor "green"
Expand-Archive $PSScriptRoot\stage\AWS.Tools.zip $PSScriptRoot\stage -Force

Write-Host "Moving selected AWSTools modules to modules directory:"$PSScriptRoot\modules\ -foregroundcolor "green"
If (!(Test-Path "$PSScriptRoot\modules\")) {New-Item -ItemType Directory -Force -Path "$PSScriptRoot\modules\" > $null}
Move-Item "$PSScriptRoot\stage\AWS.Tools.Common" "$PSScriptRoot\modules\" -Force
Move-Item "$PSScriptRoot\stage\AWS.Tools.S3" "$PSScriptRoot\modules\" -Force
Move-Item "$PSScriptRoot\stage\AWS.Tools.EventBridge" "$PSScriptRoot\modules\" -Force

Write-Host "Deleting AWSTools stage area" -foregroundcolor "green"
Remove-Item $PSScriptRoot\stage -Recurse
