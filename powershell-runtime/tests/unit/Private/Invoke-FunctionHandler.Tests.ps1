# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Invoke-FunctionHandler private function.

.DESCRIPTION
    Tests the Invoke-FunctionHandler function which invokes Lambda handlers based on
    handler type (Script, Function, Module) and converts responses to JSON format.
    Tests cover all handler types, response conversion, and error handling scenarios.
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
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Invoke-FunctionHandler"

    # Create test fixtures directory structure
    $script:TestFixturesPath = Join-Path $TestDrive "fixtures"
    $script:MockHandlersPath = Join-Path $script:TestFixturesPath "mock-handlers"
    $script:TestModulesPath = Join-Path $script:TestFixturesPath "test-modules"

    New-Item -ItemType Directory -Path $script:TestFixturesPath -Force | Out-Null
    New-Item -ItemType Directory -Path $script:MockHandlersPath -Force | Out-Null
    New-Item -ItemType Directory -Path $script:TestModulesPath -Force | Out-Null

    # Create mock script handlers for testing
    $script:SimpleScriptHandler = @'
param($LambdaInput, $LambdaContext)
return @{
    statusCode = 200
    body = "Hello from script handler"
    input = $LambdaInput
    requestId = $LambdaContext.AwsRequestId
} | ConvertTo-Json -Compress -Depth 6
'@

    $script:ErrorScriptHandler = @'
param($LambdaInput, $LambdaContext)
throw "Script handler error for testing"
'@

    $script:StringResponseHandler = @'
param($LambdaInput, $LambdaContext)
return "Simple string response"
'@

    # Write script handlers to files
    Set-Content -Path (Join-Path $script:MockHandlersPath "simple-handler.ps1") -Value $script:SimpleScriptHandler
    Set-Content -Path (Join-Path $script:MockHandlersPath "error-handler.ps1") -Value $script:ErrorScriptHandler
    Set-Content -Path (Join-Path $script:MockHandlersPath "string-handler.ps1") -Value $script:StringResponseHandler

    # Create a script with functions for function handler testing
    $script:FunctionScriptContent = @'
function global:Test-SimpleFunction {
    param($LambdaInput, $LambdaContext)
    return @{
        statusCode = 200
        body = "Hello from function handler"
        functionName = "Test-SimpleFunction"
        input = $LambdaInput
        requestId = $LambdaContext.AwsRequestId
    }
}

function global:Test-ErrorFunction {
    param($LambdaInput, $LambdaContext)
    throw "Function handler error for testing"
}

function global:Test-StringFunction {
    param($LambdaInput, $LambdaContext)
    return "Function string response"
}
'@

    Set-Content -Path (Join-Path $script:MockHandlersPath "function-handlers.ps1") -Value $script:FunctionScriptContent

    # Create a test module for module handler testing
    $script:TestModuleContent = @'
function Invoke-TestModule {
    param($LambdaInput, $LambdaContext)
    return @{
        statusCode = 200
        body = "Hello from module handler"
        moduleName = "TestModule"
        input = $LambdaInput
        requestId = $LambdaContext.AwsRequestId
    }
}

function Invoke-ErrorModule {
    param($LambdaInput, $LambdaContext)
    throw "Module handler error for testing"
}

function Invoke-StringModule {
    param($LambdaInput, $LambdaContext)
    return "Module string response"
}
'@

    $testModuleDir = Join-Path $script:TestModulesPath "TestModule"
    New-Item -ItemType Directory -Path $testModuleDir -Force | Out-Null
    Set-Content -Path (Join-Path $testModuleDir "TestModule.psm1") -Value $script:TestModuleContent

    # Create module manifest with valid GUID
    $manifestContent = @'
@{
    RootModule = 'TestModule.psm1'
    ModuleVersion = '1.0.0'
    GUID = '12345678-1234-1234-1234-123456789012'
    Author = 'Test Author'
    Description = 'Test module for handler testing'
    FunctionsToExport = @('Invoke-TestModule', 'Invoke-ErrorModule', 'Invoke-StringModule')
}
'@
    Set-Content -Path (Join-Path $testModuleDir "TestModule.psd1") -Value $manifestContent

    # Add test modules path to PSModulePath
    $env:PSModulePath = "$script:TestModulesPath$([System.IO.Path]::PathSeparator)$env:PSModulePath"
}

