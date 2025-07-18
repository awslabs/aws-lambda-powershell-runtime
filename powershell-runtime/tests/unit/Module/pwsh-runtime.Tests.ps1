# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for pwsh-runtime module.

.DESCRIPTION
    Tests for module manifest validation, metadata verification, module loading functionality,
    function export verification, and PowerShell version compatibility for the pwsh-runtime module.
    This module provides the core PowerShell runtime functionality for AWS Lambda.
#>

BeforeAll {
    # Import test utilities and assertion helpers
    . "$PSScriptRoot/../../helpers/TestUtilities.ps1"
    . "$PSScriptRoot/../../helpers/AssertionHelpers.ps1"
    . "$PSScriptRoot/../../helpers/TestLambdaRuntimeServer.ps1"

    # Initialize test environment
    Initialize-TestEnvironment

    # Build the module first to merge private functions
    $buildScript = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "build-PwshRuntimeLayer.ps1"
    & $buildScript -SkipRuntimeSetup 6>$null

    # Set paths to the built module
    $script:ModuleManifestPath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "layers/runtimeLayer/modules/pwsh-runtime.psd1"
    $script:ModulePath = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "layers/runtimeLayer/modules/pwsh-runtime.psm1"

    # Expected exported functions
    $script:ExpectedExportedFunctions = @(
        'Set-PSModulePath',
        'Set-LambdaContext',
        'Get-Handler',
        'Set-HandlerEnvironmentVariables',
        'Get-LambdaNextInvocation',
        'Invoke-FunctionHandler',
        'Send-FunctionHandlerResponse',
        'Send-FunctionHandlerError'
    )
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "pwsh-runtime Module" {
    Context "Module Manifest Validation" {
        BeforeAll {
            # Load the manifest data for testing
            $script:ManifestData = Import-PowerShellDataFile -Path $script:ModuleManifestPath
        }

        It "Should have a valid module manifest file" {
            $script:ModuleManifestPath | Should -Exist
            Test-ModuleManifest -Path $script:ModuleManifestPath | Should -Not -BeNullOrEmpty
        }

        It "Should have correct GUID in manifest" {
            $script:ManifestData.GUID | Should -Be 'd8728acd-6b96-4593-99ea-61ef1c7f3b18'
        }

        It "Should have correct version in manifest" {
            $script:ManifestData.ModuleVersion | Should -Be '0.6'
        }

        It "Should have correct author in manifest" {
            $script:ManifestData.Author | Should -Be 'Amazon.com, Inc'
        }

        It "Should have correct company name in manifest" {
            $script:ManifestData.CompanyName | Should -Be 'Amazon Web Services'
        }

        It "Should have correct description in manifest" {
            $script:ManifestData.Description | Should -Be 'The PowerShell custom runtime for AWS Lambda makes it even easier easy to run Lambda functions written in PowerShell.'
        }

        It "Should have correct copyright in manifest" {
            $script:ManifestData.Copyright | Should -Be '(c) 2022 Amazon Web Services. All rights reserved.'
        }

        It "Should specify PowerShell Core compatibility" {
            $script:ManifestData.CompatiblePSEditions | Should -Contain 'Core'
        }

        It "Should have correct PowerShell version requirement" {
            $script:ManifestData.PowerShellVersion | Should -Be '6.0'
        }

        It "Should have correct root module specified" {
            $script:ManifestData.RootModule | Should -Be 'pwsh-runtime.psm1'
        }

        It "Should have correct license URI" {
            $script:ManifestData.PrivateData.PSData.LicenseUri | Should -Be 'https://github.com/awslabs/aws-lambda-powershell-runtime/blob/main/LICENSE'
        }

        It "Should have correct project URI" {
            $script:ManifestData.PrivateData.PSData.ProjectUri | Should -Be 'https://github.com/awslabs/aws-lambda-powershell-runtime'
        }

        It "Should have correct tags" {
            $script:ManifestData.PrivateData.PSData.Tags | Should -Contain 'AWS'
            $script:ManifestData.PrivateData.PSData.Tags | Should -Contain 'Lambda'
        }
    }

    Context "Module Loading and Import Functionality" {
        BeforeEach {
            # Remove module if already loaded to test fresh import
            if (Get-Module -Name 'pwsh-runtime' -ErrorAction SilentlyContinue) {
                Remove-Module -Name 'pwsh-runtime' -Force
            }
        }

        AfterEach {
            # Clean up loaded module
            if (Get-Module -Name 'pwsh-runtime' -ErrorAction SilentlyContinue) {
                Remove-Module -Name 'pwsh-runtime' -Force
            }
        }

        It "Should import module successfully from built location" {
            { Import-Module $script:ModuleManifestPath -Force } | Should -Not -Throw
            Get-Module -Name 'pwsh-runtime' | Should -Not -BeNullOrEmpty
        }

        It "Should have correct module name after import" {
            Import-Module $script:ModuleManifestPath -Force
            $module = Get-Module -Name 'pwsh-runtime'
            $module.Name | Should -Be 'pwsh-runtime'
        }

        It "Should have correct module version after import" {
            Import-Module $script:ModuleManifestPath -Force
            $module = Get-Module -Name 'pwsh-runtime'
            $module.Version | Should -Be '0.6'
        }

        It "Should have correct module GUID after import" {
            Import-Module $script:ModuleManifestPath -Force
            $module = Get-Module -Name 'pwsh-runtime'
            $module.Guid | Should -Be 'd8728acd-6b96-4593-99ea-61ef1c7f3b18'
        }

        It "Should have correct module path after import" {
            Import-Module $script:ModuleManifestPath -Force
            $module = Get-Module -Name 'pwsh-runtime'
            # Module.Path points to the .psm1 file, not the .psd1 manifest
            $module.Path | Should -Be $script:ModulePath
        }

        It "Should have correct module base after import" {
            Import-Module $script:ModuleManifestPath -Force
            $module = Get-Module -Name 'pwsh-runtime'
            $expectedBase = Split-Path -Parent $script:ModuleManifestPath
            $module.ModuleBase | Should -Be $expectedBase
        }
    }

    Context "Function Export Verification" {
        BeforeAll {
            # Import module for function export testing
            Import-Module $script:ModuleManifestPath -Force
            $script:ImportedModule = Get-Module -Name 'pwsh-runtime'
        }

        AfterAll {
            # Clean up loaded module
            if (Get-Module -Name 'pwsh-runtime' -ErrorAction SilentlyContinue) {
                Remove-Module -Name 'pwsh-runtime' -Force
            }
        }

        It "Should export exactly 8 functions" {
            $script:ImportedModule.ExportedFunctions.Count | Should -Be 8
        }

        It "Should export all expected functions" {
            foreach ($expectedFunction in $script:ExpectedExportedFunctions) {
                $script:ImportedModule.ExportedFunctions.Keys | Should -Contain $expectedFunction
            }
        }

        It "Should export <FunctionName> function" -ForEach @(
            @{ FunctionName = 'Set-PSModulePath' }
            @{ FunctionName = 'Set-LambdaContext' }
            @{ FunctionName = 'Get-Handler' }
            @{ FunctionName = 'Set-HandlerEnvironmentVariables' }
            @{ FunctionName = 'Get-LambdaNextInvocation' }
            @{ FunctionName = 'Invoke-FunctionHandler' }
            @{ FunctionName = 'Send-FunctionHandlerResponse' }
            @{ FunctionName = 'Send-FunctionHandlerError' }
        ) {
            $script:ImportedModule.ExportedFunctions.Keys | Should -Contain $FunctionName
            Get-Command -Module 'pwsh-runtime' -Name $FunctionName | Should -Not -BeNullOrEmpty
        }

        It "Should not export any cmdlets" {
            $script:ImportedModule.ExportedCmdlets.Count | Should -Be 0
        }

        It "Should not export any variables" {
            $script:ImportedModule.ExportedVariables.Count | Should -Be 0
        }

        It "Should not export any aliases" {
            $script:ImportedModule.ExportedAliases.Count | Should -Be 0
        }
    }

    Context "Function Availability and Basic Functionality" {
        BeforeAll {
            # Import module for function testing
            Import-Module $script:ModuleManifestPath -Force
        }

        AfterAll {
            # Clean up loaded module
            if (Get-Module -Name 'pwsh-runtime' -ErrorAction SilentlyContinue) {
                Remove-Module -Name 'pwsh-runtime' -Force
            }
        }

        It "Should be able to call Set-PSModulePath function" {
            { pwsh-runtime\Set-PSModulePath } | Should -Not -Throw
        }

        It "Should be able to call Get-Handler function with valid handler" {
            $env:_HANDLER = 'test.ps1'
            $env:LAMBDA_TASK_ROOT = '/tmp'
            { pwsh-runtime\Get-Handler } | Should -Not -Throw
        }

        It "Should be able to call Set-HandlerEnvironmentVariables function" {
            $testHeaders = @{
                'Lambda-Runtime-Aws-Request-Id' = 'test-request-id'
                'Lambda-Runtime-Deadline-Ms'    = '1640995200000'
            }
            { pwsh-runtime\Set-HandlerEnvironmentVariables $testHeaders } | Should -Not -Throw
        }

        It "Should have all functions with proper command type" {
            foreach ($functionName in $script:ExpectedExportedFunctions) {
                $command = Get-Command -Module 'pwsh-runtime' -Name $functionName
                $command.CommandType | Should -Be 'Function'
                $command.ModuleName | Should -Be 'pwsh-runtime'
            }
        }
    }

    Context "PowerShell Version Compatibility" {
        BeforeAll {
            # Import module for compatibility testing
            Import-Module $script:ModuleManifestPath -Force
        }

        AfterAll {
            # Clean up loaded module
            if (Get-Module -Name 'pwsh-runtime' -ErrorAction SilentlyContinue) {
                Remove-Module -Name 'pwsh-runtime' -Force
            }
        }

        It "Should be compatible with PowerShell 7.0+" {
            $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 7
        }

        It "Should be compatible with PowerShell Core edition" {
            $PSVersionTable.PSEdition | Should -Be 'Core'
        }

        It "Should work with current PowerShell version" {
            # Test that module loads and functions are available in current PS version
            $module = Get-Module -Name 'pwsh-runtime'
            $module | Should -Not -BeNullOrEmpty
            $module.ExportedFunctions.Count | Should -Be 8
        }

        It "Should have minimum PowerShell version requirement of 6.0" {
            $manifest = Test-ModuleManifest -Path $script:ModuleManifestPath
            $manifest.PowerShellVersion | Should -Be '6.0'
        }

        It "Should specify Core edition compatibility" {
            $manifest = Test-ModuleManifest -Path $script:ModuleManifestPath
            $manifest.CompatiblePSEditions | Should -Contain 'Core'
        }
    }

    Context "Module File Structure and Content" {
        It "Should have module file (.psm1) present" {
            $script:ModulePath | Should -Exist
        }

        It "Should have non-empty module file" {
            (Get-Content $script:ModulePath -Raw).Length | Should -BeGreaterThan 0
        }

        It "Should contain all expected function definitions in module file" {
            $moduleContent = Get-Content $script:ModulePath -Raw
            foreach ($functionName in $script:ExpectedExportedFunctions) {
                $moduleContent | Should -Match "function.*$functionName"
            }
        }

        It "Should have proper PowerShell strict mode set" {
            $moduleContent = Get-Content $script:ModulePath -Raw
            $moduleContent | Should -Match 'Set-PSDebug -Strict'
        }

        It "Should have proper copyright header" {
            $moduleContent = Get-Content $script:ModulePath -Raw
            $moduleContent | Should -Match 'Copyright Amazon\.com, Inc\. or its affiliates\. All Rights Reserved\.'
            $moduleContent | Should -Match 'SPDX-License-Identifier: Apache-2\.0'
        }
    }

    Context "Module Metadata and Properties" {
        BeforeAll {
            # Import module and get manifest for testing
            Import-Module $script:ModuleManifestPath -Force
            $script:TestManifest = Test-ModuleManifest -Path $script:ModuleManifestPath
        }

        AfterAll {
            # Clean up loaded module
            if (Get-Module -Name 'pwsh-runtime' -ErrorAction SilentlyContinue) {
                Remove-Module -Name 'pwsh-runtime' -Force
            }
        }

        It "Should have correct module type" {
            $script:TestManifest.ModuleType | Should -Be 'Manifest'
        }

        It "Should have correct access mode" {
            $script:TestManifest.AccessMode | Should -Be 'ReadWrite'
        }

        It "Should have correct exported function count in manifest" {
            $script:TestManifest.ExportedFunctions.Count | Should -Be 8
        }

        It "Should have no exported cmdlets in manifest" {
            $script:TestManifest.ExportedCmdlets.Count | Should -Be 0
        }

        It "Should have no exported variables in manifest" {
            $script:TestManifest.ExportedVariables.Count | Should -Be 0
        }

        It "Should have no exported aliases in manifest" {
            $script:TestManifest.ExportedAliases.Count | Should -Be 0
        }

        It "Should have correct module base path" {
            $expectedBase = Split-Path -Parent $script:ModuleManifestPath
            $script:TestManifest.ModuleBase | Should -Be $expectedBase
        }
    }
}