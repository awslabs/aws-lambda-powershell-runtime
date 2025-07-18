# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Integration tests for PowerShell Lambda Runtime.

.DESCRIPTION
    This file contains integration tests that verify the PowerShell Lambda Runtime
    works correctly with AWS Lambda. These tests require AWS resources to be deployed
    and environment variables to be set using the Set-IntegrationTestEnvironment.ps1 script.
#>

BeforeAll {
    # Import required modules
    Import-Module AWS.Tools.Lambda -ErrorAction Stop
    Import-Module "$PSScriptRoot/../helpers/LambdaIntegrationHelpers.psm1" -Force -ErrorAction Stop

    # Check if required environment variables are set
    $requiredEnvVars = @(
        'PWSH_TEST_SCRIPTHANDLERFUNCTIONNAME',
        'PWSH_TEST_FUNCTIONHANDLERFUNCTIONNAME',
        'PWSH_TEST_MODULEHANDLERFUNCTIONNAME',
        'PWSH_TEST_INFRASTRUCTURE_DEPLOYED'
    )

    $missingVars = $requiredEnvVars | Where-Object { -not (Test-Path "env:$_") }
    if ($missingVars.Count -gt 0) {
        throw "Missing required environment variables: $($missingVars -join ', '). Please run Set-IntegrationTestEnvironment.ps1 first."
    }

    # Get AWS authentication parameters from helper function
    $script:awsAuth = Get-AwsAuthParameters

    # Define handler configurations
    $script:HandlerConfigs = @(
        @{
            HandlerType = 'Script'
            FunctionName = $env:PWSH_TEST_SCRIPTHANDLERFUNCTIONNAME
            ExpectedMessage = "Hello from PowerShell script handler!"
            TestKey = "scriptTest"
            TestData = @{ number = 42; string = "test"; bool = $true }
        }
        @{
            HandlerType = 'Function'
            FunctionName = $env:PWSH_TEST_FUNCTIONHANDLERFUNCTIONNAME
            ExpectedMessage = "Hello from PowerShell function handler!"
            TestKey = "functionTest"
            TestData = @{ array = @(1, 2, 3); string = "function"; bool = $false }
        }
        @{
            HandlerType = 'Module'
            FunctionName = $env:PWSH_TEST_MODULEHANDLERFUNCTIONNAME
            ExpectedMessage = "Hello from PowerShell module handler!"
            TestKey = "moduleTest"
            TestData = @{ nested = @{ key = "value" }; number = 123; bool = $true }
        }
    )

    # Initialize response cache to reduce Lambda invocations
    Write-Host "Initializing handler response cache..."
    Initialize-HandlerResponseCache -HandlerConfigs $script:HandlerConfigs @script:awsAuth
    Write-Host "Response cache initialized successfully."
}

Describe "PowerShell Lambda Runtime Integration Tests" {
    Context "Handler Invocation and Input Validation Tests" {
        It "Should successfully invoke and validate <HandlerType> handler" -ForEach $script:HandlerConfigs {
            # Get cached response to avoid duplicate Lambda invocations
            $cachedResult = Get-CachedHandlerResponse -HandlerType $_.HandlerType

            # Perform complete validation using consolidated helper function
            Test-LambdaHandlerValidation -Response $cachedResult.Response -Config $cachedResult.Config
        }
    }

    Context "Lambda Context Property Validation" {
        It "Should validate all Lambda context properties for <HandlerType> handler" -ForEach $script:HandlerConfigs {
            # Get cached response - no additional Lambda invocation needed
            $cachedResult = Get-CachedHandlerResponse -HandlerType $_.HandlerType
            $responseBody = $cachedResult.Response.body | ConvertFrom-Json

            # Use schema-based validation instead of repetitive assertions
            Assert-LambdaContextSchema -ContextInfo $responseBody.contextInfo -FunctionName $_.FunctionName
        }
    }

    Context "Input Data Type Preservation Tests" {
        It "Should preserve <DataType> data types correctly for <HandlerType> handler" -ForEach @(
            @{ HandlerType = 'Script'; DataType = 'Number'; TestValue = 42; PropertyName = 'number' }
            @{ HandlerType = 'Script'; DataType = 'Boolean'; TestValue = $true; PropertyName = 'bool' }
            @{ HandlerType = 'Function'; DataType = 'Array'; TestValue = @(1, 2, 3); PropertyName = 'array' }
            @{ HandlerType = 'Function'; DataType = 'Boolean'; TestValue = $false; PropertyName = 'bool' }
            @{ HandlerType = 'Module'; DataType = 'Nested Object'; TestValue = @{ key = "value" }; PropertyName = 'nested' }
            @{ HandlerType = 'Module'; DataType = 'Number'; TestValue = 123; PropertyName = 'number' }
        ) {
            # Get cached response
            $cachedResult = Get-CachedHandlerResponse -HandlerType $_.HandlerType
            $responseBody = $cachedResult.Response.body | ConvertFrom-Json

            # Use deep equality validation for data type preservation
            $actualValue = $responseBody.input.($_.PropertyName)
            Assert-DeepEqual -Actual $actualValue -Expected $_.TestValue -Path "input.$($_.PropertyName)"
        }
    }

    Context "Response Structure Validation" {
        It "Should have consistent response structure across all handler types" {
            foreach ($config in $script:HandlerConfigs) {
                $cachedResult = Get-CachedHandlerResponse -HandlerType $config.HandlerType
                $response = $cachedResult.Response
                $responseBody = $response.body | ConvertFrom-Json

                # Validate response structure
                $response.statusCode | Should -Be 200 -Because "$($config.HandlerType) handler should return status 200"

                # Validate required response body properties
                $requiredProperties = @('message', 'input', 'contextInfo')
                foreach ($property in $requiredProperties) {
                    $responseBody.PSObject.Properties.Name | Should -Contain $property -Because "$($config.HandlerType) response should contain $property"
                }

                # Validate message content
                $responseBody.message | Should -Be $config.ExpectedMessage -Because "$($config.HandlerType) should return expected message"

                # Validate input echo
                $responseBody.input.testKey | Should -Be $config.TestKey -Because "$($config.HandlerType) should echo test key correctly"
            }
        }
    }

    Context "Performance and Consistency Validation" {
        It "Should have reasonable execution times and consistent context values" {
            foreach ($config in $script:HandlerConfigs) {
                $cachedResult = Get-CachedHandlerResponse -HandlerType $config.HandlerType
                $responseBody = $cachedResult.Response.body | ConvertFrom-Json
                $contextInfo = $responseBody.contextInfo

                # Validate execution time is reasonable
                $contextInfo.RemainingTimeMs | Should -BeGreaterThan 0 -Because "$($config.HandlerType) should have positive remaining time"
                $contextInfo.RemainingTimeMs | Should -BeLessThan 900000 -Because "$($config.HandlerType) should complete within reasonable time"

                # Validate context consistency flags
                $contextInfo.HasValidRequestId | Should -BeTrue -Because "$($config.HandlerType) should have valid request ID"
                $contextInfo.HasValidFunctionName | Should -BeTrue -Because "$($config.HandlerType) should have valid function name"
                $contextInfo.TimeMethodsConsistent | Should -BeTrue -Because "$($config.HandlerType) time methods should be consistent"
            }
        }
    }
}