AfterAll {
    # Clean up global functions
    Remove-Item -Path "function:global:Test-SimpleFunction" -ErrorAction SilentlyContinue
    Remove-Item -Path "function:global:Test-ErrorFunction" -ErrorAction SilentlyContinue
    Remove-Item -Path "function:global:Test-StringFunction" -ErrorAction SilentlyContinue

    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Invoke-FunctionHandler" {

    Context "When handler type is Script" {
        BeforeEach {
            # Create sample runtime response and Lambda context
            $script:TestEvent = @{
                test = "event"
                message = "Hello World"
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            }

            $script:RuntimeResponse = @{
                headers = @{
                    'Lambda-Runtime-Aws-Request-Id' = 'test-request-123'
                    'Lambda-Runtime-Deadline-Ms' = ([DateTimeOffset]::UtcNow.AddMinutes(5).ToUnixTimeMilliseconds()).ToString()
                }
                incomingEvent = ($script:TestEvent | ConvertTo-Json -Compress)
            }

            $script:LambdaContext = New-Object PSObject -Property @{
                AwsRequestId = 'test-request-123'
                FunctionName = 'test-function'
                FunctionVersion = '1'
                InvokedFunctionArn = 'arn:aws:lambda:us-east-1:123456789012:function:test-function'
                MemoryLimitInMB = 128
                RemainingTimeInMillis = 300000
            }
        }

        It "Should invoke script handler with correct parameters" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "simple-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -Not -BeNullOrEmpty

            # Parse JSON response to verify content
            $responseObj = $result | ConvertFrom-Json
            $responseObj.statusCode | Should -Be 200
            $responseObj.body | Should -Be "Hello from script handler"
            $responseObj.requestId | Should -Be 'test-request-123'
            $responseObj.input.test | Should -Be "event"
            $responseObj.input.message | Should -Be "Hello World"
        }

        It "Should handle script handler that returns string response" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "string-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -Be "Simple string response"
        }

        It "Should pass correct LambdaInput and LambdaContext to script" {
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
            }

            $complexRuntimeResponse = @{
                headers = @{
                    'Lambda-Runtime-Aws-Request-Id' = 'complex-request-456'
                }
                incomingEvent = ($complexEvent | ConvertTo-Json -Compress -Depth 5)
            }

            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "simple-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $complexRuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $responseObj = $result | ConvertFrom-Json
            $responseObj.input.Records | Should -Not -BeNullOrEmpty
            $responseObj.input.Records[0].eventName | Should -Be "s3:ObjectCreated:Put"
            $responseObj.input.Records[0].s3.bucket.name | Should -Be "test-bucket"
        }

        It "Should handle script handler execution errors" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "error-handler.ps1"
            }

            # Act & Assert
            { pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext } | Should -Throw "*Script handler error for testing*"
        }
    }

    Context "When handler type is Function" {
        BeforeAll {
            # Load the function script first - do this in BeforeAll so functions are available to all tests
            . (Join-Path $script:MockHandlersPath "function-handlers.ps1")
        }

        BeforeEach {

            # Create sample runtime response and Lambda context
            $script:TestEvent = @{
                test = "function-event"
                data = "function-data"
            }

            $script:RuntimeResponse = @{
                headers = @{
                    'Lambda-Runtime-Aws-Request-Id' = 'function-request-789'
                }
                incomingEvent = ($script:TestEvent | ConvertTo-Json -Compress)
            }

            $script:LambdaContext = New-Object PSObject -Property @{
                AwsRequestId = 'function-request-789'
                FunctionName = 'test-function'
                RemainingTimeInMillis = 250000
            }
        }

        It "Should invoke function handler with correct parameters" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Function'
                functionName = 'Test-SimpleFunction'
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -Not -BeNullOrEmpty

            # Parse JSON response to verify content
            $responseObj = $result | ConvertFrom-Json
            $responseObj.statusCode | Should -Be 200
            $responseObj.body | Should -Be "Hello from function handler"
            $responseObj.functionName | Should -Be "Test-SimpleFunction"
            $responseObj.requestId | Should -Be 'function-request-789'
            $responseObj.input.test | Should -Be "function-event"
            $responseObj.input.data | Should -Be "function-data"
        }

        It "Should handle function handler that returns string response" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Function'
                functionName = 'Test-StringFunction'
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -Be "Function string response"
        }

        It "Should handle function handler execution errors" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Function'
                functionName = 'Test-ErrorFunction'
            }

            # Act & Assert
            { pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext } | Should -Throw "*Function handler error for testing*"
        }

        It "Should pass parsed JSON event to function handler" {
            # Arrange
            $apiGatewayEvent = @{
                httpMethod = 'POST'
                path = '/api/test'
                body = '{"key":"value"}'
                headers = @{
                    'Content-Type' = 'application/json'
                }
            }

            $apiGatewayResponse = @{
                headers = @{
                    'Lambda-Runtime-Aws-Request-Id' = 'api-request-999'
                }
                incomingEvent = ($apiGatewayEvent | ConvertTo-Json -Compress -Depth 5)
            }

            $handlerArray = @{
                handlerType = 'Function'
                functionName = 'Test-SimpleFunction'
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $apiGatewayResponse $handlerArray $script:LambdaContext

            # Assert
            $responseObj = $result | ConvertFrom-Json
            $responseObj.input.httpMethod | Should -Be 'POST'
            $responseObj.input.path | Should -Be '/api/test'
            $responseObj.input.body | Should -Be '{"key":"value"}'
        }
    }

    Context "When handler type is Module" {
        BeforeEach {
            # Import the test module
            Import-Module (Join-Path $script:TestModulesPath "TestModule") -Force

            # Create sample runtime response and Lambda context
            $script:TestEvent = @{
                test = "module-event"
                moduleData = "test-data"
            }

            $script:RuntimeResponse = @{
                headers = @{
                    'Lambda-Runtime-Aws-Request-Id' = 'module-request-555'
                }
                incomingEvent = ($script:TestEvent | ConvertTo-Json -Compress)
            }

            $script:LambdaContext = New-Object PSObject -Property @{
                AwsRequestId = 'module-request-555'
                FunctionName = 'test-module-function'
                RemainingTimeInMillis = 200000
            }
        }

        It "Should invoke module handler with correct parameters" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Module'
                functionName = 'Invoke-TestModule'
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -Not -BeNullOrEmpty

            # Parse JSON response to verify content
            $responseObj = $result | ConvertFrom-Json
            $responseObj.statusCode | Should -Be 200
            $responseObj.body | Should -Be "Hello from module handler"
            $responseObj.moduleName | Should -Be "TestModule"
            $responseObj.requestId | Should -Be 'module-request-555'
            $responseObj.input.test | Should -Be "module-event"
            $responseObj.input.moduleData | Should -Be "test-data"
        }

        It "Should handle module handler that returns string response" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Module'
                functionName = 'Invoke-StringModule'
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -Be "Module string response"
        }

        It "Should handle module handler execution errors" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Module'
                functionName = 'Invoke-ErrorModule'
            }

            # Act & Assert
            { pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext } | Should -Throw "*Module handler error for testing*"
        }
    }

    Context "When testing response conversion to JSON format" {
        BeforeEach {
            $script:TestEvent = @{ test = "json-conversion" }
            $script:RuntimeResponse = @{
                headers = @{ 'Lambda-Runtime-Aws-Request-Id' = 'json-test-123' }
                incomingEvent = ($script:TestEvent | ConvertTo-Json -Compress)
            }
            $script:LambdaContext = New-Object PSObject -Property @{ AwsRequestId = 'json-test-123' }
        }

        It "Should convert hashtable response to JSON string" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "simple-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -BeOfType [string]
            { $result | ConvertFrom-Json } | Should -Not -Throw

            # Verify JSON structure
            Assert-JsonResponse -JsonString $result -ShouldHaveProperty "statusCode"
            Assert-JsonResponse -JsonString $result -ShouldHaveProperty "body"
        }

        It "Should convert PSCustomObject response to JSON string" {
            # Create a script that returns PSCustomObject
            $psoScript = @'
param($LambdaInput, $LambdaContext)
$response = New-Object PSObject -Property @{
    statusCode = 201
    headers = @{ 'Content-Type' = 'application/json' }
    body = @{ message = "PSCustomObject response" }
}
return $response
'@
            Set-Content -Path (Join-Path $script:MockHandlersPath "pso-handler.ps1") -Value $psoScript

            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "pso-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -BeOfType [string]
            { $result | ConvertFrom-Json } | Should -Not -Throw

            $responseObj = $result | ConvertFrom-Json
            $responseObj.statusCode | Should -Be 201
            $responseObj.headers.'Content-Type' | Should -Be 'application/json'
        }

        It "Should convert array response to JSON string" {
            # Create a script that returns an array
            $arrayScript = @'
param($LambdaInput, $LambdaContext)
return @(
    @{ id = 1; name = "Item 1" },
    @{ id = 2; name = "Item 2" },
    @{ id = 3; name = "Item 3" }
)
'@
            Set-Content -Path (Join-Path $script:MockHandlersPath "array-handler.ps1") -Value $arrayScript

            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "array-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -BeOfType [string]
            { $result | ConvertFrom-Json } | Should -Not -Throw

            $responseArray = $result | ConvertFrom-Json
            $responseArray.Count | Should -Be 3
            $responseArray[0].id | Should -Be 1
            $responseArray[2].name | Should -Be "Item 3"
        }

        It "Should not convert string response to JSON" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "string-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -BeOfType [string]
            $result | Should -Be "Simple string response"

            # Should not be valid JSON since it's a plain string
            { $result | ConvertFrom-Json } | Should -Throw
        }

        It "Should handle null response gracefully" {
            # Create a script that returns null
            $nullScript = @'
param($LambdaInput, $LambdaContext)
return $null
'@
            Set-Content -Path (Join-Path $script:MockHandlersPath "null-handler.ps1") -Value $nullScript

            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "null-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -BeNullOrEmpty
        }

        It "Should handle empty string response" {
            # Create a script that returns empty string
            $emptyScript = @'
param($LambdaInput, $LambdaContext)
return ""
'@
            Set-Content -Path (Join-Path $script:MockHandlersPath "empty-handler.ps1") -Value $emptyScript

            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "empty-handler.ps1"
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext

            # Assert
            $result | Should -Be ""
        }
    }

    Context "When verbose logging is enabled" {
        BeforeEach {
            $script:OriginalVerbose = $env:POWERSHELL_RUNTIME_VERBOSE
            $env:POWERSHELL_RUNTIME_VERBOSE = 'TRUE'

            $script:TestEvent = @{ test = "verbose-test" }
            $script:RuntimeResponse = @{
                headers = @{ 'Lambda-Runtime-Aws-Request-Id' = 'verbose-123' }
                incomingEvent = ($script:TestEvent | ConvertTo-Json -Compress)
            }
            $script:LambdaContext = New-Object PSObject -Property @{ AwsRequestId = 'verbose-123' }
        }

        AfterEach {
            $env:POWERSHELL_RUNTIME_VERBOSE = $script:OriginalVerbose
        }

        It "Should execute successfully with verbose logging for <HandlerType> handler" -ForEach @(
            @{ HandlerType = 'Script'; SetupAction = 'Script' }
            @{ HandlerType = 'Function'; SetupAction = 'Function' }
            @{ HandlerType = 'Module'; SetupAction = 'Module' }
        ) {
            # Arrange
            switch ($SetupAction) {
                'Script' {
                    $handlerArray = @{
                        handlerType = 'Script'
                        scriptFilePath = Join-Path $script:MockHandlersPath "simple-handler.ps1"
                    }
                }
                'Function' {
                    if (-not (Get-Command Test-SimpleFunction -ErrorAction SilentlyContinue)) {
                        . (Join-Path $script:MockHandlersPath "function-handlers.ps1")
                    }
                    $handlerArray = @{
                        handlerType = 'Function'
                        functionName = 'Test-SimpleFunction'
                    }
                }
                'Module' {
                    Import-Module (Join-Path $script:TestModulesPath "TestModule") -Force
                    $handlerArray = @{
                        handlerType = 'Module'
                        functionName = 'Invoke-TestModule'
                    }
                }
            }

            # Act
            $result = pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext 6>$null

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $responseObj = $result | ConvertFrom-Json
            $responseObj.statusCode | Should -Be 200
        }
    }

    Context "When testing edge cases and error conditions" {
        BeforeEach {
            $script:TestEvent = @{ test = "edge-case" }
            $script:RuntimeResponse = @{
                headers = @{ 'Lambda-Runtime-Aws-Request-Id' = 'edge-123' }
                incomingEvent = ($script:TestEvent | ConvertTo-Json -Compress)
            }
            $script:LambdaContext = New-Object PSObject -Property @{ AwsRequestId = 'edge-123' }
        }

        It "Should handle invalid JSON in incoming event" {
            # Arrange
            $invalidJsonResponse = @{
                headers = @{ 'Lambda-Runtime-Aws-Request-Id' = 'invalid-json-123' }
                incomingEvent = '{"invalid": json}'  # Invalid JSON
            }

            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "simple-handler.ps1"
            }

            # Act & Assert
            { pwsh-runtime\Invoke-FunctionHandler $invalidJsonResponse $handlerArray $script:LambdaContext } | Should -Throw
        }

        It "Should handle missing script file for script handler" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Script'
                scriptFilePath = Join-Path $script:MockHandlersPath "non-existent-handler.ps1"
            }

            # Act & Assert
            { pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext } | Should -Throw
        }

        It "Should handle non-existent function for function handler" {
            # Arrange
            $handlerArray = @{
                handlerType = 'Function'
                functionName = 'Non-ExistentFunction'
            }

            # Act & Assert
            { pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext } | Should -Throw
        }

        It "Should handle non-existent function for module handler" {
            # Arrange
            Import-Module (Join-Path $script:TestModulesPath "TestModule") -Force
            $handlerArray = @{
                handlerType = 'Module'
                functionName = 'Non-ExistentModuleFunction'
            }

            # Act & Assert
            { pwsh-runtime\Invoke-FunctionHandler $script:RuntimeResponse $handlerArray $script:LambdaContext } | Should -Throw
        }
    }
}