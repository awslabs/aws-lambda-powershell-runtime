# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Set-HandlerEnvironmentVariables function.

.DESCRIPTION
    Tests the Set-HandlerEnvironmentVariables private function which sets default TEMP
    environment variables and AWS Lambda specific environment variables from headers.
    Tests cover setting default variables, handling valid headers, missing headers,
    invalid header values, and environment variable cleanup between invocations.
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
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Set-HandlerEnvironmentVariables"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Set-HandlerEnvironmentVariables" {

    Context "When setting default TEMP environment variables" {
        BeforeEach {
            # Clear TEMP variables to test default setting
            $script:OriginalTemp = $env:TEMP
            $script:OriginalTmp = $env:TMP
            $script:OriginalTmpDir = $env:TMPDIR

            $env:TEMP = $null
            $env:TMP = $null
            $env:TMPDIR = $null

            # Create minimal headers for function call
            $script:TestHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'test-request-123'
            }
        }

        AfterEach {
            # Restore original TEMP variables
            $env:TEMP = $script:OriginalTemp
            $env:TMP = $script:OriginalTmp
            $env:TMPDIR = $script:OriginalTmpDir
        }

        It "Should set <VariableName> environment variable to /tmp" -ForEach @(
            @{ VariableName = 'TEMP' }
            @{ VariableName = 'TMP' }
            @{ VariableName = 'TMPDIR' }
        ) {
            # Act
            pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders

            # Assert
            [System.Environment]::GetEnvironmentVariable($VariableName) | Should -Be "/tmp"
        }

        It "Should override existing TEMP variables with /tmp" {
            # Arrange - Set different values first
            $env:TEMP = "/different/temp"
            $env:TMP = "/different/tmp"
            $env:TMPDIR = "/different/tmpdir"

            # Act
            pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders

            # Assert - Should be overridden to /tmp
            $env:TEMP | Should -Be "/tmp"
            $env:TMP | Should -Be "/tmp"
            $env:TMPDIR | Should -Be "/tmp"
        }

        It "Should set TEMP variables consistently across multiple invocations" {
            # Act - Call function multiple times
            pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders
            $firstTemp = $env:TEMP

            pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders
            $secondTemp = $env:TEMP

            # Assert - Should be consistent
            $firstTemp | Should -Be "/tmp"
            $secondTemp | Should -Be "/tmp"
            $firstTemp | Should -Be $secondTemp
        }
    }

    Context "When setting AWS Lambda specific environment variables from valid headers" {
        BeforeEach {
            # Clear Lambda environment variables to test setting
            $script:OriginalLambdaVars = @{
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID' = $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT' = $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY' = $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS' = $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN
                '_X_AMZN_TRACE_ID' = $env:_X_AMZN_TRACE_ID
            }

            # Clear all Lambda environment variables
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = $null
            $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT = $null
            $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY = $null
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $null
            $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN = $null
            $env:_X_AMZN_TRACE_ID = $null

            # Create complete test headers
            $script:TestHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'test-request-456'
                'Lambda-Runtime-Client-Context' = 'test-client-context'
                'Lambda-Runtime-Cognito-Identity' = 'test-cognito-identity'
                'Lambda-Runtime-Deadline-Ms' = '1640995200000'
                'Lambda-Runtime-Invoked-Function-Arn' = 'arn:aws:lambda:us-east-1:123456789012:function:test-function'
                'Lambda-Runtime-Trace-Id' = 'Root=1-5e1b4151-5ac6c58b08bd4e9c9c6b4e8a'
            }
        }

        AfterEach {
            # Restore original Lambda environment variables
            foreach ($varName in $script:OriginalLambdaVars.Keys) {
                [System.Environment]::SetEnvironmentVariable($varName, $script:OriginalLambdaVars[$varName])
            }
        }

        It "Should set <EnvVarName> from <HeaderName> header" -ForEach @(
            @{ EnvVarName = 'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID'; HeaderName = 'Lambda-Runtime-Aws-Request-Id'; TestValue = 'test-request-456' }
            @{ EnvVarName = 'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT'; HeaderName = 'Lambda-Runtime-Client-Context'; TestValue = 'test-client-context' }
            @{ EnvVarName = 'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY'; HeaderName = 'Lambda-Runtime-Cognito-Identity'; TestValue = 'test-cognito-identity' }
            @{ EnvVarName = 'AWS_LAMBDA_RUNTIME_DEADLINE_MS'; HeaderName = 'Lambda-Runtime-Deadline-Ms'; TestValue = '1640995200000' }
            @{ EnvVarName = 'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN'; HeaderName = 'Lambda-Runtime-Invoked-Function-Arn'; TestValue = 'arn:aws:lambda:us-east-1:123456789012:function:test-function' }
            @{ EnvVarName = '_X_AMZN_TRACE_ID'; HeaderName = 'Lambda-Runtime-Trace-Id'; TestValue = 'Root=1-5e1b4151-5ac6c58b08bd4e9c9c6b4e8a' }
        ) {
            # Act
            pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders

            # Assert
            [System.Environment]::GetEnvironmentVariable($EnvVarName) | Should -Be $TestValue
        }

        It "Should set all Lambda environment variables in a single call" {
            # Act
            pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders

            # Assert - Verify all variables are set correctly
            Assert-EnvironmentVariable -Name 'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID' -ExpectedValue 'test-request-456'
            Assert-EnvironmentVariable -Name 'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT' -ExpectedValue 'test-client-context'
            Assert-EnvironmentVariable -Name 'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY' -ExpectedValue 'test-cognito-identity'
            Assert-EnvironmentVariable -Name 'AWS_LAMBDA_RUNTIME_DEADLINE_MS' -ExpectedValue '1640995200000'
            Assert-EnvironmentVariable -Name 'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' -ExpectedValue 'arn:aws:lambda:us-east-1:123456789012:function:test-function'
            Assert-EnvironmentVariable -Name '_X_AMZN_TRACE_ID' -ExpectedValue 'Root=1-5e1b4151-5ac6c58b08bd4e9c9c6b4e8a'
        }
    }

    Context "When handling missing or invalid header values" {
        BeforeEach {
            # Store original values for restoration
            $script:OriginalLambdaVars = @{
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID' = $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT' = $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY' = $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS' = $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN
                '_X_AMZN_TRACE_ID' = $env:_X_AMZN_TRACE_ID
            }

            # Clear all Lambda environment variables
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = $null
            $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT = $null
            $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY = $null
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS = $null
            $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN = $null
            $env:_X_AMZN_TRACE_ID = $null
        }

        AfterEach {
            # Restore original Lambda environment variables
            foreach ($varName in $script:OriginalLambdaVars.Keys) {
                [System.Environment]::SetEnvironmentVariable($varName, $script:OriginalLambdaVars[$varName])
            }
        }

        It "Should handle empty headers hashtable without error" {
            # Arrange
            $emptyHeaders = @{}

            # Act & Assert - Should not throw
            { pwsh-runtime\Set-HandlerEnvironmentVariables $emptyHeaders } | Should -Not -Throw

            # Verify TEMP variables are still set
            $env:TEMP | Should -Be "/tmp"
            $env:TMP | Should -Be "/tmp"
            $env:TMPDIR | Should -Be "/tmp"
        }

        It "Should handle missing Lambda-Runtime-Aws-Request-Id header" {
            # Arrange
            $headersWithoutRequestId = @{
                'Lambda-Runtime-Deadline-Ms' = '1640995200000'
                'Lambda-Runtime-Trace-Id' = 'Root=1-5e1b4151-5ac6c58b08bd4e9c9c6b4e8a'
            }

            # Act
            pwsh-runtime\Set-HandlerEnvironmentVariables $headersWithoutRequestId

            # Assert - Missing header should result in null/empty environment variable
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -BeNullOrEmpty
            # But other headers should still be set
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS | Should -Be '1640995200000'
            $env:_X_AMZN_TRACE_ID | Should -Be 'Root=1-5e1b4151-5ac6c58b08bd4e9c9c6b4e8a'
        }

        It "Should handle null header values" {
            # Arrange
            $headersWithNullValues = @{
                'Lambda-Runtime-Aws-Request-Id' = $null
                'Lambda-Runtime-Client-Context' = $null
                'Lambda-Runtime-Cognito-Identity' = $null
                'Lambda-Runtime-Deadline-Ms' = '1640995200000'
                'Lambda-Runtime-Invoked-Function-Arn' = $null
                'Lambda-Runtime-Trace-Id' = $null
            }

            # Act
            pwsh-runtime\Set-HandlerEnvironmentVariables $headersWithNullValues

            # Assert - Null values should result in null/empty environment variables
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -BeNullOrEmpty
            $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT | Should -BeNullOrEmpty
            $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY | Should -BeNullOrEmpty
            $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN | Should -BeNullOrEmpty
            $env:_X_AMZN_TRACE_ID | Should -BeNullOrEmpty

            # Non-null value should still be set
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS | Should -Be '1640995200000'
        }

        It "Should handle empty string header values" {
            # Arrange
            $headersWithEmptyValues = @{
                'Lambda-Runtime-Aws-Request-Id' = ''
                'Lambda-Runtime-Client-Context' = ''
                'Lambda-Runtime-Cognito-Identity' = 'valid-identity'
                'Lambda-Runtime-Deadline-Ms' = ''
                'Lambda-Runtime-Invoked-Function-Arn' = ''
                'Lambda-Runtime-Trace-Id' = ''
            }

            # Act
            pwsh-runtime\Set-HandlerEnvironmentVariables $headersWithEmptyValues

            # Assert - Empty strings should be set as empty environment variables
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -Be ''
            $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT | Should -Be ''
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS | Should -Be ''
            $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN | Should -Be ''
            $env:_X_AMZN_TRACE_ID | Should -Be ''

            # Non-empty value should be set correctly
            $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY | Should -Be 'valid-identity'
        }

        It "Should handle headers with unexpected data types" {
            # Arrange
            $headersWithMixedTypes = @{
                'Lambda-Runtime-Aws-Request-Id' = 12345  # Number instead of string
                'Lambda-Runtime-Client-Context' = @{ nested = 'object' }  # Object instead of string
                'Lambda-Runtime-Cognito-Identity' = $true  # Boolean instead of string
                'Lambda-Runtime-Deadline-Ms' = '1640995200000'  # Valid string
                'Lambda-Runtime-Invoked-Function-Arn' = @('array', 'value')  # Array instead of string
                'Lambda-Runtime-Trace-Id' = 'valid-trace-id'  # Valid string
            }

            # Act & Assert - Should not throw even with unexpected types
            { pwsh-runtime\Set-HandlerEnvironmentVariables $headersWithMixedTypes } | Should -Not -Throw

            # PowerShell should convert these to strings when setting environment variables
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -Not -BeNullOrEmpty
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS | Should -Be '1640995200000'
            $env:_X_AMZN_TRACE_ID | Should -Be 'valid-trace-id'
        }
    }

    Context "When testing environment variable cleanup between invocations" {
        BeforeEach {
            # Store original values for restoration
            $script:OriginalLambdaVars = @{
                'AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID' = $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID
                'AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT' = $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT
                'AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY' = $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY
                'AWS_LAMBDA_RUNTIME_DEADLINE_MS' = $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS
                'AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN' = $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN
                '_X_AMZN_TRACE_ID' = $env:_X_AMZN_TRACE_ID
            }
        }

        AfterEach {
            # Restore original Lambda environment variables
            foreach ($varName in $script:OriginalLambdaVars.Keys) {
                [System.Environment]::SetEnvironmentVariable($varName, $script:OriginalLambdaVars[$varName])
            }
        }

        It "Should override previous invocation environment variables" {
            # Arrange - First invocation
            $firstHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'first-request-123'
                'Lambda-Runtime-Client-Context' = 'first-context'
                'Lambda-Runtime-Deadline-Ms' = '1640995200000'
                'Lambda-Runtime-Trace-Id' = 'first-trace-id'
            }

            # Second invocation with different values
            $secondHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'second-request-456'
                'Lambda-Runtime-Client-Context' = 'second-context'
                'Lambda-Runtime-Deadline-Ms' = '1640995300000'
                'Lambda-Runtime-Trace-Id' = 'second-trace-id'
            }

            # Act - First invocation
            pwsh-runtime\Set-HandlerEnvironmentVariables $firstHeaders
            $firstRequestId = $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID
            $firstContext = $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT

            # Act - Second invocation
            pwsh-runtime\Set-HandlerEnvironmentVariables $secondHeaders
            $secondRequestId = $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID
            $secondContext = $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT

            # Assert - Values should be overridden
            $firstRequestId | Should -Be 'first-request-123'
            $firstContext | Should -Be 'first-context'

            $secondRequestId | Should -Be 'second-request-456'
            $secondContext | Should -Be 'second-context'

            # Current environment should have second invocation values
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -Be 'second-request-456'
            $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT | Should -Be 'second-context'
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS | Should -Be '1640995300000'
            $env:_X_AMZN_TRACE_ID | Should -Be 'second-trace-id'
        }

        It "Should clear previous values when new headers are missing" {
            # Arrange - First invocation with all headers
            $firstHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'first-request-123'
                'Lambda-Runtime-Client-Context' = 'first-context'
                'Lambda-Runtime-Cognito-Identity' = 'first-identity'
                'Lambda-Runtime-Deadline-Ms' = '1640995200000'
                'Lambda-Runtime-Invoked-Function-Arn' = 'first-arn'
                'Lambda-Runtime-Trace-Id' = 'first-trace-id'
            }

            # Second invocation with only some headers
            $secondHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'second-request-456'
                'Lambda-Runtime-Deadline-Ms' = '1640995300000'
            }

            # Act - First invocation
            pwsh-runtime\Set-HandlerEnvironmentVariables $firstHeaders

            # Verify first invocation set all values
            $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT | Should -Be 'first-context'
            $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY | Should -Be 'first-identity'

            # Act - Second invocation
            pwsh-runtime\Set-HandlerEnvironmentVariables $secondHeaders

            # Assert - Missing headers should result in null/empty values (cleanup)
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -Be 'second-request-456'
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS | Should -Be '1640995300000'

            # These should be cleared/null since they weren't in second headers
            $env:AWS_LAMBDA_RUNTIME_CLIENT_CONTEXT | Should -BeNullOrEmpty
            $env:AWS_LAMBDA_RUNTIME_COGNITO_IDENTITY | Should -BeNullOrEmpty
            $env:AWS_LAMBDA_RUNTIME_INVOKED_FUNCTION_ARN | Should -BeNullOrEmpty
            $env:_X_AMZN_TRACE_ID | Should -BeNullOrEmpty
        }

        It "Should consistently reset TEMP variables on each invocation" {
            # Arrange - Modify TEMP variables between calls
            $testHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'temp-test-123'
            }

            # Act - First call
            pwsh-runtime\Set-HandlerEnvironmentVariables $testHeaders
            $firstTemp = $env:TEMP

            # Modify TEMP variables externally
            $env:TEMP = "/modified/temp"
            $env:TMP = "/modified/tmp"
            $env:TMPDIR = "/modified/tmpdir"

            # Act - Second call
            pwsh-runtime\Set-HandlerEnvironmentVariables $testHeaders
            $secondTemp = $env:TEMP

            # Assert - TEMP variables should be reset to /tmp on each call
            $firstTemp | Should -Be "/tmp"
            $secondTemp | Should -Be "/tmp"
            $env:TEMP | Should -Be "/tmp"
            $env:TMP | Should -Be "/tmp"
            $env:TMPDIR | Should -Be "/tmp"
        }
    }

    Context "When verbose logging is enabled" {
        BeforeEach {
            # Store original verbose setting
            $script:OriginalVerbose = $env:POWERSHELL_RUNTIME_VERBOSE

            # Enable verbose logging
            $env:POWERSHELL_RUNTIME_VERBOSE = 'TRUE'

            # Create test headers
            $script:TestHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'verbose-test-123'
                'Lambda-Runtime-Deadline-Ms' = '1640995200000'
            }
        }

        AfterEach {
            # Restore original verbose setting
            $env:POWERSHELL_RUNTIME_VERBOSE = $script:OriginalVerbose
        }

        It "Should execute successfully with verbose logging enabled" {
            # Act & Assert - Should not throw with verbose logging
            { pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders 6>$null } | Should -Not -Throw

            # Verify function still works correctly
            $env:TEMP | Should -Be "/tmp"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -Be 'verbose-test-123'
            $env:AWS_LAMBDA_RUNTIME_DEADLINE_MS | Should -Be '1640995200000'
        }

        It "Should work with verbose logging disabled" {
            # Arrange - Disable verbose logging
            $env:POWERSHELL_RUNTIME_VERBOSE = 'FALSE'

            # Act & Assert - Should work the same way
            { pwsh-runtime\Set-HandlerEnvironmentVariables $script:TestHeaders } | Should -Not -Throw

            # Verify function still works correctly
            $env:TEMP | Should -Be "/tmp"
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -Be 'verbose-test-123'
        }
    }

    Context "When testing parameter validation" {
        BeforeEach {
            # Store original values for restoration
            $script:OriginalRequestId = $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID
        }

        AfterEach {
            # Restore original values
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID = $script:OriginalRequestId
        }

        # It "Should require Headers parameter" {
        #     # Act & Assert - Should throw when Headers parameter is missing
        #     { pwsh-runtime\Set-HandlerEnvironmentVariables } | Should -Throw -ExpectedMessage "*Headers*"
        # }

        It "Should accept hashtable for Headers parameter" {
            # Arrange
            $validHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'param-test-123'
            }

            # Act & Assert - Should not throw with valid hashtable
            { pwsh-runtime\Set-HandlerEnvironmentVariables $validHeaders } | Should -Not -Throw

            # Verify it worked
            $env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID | Should -Be 'param-test-123'
        }
    }
}