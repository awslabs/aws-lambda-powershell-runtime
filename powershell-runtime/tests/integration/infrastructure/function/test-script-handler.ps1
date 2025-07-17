# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# This is a simple script handler for testing the PowerShell Lambda Runtime

# $LambdaInput and $LambdaContext are automatically available to the script
param ($LambdaInput, $LambdaContext)

. ./Get-LambdaContextInfo.ps1

# Create a response object
$response = @{
    statusCode = 200
    headers = @{
        "Content-Type" = "application/json"
    }
    body = @{
        message = "Hello from PowerShell script handler!"
        input = $LambdaInput

        contextInfo = Get-LambdaContextInfo -LambdaContext $LambdaContext
    } | ConvertTo-Json -Depth 10
}

# Return the response
$response | ConvertTo-Json -Depth 10
