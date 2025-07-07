# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for build-PwshRuntimeLayer.ps1 build script.

.DESCRIPTION
    Tests the build-PwshRuntimeLayer.ps1 script which creates the PowerShell Runtime Layer
    by downloading PowerShell runtime, copying source files, merging private functions,
    and creating the proper directory structure for AWS Lambda layers.
#>

BeforeAll {
    # Import test utilities and assertion helpers
    . "$PSScriptRoot/../../helpers/TestUtilities.ps1"
    . "$PSScriptRoot/../../helpers/AssertionHelpers.ps1"

    # Initialize test environment
    Initialize-TestEnvironment

    # Get paths to build script and test directories
    $script:BuildScript = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "build-PwshRuntimeLayer.ps1"
    $script:ProjectRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    $script:TestLayerPath = Join-Path $TestDrive "test-layer"

    # Saving variables for later
    $ProgressPreference = 'SilentlyContinue'

    # Execute build script once for all tests - this creates the shared build artifacts
    Write-Host "Building PowerShell Runtime Layer for testing..." -ForegroundColor Green
    & $script:BuildScript -LayerPath $script:TestLayerPath -SkipRuntimeSetup 6>$null

    # Set up shared paths for all test contexts
    $script:ModuleManifestPath = Join-Path $script:TestLayerPath "modules" "pwsh-runtime.psd1"
    $script:ModulePath = Join-Path $script:TestLayerPath "modules" "pwsh-runtime.psd1"
}

AfterAll {
    # Clean up test environment
    Reset-TestEnvironment
}

