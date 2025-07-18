# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for Get-Handler private function.

.DESCRIPTION
    Tests the Get-Handler function which parses the _HANDLER environment variable
    and determines the handler type (Script, Function, Module) along with associated
    properties like file paths, module names, and function names.
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
    Import-RuntimeModuleForTesting -TestBuiltModule:$TestBuiltModule -FunctionName "Get-Handler"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "Get-Handler" {
    BeforeEach {
        # Clear any existing _HANDLER environment variable
        $env:_HANDLER = $null
        $env:LAMBDA_TASK_ROOT = "/var/task"
        $env:POWERSHELL_RUNTIME_VERBOSE = $null
    }

    Context "When handler type is Script" {
        It "Should detect script handler with .ps1 extension" {
            # Arrange
            $env:_HANDLER = "handler.ps1"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.handlerType | Should -Be 'Script'
            $result.scriptFileName | Should -Be "handler.ps1"
            $result.scriptFilePath | Should -Be "/var/task/handler.ps1"
            $result.PSObject.Properties['functionName'] | Should -BeNullOrEmpty
            $result.PSObject.Properties['moduleName'] | Should -BeNullOrEmpty
        }

        It "Should handle script handler with complex filename" {
            # Arrange
            $env:_HANDLER = "my-complex-handler.ps1"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Script'
            $result.scriptFileName | Should -Be "my-complex-handler.ps1"
            $result.scriptFilePath | Should -Be "/var/task/my-complex-handler.ps1"
        }

        It "Should use LAMBDA_TASK_ROOT environment variable for script path" {
            # Arrange
            $env:_HANDLER = "test.ps1"
            $env:LAMBDA_TASK_ROOT = "/custom/task/root"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.scriptFilePath | Should -Be "/custom/task/root/test.ps1"
        }

        It "Should handle script handler with subdirectory path" {
            # Arrange
            $env:_HANDLER = "subfolder/handler.ps1"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Script'
            $result.scriptFileName | Should -Be "subfolder/handler.ps1"
            $result.scriptFilePath | Should -Be "/var/task/subfolder/handler.ps1"
        }
    }

    Context "When handler type is Function" {
        It "Should detect function handler with script and function name" {
            # Arrange
            $env:_HANDLER = "handler.ps1::MyFunction"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.handlerType | Should -Be 'Function'
            $result.scriptFileName | Should -Be "handler.ps1"
            $result.scriptFilePath | Should -Be "/var/task/handler.ps1"
            $result.functionName | Should -Be "MyFunction"
            $result.PSObject.Properties['moduleName'] | Should -BeNullOrEmpty
        }

        It "Should handle function handler with complex names" {
            # Arrange
            $env:_HANDLER = "my-script-file.ps1::My-Complex-Function-Name"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Function'
            $result.scriptFileName | Should -Be "my-script-file.ps1"
            $result.functionName | Should -Be "My-Complex-Function-Name"
            $result.scriptFilePath | Should -Be "/var/task/my-script-file.ps1"
        }

        It "Should use LAMBDA_TASK_ROOT for function handler script path" {
            # Arrange
            $env:_HANDLER = "handler.ps1::TestFunction"
            $env:LAMBDA_TASK_ROOT = "/custom/path"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.scriptFilePath | Should -Be "/custom/path/handler.ps1"
        }

        It "Should handle function handler with script in subdirectory" {
            # Arrange
            $env:_HANDLER = "lib/utilities.ps1::Get-Data"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Function'
            $result.scriptFileName | Should -Be "lib/utilities.ps1"
            $result.functionName | Should -Be "Get-Data"
            $result.scriptFilePath | Should -Be "/var/task/lib/utilities.ps1"
        }
    }

    Context "When handler type is Module" {
        It "Should detect module handler with module and function name" {
            # Arrange
            $env:_HANDLER = "Module::MyModule::MyFunction"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.handlerType | Should -Be 'Module'
            $result.moduleName | Should -Be "MyModule"
            $result.functionName | Should -Be "MyFunction"
            $result.PSObject.Properties['scriptFileName'] | Should -BeNullOrEmpty
            $result.PSObject.Properties['scriptFilePath'] | Should -BeNullOrEmpty
        }

        It "Should handle module handler with complex names" {
            # Arrange
            $env:_HANDLER = "Module::My-Complex-Module::My-Complex-Function"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Module'
            $result.moduleName | Should -Be "My-Complex-Module"
            $result.functionName | Should -Be "My-Complex-Function"
        }

        It "Should handle module handler with dotted module names" {
            # Arrange
            $env:_HANDLER = "Module::Company.Product.Module::Get-Data"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Module'
            $result.moduleName | Should -Be "Company.Product.Module"
            $result.functionName | Should -Be "Get-Data"
        }
    }

    Context "When handler string is invalid" {
        It "Should throw error for <ErrorScenario>" -ForEach @(
            @{ ErrorScenario = 'empty handler'; Handler = ''; ExpectedError = '*Invalid Lambda Handler*' }
            @{ ErrorScenario = 'null handler'; Handler = $null; ExpectedError = '*Invalid Lambda Handler*' }
            @{ ErrorScenario = 'script with too many parts'; Handler = 'script.ps1::function::extra'; ExpectedError = '*Invalid Lambda Handler: script.ps1::function::extra*' }
            @{ ErrorScenario = 'module with insufficient parts'; Handler = 'Module::OnlyModuleName'; ExpectedError = '*Invalid Lambda Handler: Module::OnlyModuleName*' }
            @{ ErrorScenario = 'module with too many parts'; Handler = 'Module::ModuleName::FunctionName::Extra'; ExpectedError = '*Invalid Lambda Handler: Module::ModuleName::FunctionName::Extra*' }
            @{ ErrorScenario = 'non-ps1 script file'; Handler = 'handler.txt'; ExpectedError = '*Invalid Lambda Handler: handler.txt*' }
            @{ ErrorScenario = 'invalid module format'; Handler = 'NotModule::ModuleName::FunctionName'; ExpectedError = '*Invalid Lambda Handler: NotModule::ModuleName::FunctionName*' }
            @{ ErrorScenario = 'mixed format'; Handler = 'script.ps1::Module::function'; ExpectedError = '*Invalid Lambda Handler: script.ps1::Module::function*' }
        ) {
            # Arrange
            $env:_HANDLER = $Handler

            # Act & Assert
            { pwsh-runtime\Get-Handler } | Should -Throw $ExpectedError
        }
    }

    Context "When using custom handler parameter" {
        It "Should use provided handler parameter instead of environment variable" {
            # Arrange
            $env:_HANDLER = "env-handler.ps1"
            $customHandler = "custom-handler.ps1"

            # Act
            $result = pwsh-runtime\Get-Handler -handler $customHandler

            # Assert
            $result.scriptFileName | Should -Be "custom-handler.ps1"
            $result.scriptFilePath | Should -Be "/var/task/custom-handler.ps1"
        }

        It "Should handle custom function handler parameter" {
            # Arrange
            $env:_HANDLER = "env-handler.ps1"
            $customHandler = "custom.ps1::CustomFunction"

            # Act
            $result = pwsh-runtime\Get-Handler -handler $customHandler

            # Assert
            $result.handlerType | Should -Be 'Function'
            $result.scriptFileName | Should -Be "custom.ps1"
            $result.functionName | Should -Be "CustomFunction"
        }

        It "Should handle custom module handler parameter" {
            # Arrange
            $env:_HANDLER = "env-handler.ps1"
            $customHandler = "Module::CustomModule::CustomFunction"

            # Act
            $result = pwsh-runtime\Get-Handler -handler $customHandler

            # Assert
            $result.handlerType | Should -Be 'Module'
            $result.moduleName | Should -Be "CustomModule"
            $result.functionName | Should -Be "CustomFunction"
        }
    }

    Context "When verbose logging is enabled" {
        BeforeEach {
            $env:POWERSHELL_RUNTIME_VERBOSE = 'TRUE'
        }

        It "Should not throw errors when verbose logging is enabled for <HandlerType> handler" -ForEach @(
            @{ HandlerType = 'script'; Handler = 'verbose-test.ps1'; ExpectedType = 'Script' }
            @{ HandlerType = 'function'; Handler = 'verbose-test.ps1::VerboseFunction'; ExpectedType = 'Function' }
            @{ HandlerType = 'module'; Handler = 'Module::VerboseModule::VerboseFunction'; ExpectedType = 'Module' }
        ) {
            # Arrange
            $env:_HANDLER = $Handler

            # Act & Assert
            $result = pwsh-runtime\Get-Handler 6>$null
            $result.handlerType | Should -Be $ExpectedType
        }
    }

    Context "When testing return object structure" {
        It "Should return PSCustomObject for <HandlerType> handler with correct properties" -ForEach @(
            @{ HandlerType = 'script'; Handler = 'test.ps1'; RequiredProperties = @('handlerType', 'scriptFileName', 'scriptFilePath') }
            @{ HandlerType = 'function'; Handler = 'test.ps1::TestFunction'; RequiredProperties = @('handlerType', 'scriptFileName', 'scriptFilePath', 'functionName') }
            @{ HandlerType = 'module'; Handler = 'Module::TestModule::TestFunction'; RequiredProperties = @('handlerType', 'moduleName', 'functionName') }
        ) {
            # Arrange
            $env:_HANDLER = $Handler

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result | Should -BeOfType [PSCustomObject]
            foreach ($property in $RequiredProperties) {
                $result.PSObject.Properties.Name | Should -Contain $property
            }
        }
    }

    Context "When testing edge cases" {
        It "Should handle handler with multiple dots in filename" {
            # Arrange
            $env:_HANDLER = "my.complex.handler.ps1"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Script'
            $result.scriptFileName | Should -Be "my.complex.handler.ps1"
        }

        It "Should handle function handler with multiple dots in filename" {
            # Arrange
            $env:_HANDLER = "my.complex.handler.ps1::MyFunction"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Function'
            $result.scriptFileName | Should -Be "my.complex.handler.ps1"
            $result.functionName | Should -Be "MyFunction"
        }

        It "Should handle case sensitivity in Module keyword" {
            # Arrange
            $env:_HANDLER = "module::TestModule::TestFunction"

            # Act
            $result = pwsh-runtime\Get-Handler

            # Assert
            $result.handlerType | Should -Be 'Module'
            $result.moduleName | Should -Be "TestModule"
            $result.functionName | Should -Be "TestFunction"
        }

        It "Should throw when whitespace is in handler components" {
            # Arrange
            $env:_HANDLER = " handler.ps1 :: MyFunction "

            # Act & Assert
            { pwsh-runtime\Get-Handler } | Should -Throw
        }
    }
}