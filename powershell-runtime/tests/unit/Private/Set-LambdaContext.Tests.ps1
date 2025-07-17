# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Set-LambdaContext function.

.DESCRIPTION
    Tests the Set-LambdaContext function which creates a Lambda context object with properties
    populated from environment variables. The PowerShellLambdaContext C# class must be pre-loaded
    before calling this function. Covers object creation, property validation, and time-based methods.
#>

param(
    # When true, test against built module instead of source files (default: test source files)
    [switch]$TestBuiltModule = $false
)

BeforeAll {
    # Import test utilities and assertion helpers
    . "$PSScriptRoot/../../helpers/TestUtilities.ps1"
    . "$PSScriptRoot/../../helpers/AssertionHelpers.ps1"
    . "$PSScriptRoot/../../helpers/TestLambdaRuntimeServer.ps1"

    # Initialize test environment
    Initialize-TestEnvironment

    # Load C# class for testing (mimics what bootstrap does)
    if ($TestBuiltModule) {
        $csharpFilePath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "layers/runtimeLayer/PowerShellLambdaContext.cs"
    } else {
        $csharpFilePath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "source/PowerShellLambdaContext.cs"
    }
    Add-Type -TypeDefinition ([System.IO.File]::ReadAllText($csharpFilePath))

    # Import the runtime module using the appropriate mode
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Set-LambdaContext"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Set-LambdaContext" {
    Context "When creating Lambda context object" {
        BeforeEach {
            # Set up valid environment variables for Lambda context
            Set-TestEnvironmentVariables -Variables @{
                'AWS_LAMBDA_FUNCTION_NAME'                = 'test-function'
                'AWS_LAMBDA_FUNCTION_VERSION'             = '1.0'
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = 'arn:aws:lambda:us-east-1:123456789012:function:test-function'
                'AWS_LAMBDA_FUNCTION_MEMORY_SIZE'         = '512'
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'       = 'test-request-id-12345'
                'AWS_LAMBDA_LOG_GROUP_NAME'               = '/aws/lambda/test-function'
                'AWS_LAMBDA_LOG_STREAM_NAME'              = '2023/01/01/[$LATEST]abcdef123456'
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'     = 'test-cognito-identity'
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'       = 'test-client-context'
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS'          = ([DateTimeOffset]::UtcNow.AddMinutes(5).ToUnixTimeMilliseconds()).ToString()
            }
        }

        It "Should create Lambda context object with correct properties" {
            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert - Verify object creation and properties
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [Amazon.Lambda.PowerShell.Internal.LambdaContext]

            $result.FunctionName | Should -Be 'test-function'
            $result.FunctionVersion | Should -Be '1.0'
            $result.MemoryLimitInMB | Should -Be 512
            $result.AwsRequestId | Should -Be 'test-request-id-12345'
            $result.LogGroupName | Should -Be '/aws/lambda/test-function'
            $result.LogStreamName | Should -Be '2023/01/01/[$LATEST]abcdef123456'
            $result.Identity | Should -Be 'test-cognito-identity'
            $result.ClientContext | Should -Be 'test-client-context'
        }

        It "Should populate InvokedFunctionArn property correctly" {
            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert - Note: There's a bug in the C# code where InvokedFunctionArn is set to FunctionName instead of the ARN
            # This test documents the current behavior
            Write-Verbose $result.InvokedFunctionArn -Verbose
            $result.InvokedFunctionArn | Should -Be 'arn:aws:lambda:us-east-1:123456789012:function:test-function'
        }

        It "Should create functional RemainingTime property" {
            # Arrange - Set deadline to 30 seconds from now
            $futureDeadline = [DateTimeOffset]::UtcNow.AddSeconds(30).ToUnixTimeMilliseconds()
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $futureDeadline.ToString()

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert
            $result.RemainingTime | Should -Not -BeNullOrEmpty
            $result.RemainingTime | Should -BeOfType [TimeSpan]
            $result.RemainingTime.TotalSeconds | Should -BeGreaterThan 25
            $result.RemainingTime.TotalSeconds | Should -BeLessThan 35
        }

        It "Should create functional GetRemainingTimeInMillis method" {
            # Arrange - Set deadline to 45 seconds from now
            $futureDeadline = [DateTimeOffset]::UtcNow.AddSeconds(45).ToUnixTimeMilliseconds()
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $futureDeadline.ToString()

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert
            $remainingMs = $result.GetRemainingTimeInMillis()
            $remainingMs | Should -Not -BeNullOrEmpty
            $remainingMs | Should -BeOfType [double]
            $remainingMs | Should -BeGreaterThan 40000  # More than 40 seconds
            $remainingMs | Should -BeLessThan 50000     # Less than 50 seconds
        }

        It "Should handle past deadline correctly" {
            # Arrange - Set deadline to 10 seconds ago
            $pastDeadline = [DateTimeOffset]::UtcNow.AddSeconds(-10).ToUnixTimeMilliseconds()
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $pastDeadline.ToString()

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert - Should return negative values for past deadlines
            $result.RemainingTime.TotalMilliseconds | Should -BeLessThan 0
            $result.GetRemainingTimeInMillis() | Should -BeLessThan 0
        }
    }

    Context "When environment variables have different values" {
        It "Should handle null/empty environment variables gracefully" {
            # Arrange - Set some variables to null/empty
            Set-TestEnvironmentVariables -Variables @{
                'AWS_LAMBDA_FUNCTION_NAME'                = 'test-function'
                'AWS_LAMBDA_FUNCTION_VERSION'             = ''
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = $null
                'AWS_LAMBDA_FUNCTION_MEMORY_SIZE'         = '256'
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'       = 'test-request'
                'AWS_LAMBDA_LOG_GROUP_NAME'               = $null
                'AWS_LAMBDA_LOG_STREAM_NAME'              = ''
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'     = $null
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'       = $null
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS'          = ([DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds()).ToString()
            }

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert - Should handle null/empty values
            $result | Should -Not -BeNullOrEmpty
            $result.FunctionName | Should -Be 'test-function'
            $result.FunctionVersion | Should -Be ''
            $result.LogGroupName | Should -BeNullOrEmpty
            $result.LogStreamName | Should -Be ''
            $result.Identity | Should -BeNullOrEmpty
            $result.ClientContext | Should -BeNullOrEmpty
        }

        It "Should handle different memory sizes correctly" {
            # Arrange
            Set-TestEnvironmentVariables -Variables @{
                'AWS_LAMBDA_FUNCTION_NAME'                = 'memory-test'
                'AWS_LAMBDA_FUNCTION_VERSION'             = '2.0'
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = 'arn:aws:lambda:us-west-2:123456789012:function:memory-test'
                'AWS_LAMBDA_FUNCTION_MEMORY_SIZE'         = '1024'
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'       = 'memory-test-request'
                'AWS_LAMBDA_LOG_GROUP_NAME'               = '/aws/lambda/memory-test'
                'AWS_LAMBDA_LOG_STREAM_NAME'              = '2023/01/01/[$LATEST]memory123'
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'     = 'memory-cognito'
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'       = 'memory-client'
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS'          = ([DateTimeOffset]::UtcNow.AddMinutes(2).ToUnixTimeMilliseconds()).ToString()
            }

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert
            $result.MemoryLimitInMB | Should -Be 1024
            $result.FunctionName | Should -Be 'memory-test'
            $result.FunctionVersion | Should -Be '2.0'
        }

        It "Should handle invalid memory size gracefully" {
            # Arrange - Set invalid memory size
            Set-TestEnvironmentVariables -Variables @{
                'AWS_LAMBDA_FUNCTION_NAME'                = 'invalid-memory-test'
                'AWS_LAMBDA_FUNCTION_VERSION'             = '1.0'
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = 'arn:aws:lambda:us-east-1:123456789012:function:invalid-memory-test'
                'AWS_LAMBDA_FUNCTION_MEMORY_SIZE'         = 'invalid'
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'       = 'invalid-memory-request'
                'AWS_LAMBDA_LOG_GROUP_NAME'               = '/aws/lambda/invalid-memory-test'
                'AWS_LAMBDA_LOG_STREAM_NAME'              = '2023/01/01/[$LATEST]invalid123'
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'     = 'invalid-cognito'
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'       = 'invalid-client'
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS'          = ([DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds()).ToString()
            }

            # Act & Assert - Should throw when trying to convert invalid memory size
            { pwsh-runtime\Set-LambdaContext } | Should -Throw
        }

        It "Should handle invalid deadline gracefully" {
            # Arrange - Set invalid deadline
            Set-TestEnvironmentVariables -Variables @{
                'AWS_LAMBDA_FUNCTION_NAME'                = 'invalid-deadline-test'
                'AWS_LAMBDA_FUNCTION_VERSION'             = '1.0'
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = 'arn:aws:lambda:us-east-1:123456789012:function:invalid-deadline-test'
                'AWS_LAMBDA_FUNCTION_MEMORY_SIZE'         = '512'
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'       = 'invalid-deadline-request'
                'AWS_LAMBDA_LOG_GROUP_NAME'               = '/aws/lambda/invalid-deadline-test'
                'AWS_LAMBDA_LOG_STREAM_NAME'              = '2023/01/01/[$LATEST]invalid456'
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'     = 'invalid-deadline-cognito'
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'       = 'invalid-deadline-client'
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS'          = 'not-a-number'
            }

            # Act & Assert - Should throw when trying to convert invalid deadline
            { pwsh-runtime\Set-LambdaContext } | Should -Throw
        }
    }



    Context "When testing time calculations" {
        BeforeEach {
            # Set up environment variables
            Set-TestEnvironmentVariables -Variables @{
                'AWS_LAMBDA_FUNCTION_NAME'                = 'time-test-function'
                'AWS_LAMBDA_FUNCTION_VERSION'             = '1.0'
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = 'arn:aws:lambda:us-east-1:123456789012:function:time-test-function'
                'AWS_LAMBDA_FUNCTION_MEMORY_SIZE'         = '512'
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'       = 'time-test-request'
                'AWS_LAMBDA_LOG_GROUP_NAME'               = '/aws/lambda/time-test-function'
                'AWS_LAMBDA_LOG_STREAM_NAME'              = '2023/01/01/[$LATEST]timetest'
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'     = 'time-test-cognito'
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'       = 'time-test-client'
            }
        }

        It "Should calculate remaining time accurately for future deadline" {
            # Arrange - Set deadline to exactly 60 seconds from now
            $exactFutureTime = [DateTimeOffset]::UtcNow.AddSeconds(60)
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $exactFutureTime.ToUnixTimeMilliseconds().ToString()

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert - Allow for small timing differences (within 5 seconds)
            $remainingSeconds = $result.RemainingTime.TotalSeconds
            $remainingSeconds | Should -BeGreaterThan 55
            $remainingSeconds | Should -BeLessThan 65

            $remainingMs = $result.GetRemainingTimeInMillis()
            $remainingMs | Should -BeGreaterThan 55000
            $remainingMs | Should -BeLessThan 65000
        }

        It "Should return consistent values between RemainingTime and GetRemainingTimeInMillis" {
            # Arrange
            $futureDeadline = [DateTimeOffset]::UtcNow.AddSeconds(120).ToUnixTimeMilliseconds()
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $futureDeadline.ToString()

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Get both values quickly to minimize timing differences
            $remainingTimeMs = $result.RemainingTime.TotalMilliseconds
            $getRemainingTimeMs = $result.GetRemainingTimeInMillis()

            # Assert - Values should be very close (within 100ms due to timing)
            $difference = [Math]::Abs($remainingTimeMs - $getRemainingTimeMs)
            $difference | Should -BeLessThan 100
        }

        It "Should handle zero deadline correctly" {
            # Arrange - Set deadline to Unix epoch (0)
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = '0'

            # Act
            $result = pwsh-runtime\Set-LambdaContext

            # Assert - Should be a large negative number (current time since epoch)
            $result.RemainingTime.TotalMilliseconds | Should -BeLessThan -1000000000  # Very negative
            $result.GetRemainingTimeInMillis() | Should -BeLessThan -1000000000      # Very negative
        }
    }

    Context "When testing verbose logging" {
        BeforeAll {
            # Store original verbose setting to restore later
            $script:OriginalVerbose = $env:POWERSHELL_RUNTIME_VERBOSE
        }

        AfterAll {
            # Restore original verbose setting
            $env:POWERSHELL_RUNTIME_VERBOSE = $script:OriginalVerbose
        }

        BeforeEach {
            # Set up environment variables with verbose logging enabled
            Set-TestEnvironmentVariables -Variables @{
                'AWS_LAMBDA_FUNCTION_NAME'                = 'verbose-test'
                'AWS_LAMBDA_FUNCTION_VERSION'             = '1.0'
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = 'arn:aws:lambda:us-east-1:123456789012:function:verbose-test'
                'AWS_LAMBDA_FUNCTION_MEMORY_SIZE'         = '512'
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'       = 'verbose-request'
                'AWS_LAMBDA_LOG_GROUP_NAME'               = '/aws/lambda/verbose-test'
                'AWS_LAMBDA_LOG_STREAM_NAME'              = '2023/01/01/[$LATEST]verbose'
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'     = 'verbose-cognito'
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'       = 'verbose-client'
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS'          = ([DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds()).ToString()
                'POWERSHELL_RUNTIME_VERBOSE'              = 'TRUE'
            }
        }

        It "Should execute successfully with verbose logging enabled" {
            # Act - CRITICAL: Use 6>$null to redirect console output when verbose logging is enabled
            $result = pwsh-runtime\Set-LambdaContext 6>$null

            # Assert - Function should work normally with verbose logging
            $result | Should -Not -BeNullOrEmpty
            $result.FunctionName | Should -Be 'verbose-test'
            $result.AwsRequestId | Should -Be 'verbose-request'
            $result.MemoryLimitInMB | Should -Be 512
        }

        It "Should handle different memory sizes with verbose logging" {
            # Arrange - Change memory size
            $env:AWS_LAMBDA_FUNCTION_MEMORY_SIZE = '1024'

            # Act - CRITICAL: Use 6>$null to redirect console output when verbose logging is enabled
            $result = pwsh-runtime\Set-LambdaContext 6>$null

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.MemoryLimitInMB | Should -Be 1024
            $result.FunctionName | Should -Be 'verbose-test'
        }

        It "Should handle time calculations with verbose logging" {
            # Arrange - Set deadline to 30 seconds from now
            $futureDeadline = [DateTimeOffset]::UtcNow.AddSeconds(30).ToUnixTimeMilliseconds()
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $futureDeadline.ToString()

            # Act - CRITICAL: Use 6>$null to redirect console output when verbose logging is enabled
            $result = pwsh-runtime\Set-LambdaContext 6>$null

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.RemainingTime.TotalSeconds | Should -BeGreaterThan 25
            $result.RemainingTime.TotalSeconds | Should -BeLessThan 35
        }

        It "Should handle errors with verbose logging" {
            # Arrange - Set invalid memory size to trigger error
            $env:AWS_LAMBDA_FUNCTION_MEMORY_SIZE = 'invalid'

            # Act & Assert - CRITICAL: Use 6>$null even in error scenarios with verbose logging
            { pwsh-runtime\Set-LambdaContext 6>$null } | Should -Throw
        }

        It "Should handle invalid deadline with verbose logging" {
            # Arrange - Set invalid deadline to trigger error
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = 'not-a-number'

            # Act & Assert - CRITICAL: Use 6>$null even in error scenarios with verbose logging
            { pwsh-runtime\Set-LambdaContext 6>$null } | Should -Throw
        }
    }


}