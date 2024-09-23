# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function Private:Set-LambdaContext {
    <#
        .SYNOPSIS
            Captures the content of the provided Lambda Context variable.

        .DESCRIPTION
            Captures the content of the provided Lambda Context variable.
    #>

    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Set-LambdaContext]Start: Set-LambdaContext' }

    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Set-LambdaContext]Creating LambdaContext' }
    $private:LambdaContext = [Amazon.Lambda.PowerShell.Internal.LambdaContext]::new(
        $env:AWS_LAMBDA_FUNCTION_NAME,
        $env:AWS_LAMBDA_FUNCTION_VERSION,
        $env:AWS_LAMBDA_RUNTIME_INVOKE_FUNCTION_ARN,
        [int]$env:AWS_LAMBDA_FUNCTION_MEMORY_SIZE,
        $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID,
        $env:AWS_LAMBDA_LOG_GROUP_NAME,
        $env:AWS_LAMBDA_LOG_STREAM_NAME,
        $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY,
        $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT,
        [double]$env:AWS_LAMBDA_RUNTIME_DEADLINE_MS
    )
    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Set-LambdaContext]Return LambdaContext: $(ConvertTo-Json -InputObject $private:LambdaContext -Compress)" }
    return $private:LambdaContext
}
