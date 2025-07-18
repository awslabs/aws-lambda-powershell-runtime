function Get-LambdaContextInfo {
    param($LambdaContext)

    return @{
        # Core identification properties
        AwsRequestId = $LambdaContext.AwsRequestId
        FunctionName = $LambdaContext.FunctionName
        FunctionVersion = $LambdaContext.FunctionVersion
        InvokedFunctionArn = $LambdaContext.InvokedFunctionArn

        # Resource properties
        MemoryLimitInMB = $LambdaContext.MemoryLimitInMB

        # Logging properties (can be null)
        LogGroupName = $LambdaContext.LogGroupName
        LogStreamName = $LambdaContext.LogStreamName

        # Optional properties (can be null)
        Identity = $LambdaContext.Identity
        ClientContext = $LambdaContext.ClientContext

        # Timing properties - both methods for validation
        RemainingTimeMs = $LambdaContext.RemainingTime.TotalMilliseconds
        RemainingTimeMillisMethod = $LambdaContext.GetRemainingTimeInMillis()
        RemainingTimeSpan = $LambdaContext.RemainingTime.ToString()

        # Basic validation flags
        HasValidRequestId = (-not [string]::IsNullOrEmpty($LambdaContext.AwsRequestId))
        HasValidFunctionName = (-not [string]::IsNullOrEmpty($LambdaContext.FunctionName))
        TimeMethodsConsistent = [Math]::Abs($LambdaContext.RemainingTime.TotalMilliseconds - $LambdaContext.GetRemainingTimeInMillis()) -lt 100
    }
}
