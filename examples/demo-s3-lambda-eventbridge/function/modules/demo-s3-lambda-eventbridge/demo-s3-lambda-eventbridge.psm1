Write-Verbose "Run module init tasks before handler"
Write-Verbose "Importing Modules"
Import-Module "AWS.Tools.Common"
Import-Module "AWS.Tools.S3"
Import-Module "AWS.Tools.EventBridge"

function handler
{
    [cmdletbinding()]
    param(
        [parameter()]
        $LambdaInput,

        [parameter()]
        $LambdaContext
    )
    Write-Host "Getting S3 Object:Bucket Name: $($LambdaInput.Records[0].s3.bucket.name) Bucket key: $($LambdaInput.Records[0].s3.object.key)"
    ($CSVFile = Read-S3Object -BucketName $($LambdaInput.Records[0].s3.bucket.name) -Key $($LambdaInput.Records[0].s3.object.key) -File "/tmp/$($LambdaInput.Records[0].s3.object.key)" | Import-CSV) | Out-Null
    Write-Host "Parsing CSV file and sending to EventBridge Bus $env:DESTINATION_BUS"
    $CSVFile | ForEach-Object {
        $detail = ($_ | ConvertTo-Json).toString()
        $entry = [pscustomobject] @{
            EventBusName = $env:DESTINATION_BUS
            Source = "demo-s3-lambda-eventbridge"
            resources = $($LambdaContext.InvokedFunctionArn)
            DetailType = "size-order"
            Detail = $detail
        }
        Write-EVBEvent -Entry @($entry) | Out-Null
    }
}