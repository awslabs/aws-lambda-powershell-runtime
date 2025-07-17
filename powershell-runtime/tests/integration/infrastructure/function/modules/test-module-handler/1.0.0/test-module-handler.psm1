# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This is a simple module handler for testing the PowerShell Lambda Runtime

. "$env:LAMBDA_TASK_ROOT/Get-LambdaContextInfo.ps1"

function Invoke-TestModuleHandler {
    param(
        $LambdaInput,
        $LambdaContext
    )

    # Create a response object
    $response = @{
        statusCode = 200
        headers = @{
            "Content-Type" = "application/json"
        }
        body = @{
            message = "Hello from PowerShell module handler!"
            input = $LambdaInput

            contextInfo = Get-LambdaContextInfo -LambdaContext $LambdaContext
        } | ConvertTo-Json -Depth 10
    }

    # Return the response
    $response | ConvertTo-Json -Depth 10
}
