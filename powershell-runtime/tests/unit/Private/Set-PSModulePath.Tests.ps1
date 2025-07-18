# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Set-PSModulePath private function.

.DESCRIPTION
    Tests the Set-PSModulePath function which configures the PSModulePath environment
    variable to include PowerShell runtime modules, Lambda layers modules, and function
    package modules in the correct order for AWS Lambda PowerShell runtime.
#>

param(
    # When true, test against built module instead of source files (default: test source files)
    [switch]$TestBuiltModule = $false
)

BeforeAll {
    # Import test utilities and assertion helpers
    . "$PSScriptRoot/../../helpers/TestUtilities.ps1"
    . "$PSScriptRoot/../../helpers/AssertionHelpers.ps1"

    # Initialize test environment
    Initialize-TestEnvironment

    # Import the runtime module using the appropriate mode
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Set-PSModulePath"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Set-PSModulePath" {
    BeforeEach {
        # Store original PSModulePath for restoration
        $script:OriginalPSModulePath = $env:PSModulePath

        # Set default test environment variables
        $env:LAMBDA_TASK_ROOT = "/var/task"
        $env:POWERSHELL_RUNTIME_VERBOSE = $null
    }

    AfterEach {
        # Restore original PSModulePath
        $env:PSModulePath = $script:OriginalPSModulePath
    }

    Context "When configuring PSModulePath with default settings" {
        It "Should set PSModulePath with correct paths in proper order" {
            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $env:PSModulePath | Should -Not -BeNullOrEmpty

            # Split the path and verify order
            $paths = $env:PSModulePath -split ':'
            $paths.Count | Should -BeGreaterOrEqual 3

            # Verify the three required paths are present in correct order
            Assert-PathEquals -Actual $paths[0] -Expected '/opt/powershell/modules'
            Assert-PathEquals -Actual $paths[1] -Expected '/opt/modules'
            Assert-PathEquals -Actual $paths[2] -Expected '/var/task/modules'
        }

        It "Should include <PathDescription> at position <Position>" -ForEach @(
            @{ PathDescription = 'PowerShell runtime modules path'; Position = 0; ExpectedPath = '/opt/powershell/modules' }
            @{ PathDescription = 'Lambda layers modules path'; Position = 1; ExpectedPath = '/opt/modules' }
            @{ PathDescription = 'function package modules path'; Position = 2; ExpectedPath = '/var/task/modules' }
        ) {
            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[$Position] -Expected $ExpectedPath
        }

        It "Should use colon as path separator" {
            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $env:PSModulePath | Should -Match ':'
            $env:PSModulePath | Should -Not -Match ';'
        }
    }

    Context "When LAMBDA_TASK_ROOT environment variable is customized" {
        It "Should use custom LAMBDA_TASK_ROOT for function package modules path" {
            # Arrange
            $env:LAMBDA_TASK_ROOT = "/custom/task/root"

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[2] -Expected '/custom/task/root/modules'
        }

        It "Should handle LAMBDA_TASK_ROOT with trailing slash" {
            # Arrange
            $env:LAMBDA_TASK_ROOT = "/custom/task/root/"

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[2] -Expected '/custom/task/root/modules'
        }



        It "Should handle empty LAMBDA_TASK_ROOT" {
            # Arrange
            $env:LAMBDA_TASK_ROOT = ""

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            $paths[2] | Should -Be 'modules'
        }

        It "Should handle null LAMBDA_TASK_ROOT" {
            # Arrange
            $env:LAMBDA_TASK_ROOT = $null

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            $paths[2] | Should -Be 'modules'
        }
    }

    Context "When verbose logging is enabled" {
        BeforeEach {
            # Enable verbose logging
            $script:OriginalVerbose = $env:POWERSHELL_RUNTIME_VERBOSE
            $env:POWERSHELL_RUNTIME_VERBOSE = 'TRUE'
        }

        AfterEach {
            # Restore original verbose setting
            $env:POWERSHELL_RUNTIME_VERBOSE = $script:OriginalVerbose
        }

        It "Should not throw errors when verbose logging is enabled" {
            # Act & Assert - Use 6>$null to redirect console output when verbose logging is enabled
            { pwsh-runtime\Set-PSModulePath 6>$null } | Should -Not -Throw
        }

        It "Should still set PSModulePath correctly with verbose logging" {
            # Act - Use 6>$null to redirect console output when verbose logging is enabled
            pwsh-runtime\Set-PSModulePath 6>$null

            # Assert
            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[0] -Expected '/opt/powershell/modules'
            Assert-PathEquals -Actual $paths[1] -Expected '/opt/modules'
            Assert-PathEquals -Actual $paths[2] -Expected '/var/task/modules'
        }
    }

    Context "When verbose logging is disabled" {
        BeforeEach {
            # Explicitly disable verbose logging
            $script:OriginalVerbose = $env:POWERSHELL_RUNTIME_VERBOSE
            $env:POWERSHELL_RUNTIME_VERBOSE = 'FALSE'
        }

        AfterEach {
            # Restore original verbose setting
            $env:POWERSHELL_RUNTIME_VERBOSE = $script:OriginalVerbose
        }

        It "Should work correctly when verbose logging is explicitly disabled" {
            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[0] -Expected '/opt/powershell/modules'
            Assert-PathEquals -Actual $paths[1] -Expected '/opt/modules'
            Assert-PathEquals -Actual $paths[2] -Expected '/var/task/modules'
        }
    }

    Context "When testing PSModulePath configuration order" {
        It "Should prioritize <FirstPath> over <SecondPath>" -ForEach @(
            @{ FirstPath = 'PowerShell runtime modules'; SecondPath = 'layers modules'; FirstPathValue = '/opt/powershell/modules'; SecondPathValue = '/opt/modules' }
            @{ FirstPath = 'layers modules'; SecondPath = 'function package modules'; FirstPathValue = '/opt/modules'; SecondPathValue = '/var/task/modules' }
            @{ FirstPath = 'PowerShell runtime modules'; SecondPath = 'function package modules'; FirstPathValue = '/opt/powershell/modules'; SecondPathValue = '/var/task/modules' }
        ) {
            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'

            # Normalize paths for cross-platform compatibility
            $normalizedPaths = $paths | ForEach-Object { $_ -replace '\\', '/' }
            $firstIndex = [Array]::IndexOf($normalizedPaths, $FirstPathValue)
            $secondIndex = [Array]::IndexOf($normalizedPaths, $SecondPathValue)

            $firstIndex | Should -BeLessThan $secondIndex
        }
    }

    Context "When testing path construction" {
        It "Should use System.IO.Path.Combine for function package modules path" {
            # Arrange
            $env:LAMBDA_TASK_ROOT = "/test/path"

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            $expectedPath = [System.IO.Path]::Combine("/test/path", "modules")
            $paths[2] | Should -Be $expectedPath
        }

        It "Should handle path separators correctly across platforms" {
            # Arrange
            $env:LAMBDA_TASK_ROOT = "/unix/style/path"

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            $paths[2] | Should -Match 'modules$'
        }
    }

    Context "When testing environment variable modification" {
        It "Should completely replace existing PSModulePath" {
            # Arrange
            $env:PSModulePath = "/existing/path1:/existing/path2"

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $env:PSModulePath | Should -Not -Match '/existing/path1'
            $env:PSModulePath | Should -Not -Match '/existing/path2'

            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[0] -Expected '/opt/powershell/modules'
            Assert-PathEquals -Actual $paths[1] -Expected '/opt/modules'
            Assert-PathEquals -Actual $paths[2] -Expected '/var/task/modules'
        }

        It "Should set PSModulePath even when it was previously empty" {
            # Arrange
            $env:PSModulePath = ""

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $env:PSModulePath | Should -Not -BeNullOrEmpty
            $paths = $env:PSModulePath -split ':'
            $paths.Count | Should -Be 3
        }

        It "Should set PSModulePath even when it was previously null" {
            # Arrange
            $env:PSModulePath = $null

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $env:PSModulePath | Should -Not -BeNullOrEmpty
            $paths = $env:PSModulePath -split ':'
            $paths.Count | Should -Be 3
        }
    }

    Context "When testing function behavior consistency" {
        It "Should produce identical results when called multiple times" {
            # Act
            pwsh-runtime\Set-PSModulePath
            $firstResult = $env:PSModulePath

            pwsh-runtime\Set-PSModulePath
            $secondResult = $env:PSModulePath

            # Assert
            $secondResult | Should -Be $firstResult
        }

        It "Should not accumulate paths when called multiple times" {
            # Act
            pwsh-runtime\Set-PSModulePath
            $firstPaths = ($env:PSModulePath -split ':').Count

            pwsh-runtime\Set-PSModulePath
            $secondPaths = ($env:PSModulePath -split ':').Count

            # Assert
            $secondPaths | Should -Be $firstPaths
            $secondPaths | Should -Be 3
        }
    }

    Context "When testing edge cases" {
        It "Should handle special characters in LAMBDA_TASK_ROOT" {
            # Arrange
            $env:LAMBDA_TASK_ROOT = "/path with spaces/and-dashes_and.dots"

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[2] -Expected '/path with spaces/and-dashes_and.dots/modules'
        }

        It "Should handle very long LAMBDA_TASK_ROOT path" {
            # Arrange
            $longPath = "/very/long/path/" + ("directory/" * 20) + "final"
            $env:LAMBDA_TASK_ROOT = $longPath

            # Act
            pwsh-runtime\Set-PSModulePath

            # Assert
            $paths = $env:PSModulePath -split ':'
            Assert-PathEquals -Actual $paths[2] -Expected "$longPath/modules"
        }
    }

    Context "When testing return behavior" {
        It "Should not return any value" {
            # Act
            $result = pwsh-runtime\Set-PSModulePath

            # Assert
            $result | Should -BeNullOrEmpty
        }

        It "Should be a void function" {
            # Act & Assert
            $output = pwsh-runtime\Set-PSModulePath 2>&1
            $output | Should -BeNullOrEmpty
        }
    }
}
