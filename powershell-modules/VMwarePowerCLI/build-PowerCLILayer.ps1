#################
# PowerCLILayer #
#################
Write-Host "Downloading PowerCLILayer" -foregroundcolor "green"
Save-Module -Name VMware.PowerCLI -Path $PSScriptRoot\PowerCLI
