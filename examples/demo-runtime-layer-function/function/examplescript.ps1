Write-Verbose "Run script"
Write-Verbose "Importing Modules"
Import-Module "AWS.Tools.Common"
Write-Verbose $LambdaInput
Write-Verbose $LambdaContext
Get-AWSRegion