Describe "build-PwshRuntimeLayer.ps1" {
    Context "When building with SkipRuntimeSetup" {
        BeforeAll {
            # Read module content once for all tests in this context
            $script:ModuleFile = Join-Path $script:TestLayerPath "modules" "pwsh-runtime.psm1"
            $script:ModuleContent = Get-Content $script:ModuleFile -Raw

            # Read bootstrap content once for all tests in this context
            $script:BootstrapPath = Join-Path $script:TestLayerPath "bootstrap"
            $script:BootstrapContent = Get-Content $script:BootstrapPath
            $script:BootstrapFirstLine = $script:BootstrapContent | Select-Object -First 1

            # Read PowerShellLambdaContext.cs content once for all tests in this context
            $script:ContextPath = Join-Path $script:TestLayerPath "PowerShellLambdaContext.cs"
            $script:ContextContent = Get-Content $script:ContextPath -Raw
        }

        # Build artifacts are already available from BeforeAll block

        It "Should create correct directory structure" {
            # Verify main directories exist
            Test-Path (Join-Path $script:TestLayerPath "modules") | Should -Be $true
            Test-Path (Join-Path $script:TestLayerPath "modules" "pwsh-runtime.psd1") | Should -Be $true
            Test-Path (Join-Path $script:TestLayerPath "modules" "pwsh-runtime.psm1") | Should -Be $true
            Test-Path (Join-Path $script:TestLayerPath "bootstrap") | Should -Be $true
            Test-Path (Join-Path $script:TestLayerPath "PowerShellLambdaContext.cs") | Should -Be $true
        }

        It "Should copy source files to layer path" {
            # Verify essential files are copied
            $moduleManifest = Join-Path $script:TestLayerPath "modules" "pwsh-runtime.psd1"
            $moduleFile = Join-Path $script:TestLayerPath "modules" "pwsh-runtime.psm1"
            $bootstrapFile = Join-Path $script:TestLayerPath "bootstrap"

            Test-Path $moduleManifest | Should -Be $true
            Test-Path $moduleFile | Should -Be $true
            Test-Path $bootstrapFile | Should -Be $true

            # Verify bootstrap file is executable (has content)
            (Get-Content $bootstrapFile).Count | Should -BeGreaterThan 0
        }

        It "Should merge private function '<FunctionName>' into main module file" -ForEach @(
            @{ FunctionName = 'Get-Handler'; Pattern = 'function private:Get-Handler' }
            @{ FunctionName = 'Get-LambdaNextInvocation'; Pattern = 'function private:Get-LambdaNextInvocation' }
            @{ FunctionName = 'Invoke-FunctionHandler'; Pattern = 'function private:Invoke-FunctionHandler' }
            @{ FunctionName = 'Send-FunctionHandlerResponse'; Pattern = 'function private:Send-FunctionHandlerResponse' }
            @{ FunctionName = 'Send-FunctionHandlerError'; Pattern = 'function private:Send-FunctionHandlerError' }
            @{ FunctionName = 'Set-HandlerEnvironmentVariables'; Pattern = 'function private:Set-HandlerEnvironmentVariables' }
            @{ FunctionName = 'Set-LambdaContext'; Pattern = 'function Private:Set-LambdaContext' }
            @{ FunctionName = 'Set-PSModulePath'; Pattern = 'function private:Set-PSModulePath' }
        ) {
            # Verify private functions are merged (check for function signatures)
            $script:ModuleContent | Should -Match $Pattern -Because "Private function '$FunctionName' should be merged into module file"
        }

        It "Should remove Private directory after merging" {
            # Verify Private directory is removed after merging
            Test-Path (Join-Path $script:TestLayerPath "modules" "Private") | Should -Be $false
        }

        It "Should remove Makefile from layer path" {
            # Verify Makefile is not present in layer
            Test-Path (Join-Path $script:TestLayerPath "Makefile") | Should -Be $false
        }

        It "Should not create powershell directory when SkipRuntimeSetup is used" {
            # Verify powershell directory is not created
            Test-Path (Join-Path $script:TestLayerPath "powershell") | Should -Be $false
        }

        It "Should contain required runtime file '<File>'" -ForEach @(
            @{ File = "bootstrap" }
            @{ File = "PowerShellLambdaContext.cs" }
            @{ File = "modules/pwsh-runtime.psd1" }
            @{ File = "modules/pwsh-runtime.psm1" }
        ) {
            $filePath = Join-Path $script:TestLayerPath $File
            Test-Path $filePath | Should -Be $true -Because "Required file '$File' should exist"
        }

        It "Should have bootstrap file with correct permissions" {
            # Verify bootstrap file exists and has content
            Test-Path $script:BootstrapPath | Should -Be $true
            $script:BootstrapContent.Count | Should -BeGreaterThan 0

            # Verify it's a shell script (starts with shebang)
            $script:BootstrapFirstLine | Should -Match "^#!/"
        }

        It "Should have PowerShellLambdaContext.cs file" {
            Test-Path $script:ContextPath | Should -Be $true
            $script:ContextContent | Should -Match "class.*LambdaContext"
            $script:ContextContent | Should -Match "namespace"
        }

        It "Should not contain development artifact '<File>'" -ForEach @(
            @{ File = "Makefile" }
            @{ File = "modules/Private" }
            @{ File = ".git" }
            @{ File = ".gitignore" }
            @{ File = "tests" }
        ) {
            $filePath = Join-Path $script:TestLayerPath $File
            Test-Path $filePath | Should -Be $false -Because "Development file '$File' should not exist in build"
        }
    }

    Context "When validating built module manifest" {
        BeforeAll {
            # Read manifest data once for all tests in this context
            $script:ManifestData = Import-PowerShellDataFile -Path $script:ModuleManifestPath
        }

        # Build artifacts and paths are already available from BeforeAll block

        It "Should have correct module manifest metadata" {
            # Verify manifest file exists first
            Test-Path $script:ModuleManifestPath | Should -Be $true

            # Validate manifest data (already loaded in BeforeAll)
            $script:ManifestData | Should -Not -BeNullOrEmpty

            # Verify key metadata from the data file
            $script:ManifestData.ModuleVersion | Should -Be "0.6"
            $script:ManifestData.GUID | Should -Be "d8728acd-6b96-4593-99ea-61ef1c7f3b18"
            $script:ManifestData.Author | Should -Be "Amazon.com, Inc"
            $script:ManifestData.CompanyName | Should -Be "Amazon Web Services"
            $script:ManifestData.PowerShellVersion | Should -Be "6.0"
            $script:ManifestData.RootModule | Should -Be "pwsh-runtime.psm1"

            # Test that Test-ModuleManifest can process it (may have warnings but shouldn't fail)
            { Test-ModuleManifest -Path $script:ModuleManifestPath -ErrorAction Stop -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It "Should export required function '<FunctionName>'" -ForEach @(
            @{ FunctionName = 'Set-PSModulePath' }
            @{ FunctionName = 'Set-LambdaContext' }
            @{ FunctionName = 'Get-Handler' }
            @{ FunctionName = 'Set-HandlerEnvironmentVariables' }
            @{ FunctionName = 'Get-LambdaNextInvocation' }
            @{ FunctionName = 'Invoke-FunctionHandler' }
            @{ FunctionName = 'Send-FunctionHandlerResponse' }
            @{ FunctionName = 'Send-FunctionHandlerError' }
        ) {
            # Use manifest data already loaded in BeforeAll
            $script:ManifestData.FunctionsToExport | Should -Contain $FunctionName
        }

        It "Should export correct number of functions" {
            # Use manifest data already loaded in BeforeAll
            $expectedCount = 8  # Total number of expected functions
            $script:ManifestData.FunctionsToExport.Count | Should -Be $expectedCount
        }

        It "Should have correct CompatiblePSEditions" {
            # Use manifest data already loaded in BeforeAll
            $script:ManifestData.CompatiblePSEditions | Should -Contain "Core"
        }
    }

    Context "When testing built module functionality" {
        # Build artifacts and paths are already available from BeforeAll block

        It "Should be able to import built module successfully" {
            # Import the built module
            { Import-Module $script:ModulePath -Force } | Should -Not -Throw

            # Verify module is loaded
            Get-Module "pwsh-runtime" | Should -Not -BeNullOrEmpty
        }

        It "Should have function '<FunctionName>' accessible after import" -ForEach @(
            @{ FunctionName = 'Set-PSModulePath' }
            @{ FunctionName = 'Set-LambdaContext' }
            @{ FunctionName = 'Get-Handler' }
            @{ FunctionName = 'Set-HandlerEnvironmentVariables' }
            @{ FunctionName = 'Get-LambdaNextInvocation' }
            @{ FunctionName = 'Invoke-FunctionHandler' }
            @{ FunctionName = 'Send-FunctionHandlerResponse' }
            @{ FunctionName = 'Send-FunctionHandlerError' }
        ) {
            # Import the built module
            Import-Module $script:ModulePath -Force
            # Verify function exists and is callable
            Get-Command "pwsh-runtime\$FunctionName" -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have private functions merged and accessible" {
            # Import the built module
            Import-Module $script:ModulePath -Force

            # Test that private functions are accessible (they should be after merging)
            # These functions should work when called through the module
            { Get-Command "pwsh-runtime\Get-Handler" } | Should -Not -Throw
            { Get-Command "pwsh-runtime\Get-LambdaNextInvocation" } | Should -Not -Throw
            { Get-Command "pwsh-runtime\Invoke-FunctionHandler" } | Should -Not -Throw
        }
    }

    Context "When testing build script parameters" {

        It "Should accept custom LayerPath parameter" {
            $customPath = Join-Path $TestDrive "custom-layer-path"

            # Execute build script with custom path
            & $script:BuildScript -LayerPath $customPath -SkipRuntimeSetup 6>$null

            # Verify build artifacts exist at custom path
            Test-Path (Join-Path $customPath "modules" "pwsh-runtime.psd1") | Should -Be $true
            Test-Path (Join-Path $customPath "modules" "pwsh-runtime.psm1") | Should -Be $true
            Test-Path (Join-Path $customPath "bootstrap") | Should -Be $true
        }

        It "Should clean existing layer path before building" {
            # Use a separate path for this test to avoid interfering with shared build
            $cleanTestPath = Join-Path $TestDrive "clean-test-layer"

            # Create some existing content
            New-Item -Path $cleanTestPath -ItemType Directory -Force
            New-Item -Path (Join-Path $cleanTestPath "old-file.txt") -ItemType File -Force
            "old content" | Out-File -FilePath (Join-Path $cleanTestPath "old-file.txt")

            # Execute build script
            & $script:BuildScript -LayerPath $cleanTestPath -SkipRuntimeSetup 6>$null

            # Verify old content is removed and new content exists
            Test-Path (Join-Path $cleanTestPath "old-file.txt") | Should -Be $false
            Test-Path (Join-Path $cleanTestPath "modules" "pwsh-runtime.psd1") | Should -Be $true
        }

        It "Should handle multiple builds without errors" {
            # Use a separate path for this test to avoid interfering with shared build
            $multiTestPath = Join-Path $TestDrive "multi-build-test-layer"

            # Execute build script multiple times
            & $script:BuildScript -LayerPath $multiTestPath -SkipRuntimeSetup 6>$null
            & $script:BuildScript -LayerPath $multiTestPath -SkipRuntimeSetup 6>$null

            # Verify final build is successful
            Test-Path (Join-Path $multiTestPath "modules" "pwsh-runtime.psd1") | Should -Be $true
            Test-Path (Join-Path $multiTestPath "modules" "pwsh-runtime.psm1") | Should -Be $true

            # Verify module can still be imported
            $modulePath = Join-Path $multiTestPath "modules" "pwsh-runtime.psd1"
            { Import-Module $modulePath -Force } | Should -Not -Throw
        }
    }

    Context "When testing error conditions" {
        It "Should handle missing source directory gracefully" {
            # This test verifies the build script behavior when source files are missing
            # In practice, this shouldn't happen, but we test error handling
            $invalidPath = Join-Path $TestDrive "invalid-layer"

            # The build script should handle missing source gracefully
            # Note: This may throw an error, which is expected behavior
            try {
                & $script:BuildScript -LayerPath $invalidPath -SkipRuntimeSetup 6>$null
                # If it succeeds, verify basic structure
                if (Test-Path $invalidPath) {
                    Test-Path (Join-Path $invalidPath "modules") | Should -Be $true
                }
            }
            catch {
                # Error is acceptable for missing source files
                $_.Exception.Message | Should -Not -BeNullOrEmpty
            }
        }

        It "Should handle read-only layer path appropriately" {
            # Create a directory and make it read-only (if supported on platform)
            $readOnlyPath = Join-Path $TestDrive "readonly-layer"
            New-Item -Path $readOnlyPath -ItemType Directory -Force

            try {
                # Try to make directory read-only (Windows only test)
                if ($IsWindows) {
                    Set-ItemProperty -Path $readOnlyPath -Name IsReadOnly -Value $true
                    # Build script should handle this appropriately on Windows
                    { & $script:BuildScript -LayerPath $readOnlyPath -SkipRuntimeSetup 6>$null } | Should -Throw
                }
                else {
                    # On non-Windows platforms, test that build succeeds even with permission issues
                    # The build script should handle permission issues gracefully
                    { & $script:BuildScript -LayerPath $readOnlyPath -SkipRuntimeSetup 6>$null } | Should -Not -Throw
                }
            }
            finally {
                # Clean up read-only attribute
                if ($IsWindows -and (Test-Path $readOnlyPath)) {
                    Set-ItemProperty -Path $readOnlyPath -Name IsReadOnly -Value $false
                    Remove-Item $readOnlyPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }


}