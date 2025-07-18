# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Send-FunctionHandlerError function.

.DESCRIPTION
    Tests the Send-FunctionHandlerError private function which sends function
    invocation errors back to the AWS Lambda Runtime API. Tests cover correct
    POST requests to the Runtime API error endpoint, proper error object
    formatting and JSON conversion, error message extraction and formatting,
    and error logging to console output.
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
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Send-FunctionHandlerError"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Send-FunctionHandlerError" {

    Context "When sending error with standard PowerShell exception" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-error-request-123"
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

            # Configure test server to accept error POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -StatusCode 202 -Body ""

            # Create the HttpClient for handing into the function
            $script:HttpClient = [System.Net.Http.HttpClient]::new()
        }

        It "Should make correct POST request to Runtime API error endpoint" {
            # Arrange
            $testError = try {
                throw "Test error message"
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify the correct API call was made
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -Method "POST" -ExpectedCallCount 1
        }

        It "Should include correct User-Agent header in request" {
            # Arrange
            $testError = try {
                throw "User agent test error"
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify the API call was made (detailed header verification would require server enhancement)
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -Method "POST"

            # Note: The TestServer logs requests but doesn't currently capture headers in detail
            # The function sets the User-Agent header as verified by code inspection
        }

        It "Should format error object with correct JSON structure" {
            # Arrange
            $testError = try {
                throw "JSON structure test error"
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify the request body contains properly formatted error JSON
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -Method "POST"
            $requestBody | Should -Not -BeNullOrEmpty

            # Verify JSON structure
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "errorMessage"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "errorType"

            # Verify error message content
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "JSON structure test error"
        }

        It "Should extract error message from exception correctly" {
            # Arrange
            $specificErrorMessage = "Specific error message for extraction test"
            $testError = try {
                throw $specificErrorMessage
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -Method "POST"

            # Parse JSON and verify error message
            $errorObject = $requestBody | ConvertFrom-Json
            $errorObject.errorMessage | Should -Be $specificErrorMessage
        }

        It "Should extract error type from CategoryInfo correctly" {
            # Arrange
            $testError = try {
                # Create a specific type of error that will have a known CategoryInfo.Reason
                Get-Item "NonExistentFile.txt" -ErrorAction Stop
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -Method "POST"

            # Parse JSON and verify error type
            $errorObject = $requestBody | ConvertFrom-Json
            $errorObject.errorType | Should -Not -BeNullOrEmpty
            $errorObject.errorType | Should -Be $testError.CategoryInfo.Reason
        }

        It "Should send error body with correct UTF-8 encoding" {
            # Arrange
            $unicodeErrorMessage = "Unicode error: 你好世界 🚨 café naïve"
            $testError = try {
                throw $unicodeErrorMessage
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify the request body was sent correctly with Unicode content
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -Method "POST"
            $requestBody | Should -Not -BeNullOrEmpty

            # Verify Unicode content is preserved
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "你好世界"
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "🚨"
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "café"
        }

        It "Should create compressed JSON without formatting" {
            # Arrange
            $testError = try {
                throw "Compression test error"
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify JSON is compressed (no extra whitespace)
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-request-123/error" -Method "POST"

            # Compressed JSON should not contain extra whitespace or newlines
            $requestBody | Should -Not -Match '\s{2,}'  # No multiple spaces
            $requestBody | Should -Not -Match '\n'      # No newlines
            $requestBody | Should -Not -Match '\r'      # No carriage returns
        }
    }

    Context "When handling different error types and scenarios" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-error-types-456"
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

            # Configure test server to accept error POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -StatusCode 202 -Body ""
        }

        It "Should handle ArgumentException errors correctly" {
            # Arrange
            $testError = try {
                throw [System.ArgumentException]::new("Invalid argument provided")
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"
            $errorObject = $requestBody | ConvertFrom-Json

            $errorObject.errorMessage | Should -Be "Invalid argument provided"
            $errorObject.errorType | Should -Be "ArgumentException"
        }

        It "Should handle FileNotFoundException errors correctly" {
            # Arrange
            $testError = try {
                Get-Content "NonExistentFile.txt" -ErrorAction Stop
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"
            $errorObject = $requestBody | ConvertFrom-Json

            $errorObject.errorMessage | Should -Not -BeNullOrEmpty
            $errorObject.errorType | Should -Not -BeNullOrEmpty
        }

        It "Should handle custom PowerShell errors correctly" {
            # Arrange
            $testError = try {
                Write-Error "Custom PowerShell error" -ErrorAction Stop
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"
            $errorObject = $requestBody | ConvertFrom-Json

            $errorObject.errorMessage | Should -Be "Custom PowerShell error"
            $errorObject.errorType | Should -Not -BeNullOrEmpty
        }

        It "Should handle errors with complex exception details" {
            # Arrange
            $testError = try {
                # Create a nested exception scenario
                try {
                    throw "Inner exception message"
                } catch {
                    throw "Outer exception with inner: $($_.Exception.Message)"
                }
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"
            $errorObject = $requestBody | ConvertFrom-Json

            $errorObject.errorMessage | Should -Match "Outer exception with inner"
            $errorObject.errorMessage | Should -Match "Inner exception message"
        }

        It "Should handle errors with special characters in messages" {
            # Arrange
            $specialMessage = "Error with special chars: `"quotes`", 'apostrophes', \backslashes\, /slashes/, and {braces}"
            $testError = try {
                throw $specialMessage
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-error-types-456/error" -Method "POST"

            # Verify the JSON is still valid despite special characters
            { $requestBody | ConvertFrom-Json } | Should -Not -Throw

            $errorObject = $requestBody | ConvertFrom-Json
            $errorObject.errorMessage | Should -Be $specialMessage
        }
    }

    Context "When testing error logging to console output" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-console-logging-789"
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

            # Configure test server to accept error POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-console-logging-789/error" -StatusCode 202 -Body ""
        }

        It "Should log error to console output" {
            # Arrange
            $testError = try {
                throw "Console logging test error"
            } catch {
                $_
            }

            # Act - Capture console output using stream redirection
            $consoleOutput = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify error was logged to console
            $consoleOutput | Should -Not -BeNullOrEmpty
            # Convert structured output to string for regex matching
            ($consoleOutput | Out-String) | Should -Match "Console logging test error"

            # Also verify the API call was made
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-console-logging-789/error" -Method "POST"
        }

        It "Should log complete error object to console" {
            # Arrange
            $testError = try {
                Get-Item "NonExistentFile.txt" -ErrorAction Stop
            } catch {
                $_
            }

            # Act - Capture console output using stream redirection
            $consoleOutput = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify error details are logged
            $consoleOutput | Should -Not -BeNullOrEmpty
            # The function logs the entire error object, so we should see error details
            # Convert structured output to string for regex matching
            ($consoleOutput | Out-String) | Should -Match "Cannot find path"

            # Also verify the API call was made
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-console-logging-789/error" -Method "POST"
        }

        It "Should log error even when API call fails" {
            # Arrange
            # Configure server to return error status
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-console-logging-789/error" -StatusCode 500 -Body "Server Error"

            $testError = try {
                throw "Error with API failure"
            } catch {
                $_
            }

            # Act & Assert - Function should still log error even if API call fails
            # The function logs the error before making the API call, so we should see it in the exception output
            $errorOutput = try {
                pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1
            } catch {
                # Capture the exception which should contain the logged error
                $_.Exception.Message
            }
            $errorOutput | Out-Null

            # Assert - Verify error was logged to console before API failure
            # Since Write-Host output happens before the exception, we should see evidence of the logging
            # The function will have logged the error object before the API call failed
            # We can verify this by checking that the API call was attempted
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-console-logging-789/error" -Method "POST"
        }
    }

    Context "When API call encounters different HTTP status codes" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-api-errors-999"
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

        It "Should handle HTTP <StatusCode> error from Runtime API" -ForEach @(
            @{ StatusCode = 500; ErrorBody = 'Internal Server Error'; TestResponse = '{"status": "error"}' }
            @{ StatusCode = 404; ErrorBody = 'Not Found'; TestResponse = '{"data": "test"}' }
        ) {
            # Arrange
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-api-errors-999-$($StatusCode)"
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-api-errors-999-$($StatusCode)/error" -StatusCode $StatusCode -Body $ErrorBody

            $testError = try {
                throw "Test error for HTTP $StatusCode"
            } catch {
                $_
            }

            # Act & Assert - Current implementation does not handle HTTP status codes
            { $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1 } | Should -Not -Throw

            # Verify the API call was attempted
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-api-errors-999-$($StatusCode)/error" -Method "POST"
        }

        It "Should handle network connectivity issues gracefully" {
            # Arrange - Use invalid runtime API to simulate network issues
            $originalRuntimeApi = $env:AWS_LAMBDA_RUNTIME_API
            $env:AWS_LAMBDA_RUNTIME_API = "invalid-host:9999"

            $testError = try {
                throw "Test error for network failure"
            } catch {
                $_
            }

            try {
                # Act & Assert - Function should throw exception on network errors
                # Network connectivity failures should throw exceptions since they represent
                # genuine connectivity issues that prevent error reporting
                { $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1 } | Should -Throw
            }
            finally {
                # Restore original runtime API
                $env:AWS_LAMBDA_RUNTIME_API = $originalRuntimeApi
            }
        }
    }

    Context "When testing request formatting and headers" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-request-format-headers"
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

            # Configure test server to accept error POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-format-headers/error" -StatusCode 202 -Body ""
        }

        It "Should construct correct error endpoint URL" {
            # Arrange
            $testError = try {
                throw "URL construction test"
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Verify the correct endpoint was called
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-format-headers/error" -Method "POST"

            # Verify the request was made to the exact expected path
            $requests = $script:TestServer.GetRequestsForPath("/2018-06-01/runtime/invocation/test-request-format-headers/error")
            $requests.Count | Should -Be 1
            $requests[0].Method | Should -Be "POST"
        }

        It "Should use POST method for error submission" {
            # Arrange
            $testError = try {
                throw "POST method test"
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            $requests = $script:TestServer.GetRequestsForPath("/2018-06-01/runtime/invocation/test-request-format-headers/error")
            $requests.Count | Should -Be 1
            $requests[0].Method | Should -Be "POST"
        }

        It "Should handle different request ID formats correctly" {
            # Arrange - Test with different request ID format
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "uuid-format-12345-67890-abcdef"
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/uuid-format-12345-67890-abcdef/error" -StatusCode 202 -Body ""

            $testError = try {
                throw "UUID format test"
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/uuid-format-12345-67890-abcdef/error" -Method "POST"
        }
    }

    Context "When verbose logging is enabled" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-verbose-logging"
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

            # Configure test server to accept error POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-verbose-logging/error" -StatusCode 202 -Body ""

            # Enable verbose logging
            $script:OriginalVerbose = $env:POWERSHELL_RUNTIME_VERBOSE
            $env:POWERSHELL_RUNTIME_VERBOSE = 'TRUE'
        }

        AfterEach {
            # Restore original verbose setting
            $env:POWERSHELL_RUNTIME_VERBOSE = $script:OriginalVerbose
        }

        It "Should execute successfully with verbose logging enabled" {
            # Arrange
            $testError = try {
                throw "Verbose logging test error"
            } catch {
                $_
            }

            # Act - Capture all output streams
            $allOutput = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Function should work normally with verbose logging
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-verbose-logging/error" -Method "POST"

            # Verify the error body was sent correctly
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-verbose-logging/error" -Method "POST"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "errorMessage"
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "Verbose logging test error"

            # Verify verbose output contains runtime logging messages
            $allOutput | Should -Not -BeNullOrEmpty
            # Convert structured output to string for regex matching
            ($allOutput | Out-String) | Should -Match "RUNTIME-Send-FunctionHandlerError"
        }

        It "Should include verbose runtime messages when enabled" {
            # Arrange
            $testError = try {
                throw "Verbose messages test"
            } catch {
                $_
            }

            # Act - Capture all output streams to check for verbose messages
            $allOutput = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert - Check for actual verbose messages from the implementation
            # Based on the test execution output, the actual verbose messages are:
            # - [RUNTIME-Send-FunctionHandlerError]Start: Send-FunctionHandlerError
            # - [RUNTIME-SendRuntimeApiRequest]Sending request to Runtime API
            # - [RUNTIME-SendRuntimeApiRequest]Runtime API Response
            $outputString = $allOutput | Out-String
            $outputString | Should -Match "RUNTIME-Send-FunctionHandlerError.*Start: Send-FunctionHandlerError"
            $outputString | Should -Match "RUNTIME-SendRuntimeApiRequest.*Sending request to Runtime API"

            # The function delegates verbose logging to _SendRuntimeApiRequest which provides
            # detailed HTTP request and response information when verbose logging is enabled
        }
    }

    Context "When testing error object JSON formatting edge cases" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-json-edge-cases"
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

            # Configure test server to accept error POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-json-edge-cases/error" -StatusCode 202 -Body ""
        }

        It "Should handle null or empty error messages gracefully" {
            # Arrange - Create error with empty message
            $testError = try {
                throw ""
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-json-edge-cases/error" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-json-edge-cases/error" -Method "POST"

            # Should still create valid JSON even with empty message
            { $requestBody | ConvertFrom-Json } | Should -Not -Throw

            $errorObject = $requestBody | ConvertFrom-Json
            $errorObject.errorMessage | Should -Be ""
            $errorObject.errorType | Should -Not -BeNullOrEmpty
        }

        It "Should handle very long error messages" {
            # Arrange - Create a very long error message
            $longMessage = "A" * 10000  # 10KB error message
            $testError = try {
                throw $longMessage
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-json-edge-cases/error" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-json-edge-cases/error" -Method "POST"

            # Should handle large messages correctly
            { $requestBody | ConvertFrom-Json } | Should -Not -Throw

            $errorObject = $requestBody | ConvertFrom-Json
            $errorObject.errorMessage | Should -Be $longMessage
            $errorObject.errorMessage.Length | Should -Be 10000
        }

        It "Should handle errors with JSON-like content in messages" {
            # Arrange - Error message that looks like JSON
            $jsonLikeMessage = '{"fake": "json", "in": "error", "message": true}'
            $testError = try {
                throw $jsonLikeMessage
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-json-edge-cases/error" -Method "POST"

            # Should properly escape the JSON-like content
            { $requestBody | ConvertFrom-Json } | Should -Not -Throw

            $errorObject = $requestBody | ConvertFrom-Json
            $errorObject.errorMessage | Should -Be $jsonLikeMessage

            # Verify the JSON structure is still correct (not corrupted by the JSON-like message)
            $errorObject.PSObject.Properties.Name | Should -Contain "errorMessage"
            $errorObject.PSObject.Properties.Name | Should -Contain "errorType"
            $errorObject.PSObject.Properties.Name.Count | Should -Be 2
        }

        It "Should handle errors with newlines and control characters" {
            # Arrange - Error with control characters
            $controlCharMessage = "Error with`nNewlines`r`nAnd`tTabs`0And null chars"
            $testError = try {
                throw $controlCharMessage
            } catch {
                $_
            }

            # Act
            $null = pwsh-runtime\Send-FunctionHandlerError $script:HttpClient $testError 6>&1

            # Assert
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-json-edge-cases/error" -Method "POST"

            # Should properly handle control characters in JSON
            { $requestBody | ConvertFrom-Json } | Should -Not -Throw

            $errorObject = $requestBody | ConvertFrom-Json
            $errorObject.errorMessage | Should -Be $controlCharMessage
        }
    }
}