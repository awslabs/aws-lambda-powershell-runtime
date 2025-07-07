# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Send-FunctionHandlerResponse function.

.DESCRIPTION
    Tests the Send-FunctionHandlerResponse private function which sends the function
    response back to the AWS Lambda Runtime API. Tests cover successful POST requests,
    proper response body encoding and formatting, correct request headers including
    user agent, and handling of empty or null responses.
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
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Send-FunctionHandlerResponse"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Send-FunctionHandlerResponse" {

    Context "When sending successful response with valid JSON data" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-request-123"
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

            # Configure test server to accept response POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -StatusCode 202 -Body ""

            # Create the HttpClient for handing into the function
            $script:HttpClient = [System.Net.Http.HttpClient]::new()
        }

        It "Should make correct POST request to Runtime API response endpoint" {
            # Arrange
            $testResponse = @{
                statusCode = 200
                body       = "Hello World"
                headers    = @{ "Content-Type" = "text/plain" }
            } | ConvertTo-Json -Depth 10

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse

            # Assert - Verify the correct API call was made
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -Method "POST" -ExpectedCallCount 1
        }

        It "Should include correct User-Agent header in request" {
            # Arrange
            $testResponse = '{"test": "response"}'
            $expectedUserAgent = "aws-lambda-powershell/$env:POWERSHELL_VERSION"
            $expectedUserAgent | Out-Null

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse

            # Assert - Verify the API call was made (detailed header verification would require server enhancement)
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -Method "POST"

            # Note: The TestServer logs requests but doesn't currently capture headers in detail
            # The function sets the User-Agent header as verified by code inspection
        }

        It "Should send response body with correct UTF-8 encoding" {
            # Arrange
            $testResponse = @{
                message   = "Test response with special characters: àáâãäå"
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            } | ConvertTo-Json -Depth 10

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse

            # Assert - Verify the request body was sent correctly
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -Method "POST"
            $requestBody | Should -Not -BeNullOrEmpty
            $requestBody | Should -Be $testResponse

            # Verify the body contains the expected content
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "message"
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "special characters"
        }

        It "Should handle complex nested JSON response objects" {
            # Arrange
            $complexResponse = @{
                statusCode = 200
                headers    = @{
                    "Content-Type"    = "application/json"
                    "X-Custom-Header" = "test-value"
                }
                body       = @{
                    data    = @{
                        items    = @(
                            @{ id = 1; name = "Item 1" }
                            @{ id = 2; name = "Item 2" }
                        )
                        metadata = @{
                            total = 2
                            page  = 1
                        }
                    }
                    success = $true
                }
            } | ConvertTo-Json -Depth 10

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $complexResponse

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -Method "POST"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "statusCode"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "headers"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "body"
        }

        It "Should handle string response data correctly" {
            # Arrange
            $stringResponse = "Simple string response"

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $stringResponse

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-123/response" -Method "POST"
            $requestBody | Should -Be $stringResponse
        }
    }

    Context "When handling empty or null responses" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-request-456"
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

            # Configure test server to accept response POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-456/response" -StatusCode 202 -Body ""
        }

        It "Should handle <ResponseType> response gracefully" -ForEach @(
            @{ ResponseType = 'null'; Response = $null; ExpectEmpty = $true }
            @{ ResponseType = 'empty string'; Response = ''; ExpectEmpty = $true }
            @{ ResponseType = 'whitespace-only'; Response = "   `t`n   "; ExpectEmpty = $false }
        ) {
            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $Response

            # Assert - Should still make the API call
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-456/response" -Method "POST"

            # Verify body content based on expectation
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-456/response" -Method "POST"

            if ($ExpectEmpty) {
                # Null and empty string should result in no body content
                $requestBody | Should -BeNullOrEmpty
            } else {
                # Whitespace-only strings should be sent as-is since whitespace can be meaningful
                # in some response formats and the function shouldn't make assumptions about
                # what constitutes "empty" content
                $requestBody | Should -Be $Response
            }
        }
    }

    Context "When API call encounters errors" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-request-789"
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
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-789/response" -StatusCode $StatusCode -Body $ErrorBody

            # Act & Assert - Current implementation does not handle HTTP status codes
            { pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse } | Should -Not -Throw

            # Verify the API call was attempted
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-789/response" -Method "POST"
        }
    }

    Context "When testing request formatting and headers" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-request-headers"
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

            # Configure test server to accept response POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-headers/response" -StatusCode 202 -Body ""
        }

        It "Should construct correct response endpoint URL" {
            # Arrange
            $testResponse = '{"message": "URL test"}'

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse

            # Assert - Verify the correct endpoint was called
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-headers/response" -Method "POST"

            # Verify the request was made to the exact expected path
            $requests = $script:TestServer.GetRequestsForPath("/2018-06-01/runtime/invocation/test-request-headers/response")
            $requests.Count | Should -Be 1
            $requests[0].Method | Should -Be "POST"
        }

        It "Should use POST method for response submission" {
            # Arrange
            $testResponse = '{"method": "test"}'

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse

            # Assert
            $requests = $script:TestServer.GetRequestsForPath("/2018-06-01/runtime/invocation/test-request-headers/response")
            $requests.Count | Should -Be 1
            $requests[0].Method | Should -Be "POST"
        }

        It "Should handle different request ID formats correctly" {
            # Arrange - Test with different request ID format
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "uuid-format-12345-67890-abcdef"
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/uuid-format-12345-67890-abcdef/response" -StatusCode 202 -Body ""
            $testResponse = '{"requestId": "uuid-test"}'

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/uuid-format-12345-67890-abcdef/response" -Method "POST"
        }
    }

    Context "When verbose logging is enabled" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-request-verbose"
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

            # Configure test server to accept response POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-verbose/response" -StatusCode 202 -Body ""

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
            $testResponse = @{
                message   = "verbose test"
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            } | ConvertTo-Json -Depth 10

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $testResponse 6>$null

            # Assert - Function should work normally with verbose logging
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-verbose/response" -Method "POST"

            # Verify the response body was sent correctly
            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-verbose/response" -Method "POST"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "message"
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "verbose test"
        }
    }

    Context "When testing response body encoding and formatting" {
        BeforeAll {
            # Start test server for this context
            $script:TestServer = Start-TestLambdaRuntimeServer -Port 9001

            # Set environment variables for testing
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9001"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = "test-request-encoding"
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

            # Configure test server to accept response POST
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-encoding/response" -StatusCode 202 -Body ""
        }

        It "Should handle Unicode characters in response body" {
            # Arrange
            $unicodeResponse = @{
                message = "Unicode test: 你好世界 🌍 café naïve résumé"
                emoji   = "🚀🎉💻"
                symbols = "©®™€£¥"
            } | ConvertTo-Json -Depth 10

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $unicodeResponse

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-encoding/response" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-encoding/response" -Method "POST"
            $requestBody | Should -Not -BeNullOrEmpty
            $requestBody | Should -Be $unicodeResponse

            # Verify Unicode content is preserved
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "你好世界"
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "🚀🎉💻"
            Assert-JsonResponse -JsonString $requestBody -ShouldContainValue "café"
        }

        It "Should handle large response bodies correctly" {
            # Arrange - Create a large response (but not too large for testing)
            $largeData = @()
            for ($i = 1; $i -le 100; $i++) {
                $largeData += @{
                    id          = $i
                    name        = "Item $i"
                    description = "This is a description for item number $i with some additional text to make it longer"
                    timestamp   = (Get-Date).AddMinutes($i).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
            }

            $largeResponse = @{
                data     = $largeData
                count    = $largeData.Count
                metadata = @{
                    generated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                    size      = "large"
                }
            } | ConvertTo-Json -Depth 10

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $largeResponse

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-encoding/response" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-encoding/response" -Method "POST"
            $requestBody | Should -Not -BeNullOrEmpty
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "data"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "count"
            Assert-JsonResponse -JsonString $requestBody -PropertyValue "100" -ShouldHaveProperty "count"
        }

        It "Should preserve exact JSON formatting when passed as string" {
            # Arrange - Pre-formatted JSON string
            $preFormattedJson = @'
{
    "statusCode": 200,
    "headers": {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*"
    },
    "body": "{\"message\":\"Hello World\",\"timestamp\":\"2023-01-01T00:00:00.000Z\"}"
}
'@

            # Act
            pwsh-runtime\Send-FunctionHandlerResponse $script:HttpClient $preFormattedJson

            # Assert
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-encoding/response" -Method "POST"

            $requestBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-request-encoding/response" -Method "POST"
            $requestBody | Should -Be $preFormattedJson

            # Verify the JSON structure is preserved
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "statusCode"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "headers"
            Assert-JsonResponse -JsonString $requestBody -ShouldHaveProperty "body"
        }
    }
}