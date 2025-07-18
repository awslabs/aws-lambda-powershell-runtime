# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Integration tests for PowerShell Lambda Runtime error handling.

.DESCRIPTION
    This file contains integration tests that verify the PowerShell Lambda Runtime
    correctly handles and reports errors from PowerShell execution. These tests focus
    on ensuring PowerShell execution failures are properly reported back from Lambda.

    The tests use a response caching mechanism to minimize Lambda function invocations.
#>

BeforeAll {
    # Import required modules
    Import-Module AWS.Tools.Lambda -ErrorAction Stop
    Import-Module AWS.Tools.CloudWatchLogs -ErrorAction Stop
    Import-Module "$PSScriptRoot/../helpers/LambdaIntegrationHelpers.psm1" -Force -ErrorAction Stop

    # Check if required environment variables are set
    $requiredEnvVars = @(
        'PWSH_TEST_SCRIPTHANDLERFAILINGFUNCTIONNAME',
        'PWSH_TEST_INFRASTRUCTURE_DEPLOYED'
    )

    $missingVars = $requiredEnvVars | Where-Object { -not (Test-Path "env:$_") }
    if ($missingVars.Count -gt 0) {
        throw "Missing required environment variables: $($missingVars -join ', '). Please run Set-IntegrationTestEnvironment.ps1 first."
    }

    # Get AWS authentication parameters from helper function
    $script:awsAuth = Get-AwsAuthParameters

    # Define failing function configuration
    $script:FailingFunctionName = $env:PWSH_TEST_SCRIPTHANDLERFAILINGFUNCTIONNAME

    # Initialize error response cache to minimize Lambda invocations
    Write-Host "Initializing error response cache..."
    $script:ErrorResponseCache = $null

    # Make a single invocation to the failing function and cache the response
    try {
        $payload = New-TestPayload -TestKey "errorTest" -AdditionalData @{ test = "CommandNotFound" }
        $response = Invoke-LMFunction -FunctionName $script:FailingFunctionName -Payload $payload @script:awsAuth

        # Cache both the raw response and the parsed error
        $script:ErrorResponseCache = @{
            RawResponse = $response
            ParsedError = [System.IO.StreamReader]::new($response.Payload).ReadToEnd() | ConvertFrom-Json
        }

        Write-Host "Error response cached successfully."
    }
    catch {
        throw "Failed to cache error response: $_. Tests cannot continue without a cached response."
    }
}

Describe "PowerShell Lambda Runtime Error Handling" {
    Context "PowerShell Execution Failures" {
        It "Should report CommandNotFoundException errors correctly" {
            # Use cached response - no additional Lambda invocation needed
            $errorResponse = $script:ErrorResponseCache.ParsedError
            Write-Verbose "Using cached error response"

            # Validate error response
            $errorResponse | Should -Not -BeNullOrEmpty -Because "Error response should not be null"

            # The error should be in the expected format
            $errorResponse.errorType | Should -Be "CommandNotFoundException" -Because "Error type should match the PowerShell error"
            $errorResponse.errorMessage | Should -Match "Invoke-NonExistentFunction" -Because "Error message should contain the non-existent function name"
            $errorResponse.errorMessage | Should -Match "is not recognized as a name of a cmdlet" -Because "Error message should contain the standard PowerShell error text"

            # Verify the error message matches the expected format
            $expectedErrorPattern = "The term 'Invoke-NonExistentFunction' is not recognized as a name of a cmdlet, function, script file, or executable program."
            $errorResponse.errorMessage | Should -Match $expectedErrorPattern -Because "Error message should match the standard PowerShell CommandNotFoundException format"
        }
    }

    Context "Lambda Error Response Structure" {
        It "Should return error responses with the correct structure" {
            # Use cached response - no additional Lambda invocation needed
            $errorResponse = $script:ErrorResponseCache.ParsedError
            $rawResponse = $script:ErrorResponseCache.RawResponse
            Write-Verbose "Using cached error response"

            # Validate error response structure
            $errorResponse | Should -Not -BeNullOrEmpty -Because "Error response should not be null"

            # Check for required error properties
            $errorResponse.PSObject.Properties.Name | Should -Contain "errorType" -Because "Error response should contain errorType property"
            $errorResponse.PSObject.Properties.Name | Should -Contain "errorMessage" -Because "Error response should contain errorMessage property"

            # Verify the function execution status
            $rawResponse.StatusCode | Should -Be 200 -Because "Lambda invocation should return HTTP 200 even for function errors"
            $rawResponse.FunctionError | Should -Be "Unhandled" -Because "Function error should be marked as Unhandled"
        }
    }

    Context "CloudWatch Logging Integration" {
        It "Should log error details to CloudWatch" {
            # Use cached response to get the request ID and function name
            $errorResponse = $script:ErrorResponseCache.ParsedError
            Write-Verbose "Using cached error response"

            # Validate error response
            $errorResponse | Should -Not -BeNullOrEmpty -Because "Error response should not be null"
            $errorResponse.errorType | Should -Be "CommandNotFoundException" -Because "Error type should match the PowerShell error"

            # Construct the log group name based on the function name
            $cwSplat = @{
                LogGroupName = "/aws/lambda/$($script:FailingFunctionName)"
            }

            # Get the log streams for this function, sorted by last event time (most recent first)
            $logStreams = Get-CWLLogStream @cwSplat @script:awsAuth | Sort-Object -Property LastEventTimestamp -Descending
            $logStreams | Should -Not -BeNullOrEmpty -Because "Function should have log streams"

            # Get the most recent log stream
            $latestLogStream = $logStreams | Select-Object -First 1
            $latestLogStream | Should -Not -BeNullOrEmpty -Because "Function should have a recent log stream"

            # Get the log events from the most recent stream
            $logEvents = Get-CWLLogEvent -LogStreamName $latestLogStream.LogStreamName @cwSplat @script:awsAuth
            $logEvents | Should -Not -BeNullOrEmpty -Because "Log stream should contain events"

            # Extract the log messages
            $logMessages = $logEvents.Events.Message

            # Verify that error details are logged
            $errorTypeLogged = $logMessages | Where-Object { $_ -match "CommandNotFoundException" }
            $errorTypeLogged | Should -Not -BeNullOrEmpty -Because "Error type should be logged to CloudWatch"

            $errorMessageLogged = $logMessages | Where-Object { $_ -match "Invoke-NonExistentFunction" -and $_ -match "is not recognized as a name of a cmdlet" }
            $errorMessageLogged | Should -Not -BeNullOrEmpty -Because "Error message should be logged to CloudWatch"
        }
    }
}