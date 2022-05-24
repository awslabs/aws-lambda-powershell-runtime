Write-Verbose "Run module init tasks before handler"
Write-Verbose "Importing Modules"
Import-Module "AWS.Tools.Common"

function examplehandler
{
    [cmdletbinding()]
    param(
        [parameter()]
        $InputObject,

        [parameter()]
        $Context
    )
    Write-Verbose "Run handler function from module"
    Get-AWSRegion
}