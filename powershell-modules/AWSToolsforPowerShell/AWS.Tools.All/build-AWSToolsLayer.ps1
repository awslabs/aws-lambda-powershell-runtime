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

### Extract entire AWS.Tools modules to moduled area
Write-Host 'Extracting full AWSTools module to: '$modulesPath
Expand-Archive $stagePath\AWS.Tools.zip $modulesPath

Write-Host "Deleting AWSTools stage area" -foregroundcolor "green"
Remove-Item $stagePath -Recurse