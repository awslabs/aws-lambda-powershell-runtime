# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Integration tests for helper function interactions.

.DESCRIPTION
    Tests that verify how AssertionHelpers, TestUtilities, and TestLambdaRuntimeServer
    work together in realistic testing scenarios. These tests simulate the patterns
    used in actual Lambda runtime unit tests.
#>

BeforeAll {
    # Import all helper modules
    . "$PSScriptRoot/AssertionHelpers.ps1"
    . "$PSScriptRoot/TestUtilities.ps1"
    . "$PSScriptRoot/TestLambdaRuntimeServer.ps1"

    # Store original state
    $script:OriginalPSModulePath = $env:PSModulePath
    $script:OriginalEnvironment = @{}

    $script:TrackedEnvVars = @(
        'AWS_LAMBDA_RUNTIME_API',
        '_HANDLER',
        'LAMBDA_TASK_ROOT',
        'AWS_LAMBDA_FUNCTION_NAME'
    )

    foreach ($envVar in $script:TrackedEnvVars) {
        $script:OriginalEnvironment[$envVar] = [System.Environment]::GetEnvironmentVariable($envVar)
    }
}

AfterAll {
    # Restore original state
    $env:PSModulePath = $script:OriginalPSModulePath

    foreach ($envVar in $script:TrackedEnvVars) {
        $originalValue = $script:OriginalEnvironment[$envVar]
        [System.Environment]::SetEnvironmentVariable($envVar, $originalValue)
    }

    # Clean up any test directories
    if ($env:TEMP -and $env:TEMP.Contains("lambda-test-")) {
        Remove-Item -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "Test Environment Setup and Validation" {
    BeforeEach {
        Reset-TestEnvironment -WarningAction SilentlyContinue
    }

    AfterEach {
        Reset-TestEnvironment -WarningAction SilentlyContinue
    }

    Context "When setting up a test environment" {
        It "Should initialize environment and validate with assertions" {
            # Initialize test environment
            Initialize-TestEnvironment

            # Validate environment using assertions
            Assert-EnvironmentVariable -Name "AWS_LAMBDA_RUNTIME_API" -ExpectedValue "localhost:8888"
            Assert-EnvironmentVariable -Name "AWS_LAMBDA_FUNCTION_NAME" -ExpectedValue "test-function"
            Assert-EnvironmentVariable -Name "AWS_REGION" -ExpectedValue "us-east-1"
            Assert-EnvironmentVariable -Name "TZ" -ExpectedValue "UTC"

            # Validate temporary directory setup
            Assert-FileExists -Path $env:TEMP -ShouldBeDirectory
            Assert-FileExists -Path $env:TMP -ShouldBeDirectory
        }

        It "Should allow custom environment configuration with validation" {
            # Initialize with custom paths
            Initialize-TestEnvironment

            # Set custom environment variables
            Set-TestEnvironmentVariables -Handler "custom-handler.ps1" -RuntimeApi "localhost:8080" -FunctionName "custom-function"

            # Validate custom configuration
            Assert-EnvironmentVariable -Name "_HANDLER" -ExpectedValue "custom-handler.ps1"
            Assert-EnvironmentVariable -Name "AWS_LAMBDA_RUNTIME_API" -ExpectedValue "localhost:8080"
            Assert-EnvironmentVariable -Name "AWS_LAMBDA_FUNCTION_NAME" -ExpectedValue "custom-function"
        }
    }

    Context "When testing handler type detection with environment setup" {
        It "Should detect script handlers correctly in test environment" {
            Set-TestEnvironmentVariables -Handler "test-script.ps1"
            Initialize-TestEnvironment

            Assert-HandlerType -HandlerString $env:_HANDLER -ExpectedType "Script"
        }

        It "Should detect function handlers correctly in test environment" {
            Set-TestEnvironmentVariables -Handler "TestModule::Test-Function"
            Initialize-TestEnvironment

            Assert-HandlerType -HandlerString $env:_HANDLER -ExpectedType "Function"
        }

        It "Should detect module handlers correctly in test environment" {
            Set-TestEnvironmentVariables -Handler "TestModule"
            Initialize-TestEnvironment

            Assert-HandlerType -HandlerString $env:_HANDLER -ExpectedType "Module"
        }
    }
}

Describe "Lambda Runtime Server Integration with Assertions" {
    BeforeAll {
        $script:TestServer = Start-TestLambdaRuntimeServer -Port 9011
        Start-Sleep -Milliseconds 500
    }

    AfterAll {
        if ($script:TestServer) {
            Stop-TestLambdaRuntimeServer -Server $script:TestServer
        }
    }

    BeforeEach {
        Reset-TestServer -Server $script:TestServer
        Reset-TestEnvironment -WarningAction SilentlyContinue
        Initialize-TestEnvironment
        Set-TestEnvironmentVariables -RuntimeApi "localhost:9011"
    }

    AfterEach {
        Reset-TestEnvironment -WarningAction SilentlyContinue
    }

    Context "When testing Lambda event processing workflow" {
        It "Should handle event processing cycle with assertions" {
            # Generate test event
            $testEvent = New-TestEvent -EventType S3 -BucketName "integration-test-bucket" -ObjectKey "test-file.txt"

            # Configure server with test event
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $testEvent -RequestId "integration-test-123"

            # Simulate Lambda runtime API call
            $response = Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3

            # Validate response using JSON assertions
            $responseJson = $response | ConvertTo-Json -Depth 10
            Assert-JsonResponse -JsonString $responseJson -ShouldHaveProperty "Records"
            Assert-JsonResponse -JsonString $responseJson -ShouldContainValue "integration-test-bucket"
            Assert-JsonResponse -JsonString $responseJson -ShouldContainValue "test-file.txt"

            # Validate API call was made correctly
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" -ExpectedCallCount 1

            # Simulate function response
            $functionResponse = @{
                statusCode = 200
                body = "Processed S3 event"
            } | ConvertTo-Json

            try {
                Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/integration-test-123/response" -Method POST -Body $functionResponse -ContentType "application/json" -TimeoutSec 3
            } catch {
                # Expected - server returns 202
            }

            # Validate response was posted correctly
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/integration-test-123/response" -Method "POST" -ShouldContainBody "Processed"
        }

        It "Should handle error scenarios with proper assertions" {
            # Generate test event
            $testEvent = New-TestEvent -EventType Custom -CustomData @{ shouldFail = $true }

            # Configure server
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $testEvent -RequestId "error-test-456"

            # Get event
            $response = Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3

            # Validate event structure
            $responseJson = $response | ConvertTo-Json -Depth 10
            Assert-JsonResponse -JsonString $responseJson -ShouldHaveProperty "shouldFail"
            Assert-JsonResponse -JsonString $responseJson -ShouldHaveProperty "eventType" -PropertyValue "Custom"

            # Simulate error response
            $errorResponse = @{
                errorMessage = "Function execution failed"
                errorType = "RuntimeError"
                stackTrace = @("at Test-Function line 1", "at Invoke-Handler line 5")
            } | ConvertTo-Json

            try {
                Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/error-test-456/error" -Method POST -Body $errorResponse -ContentType "application/json" -TimeoutSec 3
            } catch {
                # Expected - server returns 202
            }

            # Validate error was posted correctly
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/error-test-456/error" -Method "POST" -ShouldContainBody "RuntimeError"
        }
    }

    Context "When testing multiple invocation scenarios" {
        It "Should handle sequential invocations with proper tracking" {
            # First invocation
            $event1 = New-TestEvent -EventType ApiGateway -HttpMethod "GET" -Path "/users"
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $event1 -RequestId "seq-1"

            $response1 = Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3
            Assert-JsonResponse -JsonString ($response1 | ConvertTo-Json) -ShouldHaveProperty "httpMethod" -PropertyValue "GET"

            # Second invocation
            $event2 = New-TestEvent -EventType ApiGateway -HttpMethod "POST" -Path "/users"
            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $event2 -RequestId "seq-2"

            $response2 = Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3
            Assert-JsonResponse -JsonString ($response2 | ConvertTo-Json) -ShouldHaveProperty "httpMethod" -PropertyValue "POST"

            # Validate both calls were tracked
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" -ExpectedCallCount 2

            # Respond to both
            try {
                Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/seq-1/response" -Method POST -Body '{"statusCode": 200}' -ContentType "application/json" -TimeoutSec 3
                Invoke-RestMethod -Uri "http://localhost:9011/2018-06-01/runtime/invocation/seq-2/response" -Method POST -Body '{"statusCode": 201}' -ContentType "application/json" -TimeoutSec 3
            } catch {
                # Expected - server returns 202
            }

            # Validate responses
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/seq-1/response" -Method "POST" -ShouldContainBody "200"
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/seq-2/response" -Method "POST" -ShouldContainBody "201"
        }
    }
}

Describe "Event Generation and Validation Integration" {
    Context "When generating and validating different event types" {
        It "Should generate and validate API Gateway events" {
            $event = New-TestEvent -EventType ApiGateway -HttpMethod "PUT" -Path "/api/v1/resource"
            $eventJson = $event | ConvertTo-Json -Depth 10

            # Validate structure
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "httpMethod" -PropertyValue "PUT"
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "path" -PropertyValue "/api/v1/resource"
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "requestContext"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "123456789012"  # Account ID

            # Validate request context structure
            $requestContext = $event.requestContext | ConvertTo-Json -Depth 5
            Assert-JsonResponse -JsonString $requestContext -ShouldHaveProperty "requestId"
            Assert-JsonResponse -JsonString $requestContext -ShouldHaveProperty "accountId" -PropertyValue "123456789012"
        }

        It "Should generate and validate S3 events" {
            $event = New-TestEvent -EventType S3 -BucketName "validation-bucket" -ObjectKey "validation-object.json"
            $eventJson = $event | ConvertTo-Json -Depth 10

            # Validate top-level structure
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "Records"

            # Validate S3-specific structure
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "aws:s3"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "s3:ObjectCreated:Put"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "validation-bucket"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "validation-object.json"

            # Validate record structure
            $record = $event.Records[0] | ConvertTo-Json -Depth 5
            Assert-JsonResponse -JsonString $record -ShouldHaveProperty "eventSource" -PropertyValue "aws:s3"
            Assert-JsonResponse -JsonString $record -ShouldHaveProperty "eventName" -PropertyValue "s3:ObjectCreated:Put"
        }

        It "Should generate and validate CloudWatch events" {
            $event = New-TestEvent -EventType CloudWatch
            $eventJson = $event | ConvertTo-Json -Depth 10

            # Validate CloudWatch event structure
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "account" -PropertyValue "123456789012"
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "region" -PropertyValue "us-east-1"
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "detail-type" -PropertyValue "Test Event"
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "source" -PropertyValue "test.application"
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "detail"

            # Validate timestamp format
            $event.time | Should -Match "\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z"
        }

        It "Should generate and validate custom events with complex data" {
            $complexData = @{
                user = @{
                    id = 12345
                    name = "Test User"
                    preferences = @{
                        theme = "dark"
                        notifications = $true
                    }
                }
                metadata = @{
                    version = "2.1.0"
                    features = @("feature1", "feature2", "feature3")
                }
            }

            $event = New-TestEvent -EventType Custom -CustomData $complexData
            $eventJson = $event | ConvertTo-Json -Depth 10

            # Validate base custom event structure
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "eventType" -PropertyValue "Custom"
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "timestamp"

            # Validate custom data integration
            Assert-JsonResponse -JsonString $eventJson -ShouldHaveProperty "user"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "Test User"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "dark"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "2.1.0"
            Assert-JsonResponse -JsonString $eventJson -ShouldContainValue "feature1"
        }
    }
}

Describe "End-to-End Testing Workflow Simulation" {
    BeforeAll {
        $script:TestServer = Start-TestLambdaRuntimeServer -Port 9012
        Start-Sleep -Milliseconds 500
    }

    AfterAll {
        if ($script:TestServer) {
            Stop-TestLambdaRuntimeServer -Server $script:TestServer
        }
    }

    BeforeEach {
        Reset-TestServer -Server $script:TestServer
        Reset-TestEnvironment -WarningAction SilentlyContinue
    }

    AfterEach {
        Reset-TestEnvironment -WarningAction SilentlyContinue
    }

    Context "When simulating Get-LambdaNextInvocation testing pattern" {
        It "Should replicate the testing workflow used in actual unit tests" {
            # Step 1: Initialize test environment (like BeforeAll in actual tests)
            Initialize-TestEnvironment
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9012"

            # Validate environment setup
            Assert-EnvironmentVariable -Name "AWS_LAMBDA_RUNTIME_API" -ExpectedValue "localhost:9012"

            # Step 2: Configure test server with Lambda event (like BeforeEach)
            $testEvent = @{
                test = "event"
                key = "value"
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }

            Set-TestServerLambdaEvent -Server $script:TestServer -LambdaEvent $testEvent -RequestId "workflow-test-123"

            # Step 3: Simulate the function under test making API call
            $response = Invoke-RestMethod -Uri "http://localhost:9012/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3

            # Step 4: Validate API call was made correctly (like actual unit tests)
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" -ExpectedCallCount 1

            # Step 5: Validate response structure and content
            $response | Should -Not -BeNullOrEmpty
            $responseJson = $response | ConvertTo-Json -Depth 5
            Assert-JsonResponse -JsonString $responseJson -ShouldHaveProperty "test" -PropertyValue "event"
            Assert-JsonResponse -JsonString $responseJson -ShouldHaveProperty "key" -PropertyValue "value"
            Assert-JsonResponse -JsonString $responseJson -ShouldContainValue "event"

            # Step 6: Validate headers were set correctly (simulating header validation)
            $webRequest = [System.Net.WebRequest]::Create("http://localhost:9012/2018-06-01/runtime/invocation/next")
            $webRequest.Method = "GET"
            $httpResponse = $webRequest.GetResponse()

            $httpResponse.Headers['Lambda-Runtime-Aws-Request-Id'] | Should -Be "workflow-test-123"
            $httpResponse.Headers['Lambda-Runtime-Deadline-Ms'] | Should -Not -BeNullOrEmpty
            $httpResponse.Headers['Content-Type'] | Should -Be 'application/json'

            $httpResponse.Close()

            # This workflow demonstrates how all helper functions work together
            # in the same pattern used by actual Lambda runtime unit tests
        }
    }

    Context "When simulating error handling testing patterns" {
        It "Should handle the error testing workflow" {
            # Initialize environment
            Initialize-TestEnvironment
            Set-TestEnvironmentVariables -RuntimeApi "localhost:9012"

            # Configure server to return HTTP error
            Set-TestServerResponse -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -StatusCode 500 -Body "Internal Server Error"

            # Attempt API call (should handle error gracefully)
            try {
                Invoke-RestMethod -Uri "http://localhost:9012/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3
                throw "Should have thrown an exception"
            }
            catch {
                $_.Exception.Message | Should -Match "500"
            }

            # Validate that the API call was attempted
            Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" -ExpectedCallCount 1

            # This demonstrates how error scenarios are tested using the helper functions
        }
    }
}

Describe "Helper Function Robustness and Edge Cases" {
    Context "When testing helper functions under stress" {
        It "Should handle rapid environment changes correctly" {
            # Rapid initialization and reset cycles
            for ($i = 0; $i -lt 5; $i++) {
                Initialize-TestEnvironment
                Assert-EnvironmentVariable -Name "AWS_LAMBDA_RUNTIME_API" -ExpectedValue "localhost:8888"

                Reset-TestEnvironment -WarningAction SilentlyContinue
                # After reset, the test environment should be clean
                # (Original values should be restored)
            }
        }

        It "Should handle complex event generation scenarios" {
            # Generate multiple different event types rapidly
            $events = @()

            $events += New-TestEvent -EventType ApiGateway -HttpMethod "GET" -Path "/test1"
            $events += New-TestEvent -EventType S3 -BucketName "bucket1" -ObjectKey "key1"
            $events += New-TestEvent -EventType CloudWatch
            $events += New-TestEvent -EventType Custom -CustomData @{ test = "data" }

            # Validate all events
            foreach ($event in $events) {
                $eventJson = $event | ConvertTo-Json -Depth 10
                Assert-JsonResponse -JsonString $eventJson
            }

            # Each event should have unique identifiers
            $requestIds = $events | ForEach-Object {
                if ($_.requestContext) { $_.requestContext.requestId }
                elseif ($_.requestId) { $_.requestId }
                elseif ($_.id) { $_.id }
            }

            $requestIds | Should -Not -BeNullOrEmpty
            $requestIds.Count | Should -Be ($requestIds | Select-Object -Unique).Count
        }
    }

}