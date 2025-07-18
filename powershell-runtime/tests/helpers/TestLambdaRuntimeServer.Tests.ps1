# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for TestLambdaRuntimeServer.ps1 functionality.

.DESCRIPTION
    Validates that the TestLambdaRuntimeServer works correctly for Lambda runtime testing needs.
    Tests all core functionality required by the unit testing framework.
#>

BeforeAll {
    # Dot-source the TestLambdaRuntimeServer script
    . "$PSScriptRoot/TestLambdaRuntimeServer.ps1"
}

Describe "TestLambdaRuntimeServer Core Functionality" {
    BeforeAll {
        $port = 8888
        $script:TestServer = Start-TestLambdaRuntimeServer -Port $port
        $script:TestEndpointUrl = "http://localhost:$($port)"
    }
    BeforeEach {
        # $port = 8888
        # $script:TestServer = Start-TestLambdaRuntimeServer -Port $port
        # $script:TestEndpointUrl = "http://localhost:$($port)"
        Reset-TestServer -Server $script:TestServer
    }

    AfterEach {
        #Stop-TestLambdaRuntimeServer -Server $script:TestServer
        Reset-TestServer -Server $script:TestServer
    }

    AfterAll {
        if ($script:TestServer) {
            Stop-TestLambdaRuntimeServer -Server $script:TestServer
        }
    }

    Context "Server Initialization and Properties" {
        It "Should initialize with correct default properties" {
            $server = Start-TestLambdaRuntimeServer -Port 9999 -MockOnly
            $server.Port | Should -Be 9999
            $server.BaseUrl | Should -Be "http://localhost:9999/"
            $server.IsRunning | Should -Be $false
            $server.RequestCount | Should -Be 0
            $server.Responses.Count | Should -BeGreaterThan 0  # Should have default responses
            $server.Stop()
            Remove-Variable -Name server
        }

        It "Should start and stop correctly" {
            $server = Start-TestLambdaRuntimeServer -Port 9999 -MockOnly
            $server.IsRunning | Should -Be $false

            $server.Start()
            Start-Sleep -Milliseconds 200
            $server.IsRunning | Should -Be $true

            $server.Stop()
            $server.IsRunning | Should -Be $false
        }

        It "Should setup default Lambda Runtime API responses" {
            $server = Start-TestLambdaRuntimeServer -Port 9999 -MockOnly

            # Check default responses exist
            $server.Responses.ContainsKey('/2018-06-01/runtime/invocation/next') | Should -Be $true
            $server.Responses.ContainsKey('/2018-06-01/runtime/invocation/*/response') | Should -Be $true
            $server.Responses.ContainsKey('/2018-06-01/runtime/invocation/*/error') | Should -Be $true

            # Verify default response structure
            $nextResponse = $server.Responses['/2018-06-01/runtime/invocation/next']
            $nextResponse.StatusCode | Should -Be 200
            $nextResponse.Headers['Lambda-Runtime-Aws-Request-Id'] | Should -Not -BeNullOrEmpty
            $nextResponse.Headers['Lambda-Runtime-Deadline-Ms'] | Should -Not -BeNullOrEmpty
            $nextResponse.Body | Should -Not -BeNullOrEmpty
        }
    }

    Context "HTTP Request Processing" {
        It "Should handle GET requests to Lambda Runtime API" {
            $response = Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3
            $response | Should -Not -BeNullOrEmpty
            $response.test | Should -Be "event"
            $response.key | Should -Be "value"
        }

        It "Should handle POST requests with body" {
            $testData = @{ response = "test-response" } | ConvertTo-Json -Depth 5

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/test-123/response" -Method POST -Body $testData -ContentType "application/json" -TimeoutSec 3
            }
            catch {
                # Expected - server returns 202 but Invoke-RestMethod might not handle empty response well
            }

            # Verify request was processed (should be logged)
            $script:TestServer.GetRequestCount() | Should -BeGreaterThan 0
        }

        It "Should return 404 for unknown endpoints" {
            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/unknown/endpoint" -Method GET -TimeoutSec 3
                throw "Should have thrown an exception"
            }
            catch {
                $_.Exception.Message | Should -Match "404"
            }
        }

        It "Should handle wildcard path matching" {
            # Test that wildcard patterns work for response and error endpoints
            $testData = "test response"

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/abc123/response" -Method POST -Body $testData -ContentType "application/json" -TimeoutSec 3
            }
            catch {
                # Expected - 202 response
            }

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/def456/error" -Method POST -Body $testData -ContentType "application/json" -TimeoutSec 3
            }
            catch {
                # Expected - 202 response
            }

            # Verify both requests were logged
            $script:TestServer.GetRequestCount() | Should -BeGreaterOrEqual 2
        }
    }

    Context "Request Logging and Verification" {
        It "Should log all incoming requests" {
            # Make multiple requests
            Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/test/response" -Method POST -Body "test" -TimeoutSec 3
            } catch { }

            # Verify logging
            $script:TestServer.GetRequestCount() | Should -Be 2
            $requests = $script:TestServer.GetRequestLog()
            $requests.Count | Should -Be 2

            # Verify request details
            $getRequest = $requests | Where-Object { $_.Method -eq 'GET' }
            $getRequest.Path | Should -Be '/2018-06-01/runtime/invocation/next'
            $getRequest.Timestamp | Should -Not -BeNullOrEmpty

            $postRequest = $requests | Where-Object { $_.Method -eq 'POST' }
            $postRequest.Path | Should -Be '/2018-06-01/runtime/invocation/test/response'
            $postRequest.Body | Should -Be 'test'
        }

        It "Should support path-specific request queries" {
            # Make requests to different paths
            Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue
            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/test/response" -Method POST -Body "test" -TimeoutSec 3
            } catch { }

            # Test path-specific queries
            $script:TestServer.GetRequestCount('/2018-06-01/runtime/invocation/next') | Should -Be 1
            $script:TestServer.GetRequestCount('/2018-06-01/runtime/invocation/test/response') | Should -Be 1
            $script:TestServer.GetRequestCount('/nonexistent') | Should -Be 0

            # Test GetRequestsForPath
            $nextRequests = $script:TestServer.GetRequestsForPath('/2018-06-01/runtime/invocation/next')
            $nextRequests.Count | Should -Be 1
            $nextRequests[0].Method | Should -Be 'GET'
        }

        It "Should clear request log when requested" {
            # Make a request
            Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue
            $script:TestServer.GetRequestCount() | Should -BeGreaterThan 0

            # Clear log
            $script:TestServer.ClearRequestLog()
            $script:TestServer.GetRequestCount() | Should -Be 0
            $script:TestServer.GetRequestLog().Count | Should -Be 0
        }
    }

    Context "Response Configuration" {
        It "Should support string response configuration (backward compatibility)" {
            $script:TestServer.SetResponse('/test/string', 'simple string response')

            $response = Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/test/string" -Method GET -TimeoutSec 3
            $response | Should -Be 'simple string response'
        }

        It "Should support rich response configuration with status codes and headers" {
            $customHeaders = @{
                'X-Custom-Header' = 'custom-value'
                'Content-Type' = 'application/custom'
            }

            $script:TestServer.SetResponse('/test/rich', @{
                StatusCode = 201
                Headers = $customHeaders
                Body = '{"custom": "response"}'
            })

            # Use WebRequest to check headers
            $webRequest = [System.Net.WebRequest]::Create("$($script:TestEndpointUrl)/test/rich")
            $webRequest.Method = "GET"
            $response = $webRequest.GetResponse()

            $response.StatusCode | Should -Be 'Created'  # 201
            $response.Headers['X-Custom-Header'] | Should -Be 'custom-value'

            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $body = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()

            $bodyObj = $body | ConvertFrom-Json
            $bodyObj.custom | Should -Be 'response'
        }

        It "Should support error response configuration" {
            $script:TestServer.SetResponse('/test/error', @{
                StatusCode = 500
                Body = 'Internal Server Error'
            })

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/test/error" -Method GET -TimeoutSec 3
                throw "Should have thrown an exception"
            }
            catch {
                $_.Exception.Message | Should -Match "500"
            }
        }

        It "Should find response configurations with wildcard matching" {
            $script:TestServer.SetResponse('/api/*/test', @{
                StatusCode = 200
                Body = 'wildcard match'
            })

            # Test FindResponseConfig method directly
            $config = $script:TestServer.FindResponseConfig('/api/v1/test')
            $config | Should -Not -BeNull
            $config.StatusCode | Should -Be 200
            $config.Body | Should -Be 'wildcard match'

            # Test actual HTTP request
            $response = Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/api/v1/test" -Method GET -TimeoutSec 3
            $response | Should -Be 'wildcard match'
        }
    }

    Context "Lambda Event Configuration" {
        It "Should configure Lambda events with custom request ID" {
            $testEvent = @{
                eventType = "test"
                data = @{
                    key = "value"
                    nested = @{
                        property = "nested-value"
                    }
                }
            }
            $customRequestId = "custom-request-12345"

            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $testEvent -RequestId $customRequestId

            # Verify the event is returned correctly
            $response = Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3
            $response.eventType | Should -Be "test"
            $response.data.key | Should -Be "value"
            $response.data.nested.property | Should -Be "nested-value"

            # Verify headers are set correctly
            $webRequest = [System.Net.WebRequest]::Create("$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next")
            $webRequest.Method = "GET"
            $httpResponse = $webRequest.GetResponse()

            $httpResponse.Headers['Lambda-Runtime-Aws-Request-Id'] | Should -Be $customRequestId
            $httpResponse.Headers['Lambda-Runtime-Deadline-Ms'] | Should -Not -BeNullOrEmpty
            $httpResponse.Headers['Content-Type'] | Should -Be 'application/json'

            $httpResponse.Close()
        }

        It "Should generate default request ID when not provided" {
            $testEvent = @{ test = "event" }

            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $testEvent

            # Verify headers are set with generated request ID
            $webRequest = [System.Net.WebRequest]::Create("$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next")
            $webRequest.Method = "GET"
            $httpResponse = $webRequest.GetResponse()

            $requestId = $httpResponse.Headers['Lambda-Runtime-Aws-Request-Id']
            $requestId | Should -Not -BeNullOrEmpty
            $requestId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'  # GUID format

            $httpResponse.Close()
        }
    }

    Context "Server Reset Functionality" {
        It "Should reset all server state correctly" {
            # Make some requests and configure custom responses
            Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue
            $script:TestServer.SetResponse('/custom/endpoint', @{
                StatusCode = 201
                Body = 'custom response'
            })

            # Verify state exists
            $script:TestServer.GetRequestCount() | Should -BeGreaterThan 0
            $script:TestServer.Responses.ContainsKey('/custom/endpoint') | Should -Be $true

            # Reset server
            Reset-TestServer -Server $script:TestServer

            # Verify state was cleared
            $script:TestServer.GetRequestCount() | Should -Be 0
            $script:TestServer.GetRequestLog().Count | Should -Be 0

            # Verify custom responses were cleared but defaults restored
            $script:TestServer.Responses.ContainsKey('/custom/endpoint') | Should -Be $false
            $script:TestServer.Responses.ContainsKey('/2018-06-01/runtime/invocation/next') | Should -Be $true

            # Verify default responses still work
            $response = Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue
            $response | Should -Not -BeNullOrEmpty
        }
    }

    Context "Helper Functions for Test Compatibility" {
        It "Should support Assert-TestServerRequest function" {
            # Make a request
            Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Should not throw for existing request
            { Assert-TestServerRequest -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" } | Should -Not -Throw

            # Should throw for non-existent request
            { Assert-TestServerRequest -Server $script:TestServer -Path "/nonexistent" -Method "GET" } | Should -Throw
        }

        It "Should support Get-TestServerRequestBody function" {
            $testData = @{ response = "test-response" } | ConvertTo-Json -Depth 5

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/test-123/response" -Method POST -Body $testData -ContentType "application/json" -TimeoutSec 3
            }
            catch {
                # Expected - server returns 202
            }

            $capturedBody = Get-TestServerRequestBody -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-123/response" -Method "POST"
            $capturedBody | Should -Be $testData
        }

        It "Should support Set-TestServerResponse function" {
            $customHeaders = @{ 'X-Test-Header' = 'test-value' }

            Set-TestServerResponse -Server $script:TestServer -Path "/test/helper" -StatusCode 201 -Body "helper response" -Headers $customHeaders

            # Verify response was set correctly
            $webRequest = [System.Net.WebRequest]::Create("$($script:TestEndpointUrl)/test/helper")
            $webRequest.Method = "GET"
            $response = $webRequest.GetResponse()

            $response.StatusCode | Should -Be 'Created'  # 201
            $response.Headers['X-Test-Header'] | Should -Be 'test-value'

            $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
            $body = $reader.ReadToEnd()
            $reader.Close()
            $response.Close()

            $body | Should -Be "helper response"
        }
    }

    Context "Additional Tests for Get-LambdaNextInvocation Support" {
        It "Should support Assert-ApiCall pattern used in Get-LambdaNextInvocation tests" {
            # Make a request
            Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Test the pattern used in Get-LambdaNextInvocation.Tests.ps1
            $requests = $script:TestServer.GetRequestsForPath('/2018-06-01/runtime/invocation/next')
            $getRequests = $requests | Where-Object { $_.Method -eq 'GET' }

            $getRequests.Count | Should -Be 1
            $getRequests[0].Method | Should -Be 'GET'
            $getRequests[0].Path | Should -Be '/2018-06-01/runtime/invocation/next'
        }

        It "Should support User-Agent header capture for Get-LambdaNextInvocation tests" {
            # Make request with custom User-Agent
            $headers = @{ 'User-Agent' = 'aws-lambda-powershell/test-version' }

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -Headers $headers -TimeoutSec 3 -ErrorAction SilentlyContinue
            } catch {
                # May fail but request should be logged
            }

            # Verify request was captured
            $requests = $script:TestServer.GetRequestsForPath('/2018-06-01/runtime/invocation/next')
            $requests.Count | Should -BeGreaterThan 0
        }

        It "Should handle complex nested Lambda events like Get-LambdaNextInvocation tests" {
            $complexEvent = @{
                Records = @(
                    @{
                        eventName = "s3:ObjectCreated:Put"
                        eventVersion = "2.1"
                        eventSource = "aws:s3"
                        s3 = @{
                            bucket = @{
                                name = "complex-test-bucket"
                                arn = "arn:aws:s3:::complex-test-bucket"
                            }
                            object = @{
                                key = "complex/nested/file.txt"
                                size = 2048
                                eTag = "complex-etag"
                            }
                        }
                        requestParameters = @{
                            sourceIPAddress = "192.168.1.100"
                        }
                    }
                )
                requestContext = @{
                    requestId = "complex-request-id"
                    accountId = "123456789012"
                }
            }

            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $complexEvent -RequestId "complex-test-789"

            # Verify the complex event is returned correctly
            $response = Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3

            $response.Records.Count | Should -Be 1
            $response.Records[0].eventName | Should -Be "s3:ObjectCreated:Put"
            $response.Records[0].s3.bucket.name | Should -Be "complex-test-bucket"
            $response.Records[0].s3.object.key | Should -Be "complex/nested/file.txt"
            $response.requestContext.requestId | Should -Be "complex-request-id"
        }

        It "Should validate all required Lambda Runtime API headers" {
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent @{ test = "headers" } -RequestId "header-validation-123"

            # Use WebRequest to check headers
            $webRequest = [System.Net.WebRequest]::Create("$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next")
            $webRequest.Method = "GET"
            $response = $webRequest.GetResponse()

            # Validate all required headers are present
            $response.Headers['Lambda-Runtime-Aws-Request-Id'] | Should -Be "header-validation-123"
            $response.Headers['Lambda-Runtime-Deadline-Ms'] | Should -Not -BeNullOrEmpty
            $response.Headers['Content-Type'] | Should -Be 'application/json'

            # Validate deadline format (should be a timestamp)
            $deadline = $response.Headers['Lambda-Runtime-Deadline-Ms']
            { [long]$deadline } | Should -Not -Throw
            [long]$deadline | Should -BeGreaterThan 0

            $response.Close()
        }

        It "Should handle empty response body scenarios" {
            # Configure server to return empty body
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -StatusCode 200 -Body ""

            # Request should succeed but return empty content
            $response = Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Response should be empty or null
            if ($response) {
                $response | Should -Be ""
            } else {
                $response | Should -BeNullOrEmpty
            }
        }

        It "Should capture request bodies for different content types and sizes" {
            # Test small JSON body
            $smallJson = '{"test": "small"}'
            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/test-small/response" -Method POST -Body $smallJson -ContentType "application/json" -TimeoutSec 3
            } catch { }

            # Test larger JSON body
            $largeData = @{}
            for ($i = 1; $i -le 100; $i++) {
                $largeData["key$i"] = "value$i with some additional text to make it larger"
            }
            $largeJson = $largeData | ConvertTo-Json -Depth 5

            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/test-large/response" -Method POST -Body $largeJson -ContentType "application/json" -TimeoutSec 3
            } catch { }

            # Test plain text body
            $textBody = "This is a plain text response body for testing"
            try {
                Invoke-RestMethod -Uri "$($script:TestEndpointUrl)/2018-06-01/runtime/invocation/test-text/response" -Method POST -Body $textBody -ContentType "text/plain" -TimeoutSec 3
            } catch { }

            # Verify all bodies were captured correctly
            $smallRequest = $script:TestServer.GetRequestsForPath('/2018-06-01/runtime/invocation/test-small/response')[0]
            $smallRequest.Body | Should -Be $smallJson

            $largeRequest = $script:TestServer.GetRequestsForPath('/2018-06-01/runtime/invocation/test-large/response')[0]
            $largeRequest.Body | Should -Be $largeJson

            $textRequest = $script:TestServer.GetRequestsForPath('/2018-06-01/runtime/invocation/test-text/response')[0]
            $textRequest.Body | Should -Be $textBody
        }

        It "Should handle HTTP error conditions for Lambda Runtime API" {
            # Test different error status codes
            $errorCodes = @(400, 403, 404, 500, 502, 503)

            foreach ($statusCode in $errorCodes) {
                $errorPath = "/test/error/$statusCode"
                Set-TestServerResponse -Server $script:TestServer -Path $errorPath -StatusCode $statusCode -Body "Error $statusCode"

                try {
                    Invoke-RestMethod -Uri "$($script:TestEndpointUrl)$errorPath" -Method GET -TimeoutSec 3
                    throw "Should have thrown an exception for status code $statusCode"
                } catch {
                    $_.Exception.Message | Should -Match $statusCode
                }

                # Verify request was logged
                $errorRequests = $script:TestServer.GetRequestsForPath($errorPath)
                $errorRequests.Count | Should -Be 1
            }
        }
    }
}
