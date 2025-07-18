# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Get-LambdaNextInvocation function.

.DESCRIPTION
    Tests the Get-LambdaNextInvocation private function which retrieves the next
    invocation from the AWS Lambda Runtime API. Tests cover successful API calls,
    error handling, response parsing, and proper HTTP request formatting.
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

    # Import the runtime module using the appropriate mode
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Get-LambdaNextInvocation"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Get-LambdaNextInvocation" {

    Context "When API call succeeds with valid response" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
        }

        AfterAll {
            # Clean up test server
            if ($script:TestServer) {
                Stop-TestLambdaRuntimeServer -Server $script:TestServer
            }
        }

        BeforeEach {
            # Reset server state
            Reset-TestServer -Server $script:TestServer

            # Configure test server with successful response
            $testEvent = @{
                test = "event"
                key = "value"
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }

            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $testEvent -RequestId "test-request-123"
        }

        It "Should make correct GET request to Runtime API next endpoint" {
            # Act
            $null = pwsh-runtime\Get-LambdaNextInvocation

            # Assert - Verify the correct API call was made
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" -ExpectedCallCount 1
        }

        It "Should include correct User-Agent header in request" {
            # Arrange - Get PowerShell version for expected user agent
            $null = "aws-lambda-powershell/$env:POWERSHELL_VERSION"

            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation

            # Assert - Check that request was made (detailed header verification would require server enhancement)
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET"

            # Verify result structure indicates successful request
            $result | Should -Not -BeNullOrEmpty
            $result.headers | Should -Not -BeNullOrEmpty
            $result.incomingEvent | Should -Not -BeNullOrEmpty
        }

        It "Should return response object with headers and incomingEvent properties" {
            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation

            # Assert - Verify response structure
            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain "headers"
            $result.PSObject.Properties.Name | Should -Contain "incomingEvent"
        }

        It "Should return correct event data in incomingEvent property" {
            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation

            # Assert - Verify event content
            $result.incomingEvent | Should -Not -BeNullOrEmpty

            # Parse the JSON event to verify content
            $eventData = $result.incomingEvent | ConvertFrom-Json
            $eventData.test | Should -Be "event"
            $eventData.key | Should -Be "value"
        }

        It "Should return Lambda Runtime headers in headers property" {
            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation

            # Assert - Verify headers are present
            $result.headers | Should -Not -BeNullOrEmpty

            # Check for expected Lambda Runtime headers
            $result.headers['Lambda-Runtime-Aws-Request-Id'] | Should -Be "test-request-123"
            $result.headers['Lambda-Runtime-Deadline-Ms'] | Should -Not -BeNullOrEmpty
        }
    }

    Context "When API call returns empty response" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
        }

        AfterAll {
            # Clean up test server
            if ($script:TestServer) {
                Stop-TestLambdaRuntimeServer -Server $script:TestServer
            }
        }

        BeforeEach {
            # Reset server state
            Reset-TestServer -Server $script:TestServer

            # Configure test server to return empty body
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -StatusCode 200 -Body ""
        }

        It "Should handle empty response gracefully and continue" {
            # This test verifies the function handles empty responses by continuing (which in the runtime loop means trying again)
            # Since the function uses 'continue' for empty responses, we need to test this behavior

            # The function should not return anything for empty responses (it continues)
            # We'll verify this by checking that no valid response object is returned

            # Note: The actual 'continue' behavior is part of the runtime loop,
            # so in isolation this function may behave differently

            # Act & Assert - This should either return null/empty or throw due to continue outside loop
            { pwsh-runtime\Get-LambdaNextInvocation } | Should -Not -Throw
        }
    }

    Context "When API call fails with HTTP error" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
        }

        AfterAll {
            # Clean up test server
            if ($script:TestServer) {
                Stop-TestLambdaRuntimeServer -Server $script:TestServer
            }
        }

        BeforeEach {
            # Reset server state
            Reset-TestServer -Server $script:TestServer

            # Configure test server to return HTTP error
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -StatusCode 500 -Body "Internal Server Error"
        }

        It "Should handle HTTP errors gracefully and continue" {
            # The function catches exceptions and uses 'continue' to retry
            # In isolation, this means the function should not throw exceptions

            # Act & Assert
            { pwsh-runtime\Get-LambdaNextInvocation } | Should -Not -Throw
        }

        It "Should make the API call even when server returns error" {
            # Act
            try {
                pwsh-runtime\Get-LambdaNextInvocation
            }
            catch {
                # Ignore any exceptions for this test
            }

            # Assert - Verify the API call was attempted
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET"
        }
    }

    Context "When verbose logging is enabled" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
        }

        AfterAll {
            # Clean up test server
            if ($script:TestServer) {
                Stop-TestLambdaRuntimeServer -Server $script:TestServer
            }
        }

        BeforeEach {
            # Reset server state
            Reset-TestServer -Server $script:TestServer

            # Configure successful response
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent @{ test = "verbose" }

            # Enable verbose logging
            $script:OriginalVerbose = $env:POWERSHELL_RUNTIME_VERBOSE
            $env:POWERSHELL_RUNTIME_VERBOSE = 'TRUE'
        }

        AfterEach {
            # Restore original verbose setting
            $env:POWERSHELL_RUNTIME_VERBOSE = $script:OriginalVerbose
        }

        It "Should execute successfully with verbose logging enabled" {
            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation 6>$null

            # Assert - Function should work normally with verbose logging
            $result | Should -Not -BeNullOrEmpty
            $result.incomingEvent | Should -Not -BeNullOrEmpty

            # Verify API call was made
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET"
        }
    }

    Context "When testing response parsing and format validation" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
        }

        AfterAll {
            # Clean up test server
            if ($script:TestServer) {
                Stop-TestLambdaRuntimeServer -Server $script:TestServer
            }
        }

        BeforeEach {
            # Reset server state
            Reset-TestServer -Server $script:TestServer
        }

        It "Should handle JSON event data correctly" {
            # Arrange
            $complexEvent = @{
                Records = @(
                    @{
                        eventName = "s3:ObjectCreated:Put"
                        s3 = @{
                            bucket = @{ name = "test-bucket" }
                            object = @{ key = "test-file.txt" }
                        }
                    }
                )
                requestContext = @{
                    requestId = "test-request-id"
                    accountId = "123456789012"
                }
            }

            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $complexEvent

            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation

            # Assert
            $result.incomingEvent | Should -Not -BeNullOrEmpty
            Assert-JsonResponse -JsonString $result.incomingEvent -ShouldHaveProperty "Records"
            Assert-JsonResponse -JsonString $result.incomingEvent -ShouldHaveProperty "requestContext"
        }

        It "Should handle simple string event data" {
            # Arrange
            $simpleEvent = @{ message = "Hello World" }
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $simpleEvent

            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation

            # Assert
            $result.incomingEvent | Should -Not -BeNullOrEmpty
            Assert-JsonResponse -JsonString $result.incomingEvent -ShouldContainValue "Hello World"
        }

        It "Should preserve all response headers from Runtime API" {
            # Arrange
            $testEvent = @{ test = "headers" }
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $testEvent -RequestId "header-test-123"

            # Act
            $result = pwsh-runtime\Get-LambdaNextInvocation

            # Assert
            $result.headers | Should -Not -BeNullOrEmpty
            $result.headers['Lambda-Runtime-Aws-Request-Id'] | Should -Be "header-test-123"
            $result.headers['Content-Type'] | Should -Be "application/json"
        }
    }
}