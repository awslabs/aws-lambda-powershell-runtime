# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This is a simple function handler for testing the PowerShell Lambda Runtime

. ./Get-LambdaContextInfo.ps1

function Invoke-TestFunction {
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
            message = "Hello from PowerShell function handler!"
            input = $LambdaInput

            contextInfo = Get-LambdaContextInfo -LambdaContext $LambdaContext
        } | ConvertTo-Json -Depth 10
    }

    # Return the response
    $response | ConvertTo-Json -Depth 10
}
