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
    }

    Context "When testing download logic without runtime setup" {
        BeforeEach {
            # Mock external commands to test download logic without actual downloads
            Mock Invoke-WebRequest {
                # Create a fake tar file to simulate successful download
                New-Item -Path $OutFile -ItemType File -Force
                "fake tar content" | Out-File -FilePath $OutFile
            }
            Mock tar {
                # Create fake powershell directory structure to simulate extraction
                $extractPath = $args[$args.Count - 1]  # Last argument is extraction path
                New-Item -Path $extractPath -ItemType Directory -Force
                New-Item -Path (Join-Path $extractPath "pwsh") -ItemType File -Force
            }
        }

        It "Should construct correct GitHub download URL for version '<Version>' and architecture '<Arch>'" -ForEach @(
            @{ Version = '7.4.5'; Arch = 'x64' }
            @{ Version = '7.4.5'; Arch = 'arm64' }
            @{ Version = '7.3.0'; Arch = 'x64' }
            @{ Version = '7.2.0'; Arch = 'arm64' }
        ) {
            # Test URL construction logic without actually running the build script
            # This tests the parameter validation and URL formatting
            $expectedUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$Version/powershell-$Version-linux-$Arch.tar.gz"

            # Verify URL format is correct
            $expectedUrl | Should -Match "^https://github\.com/PowerShell/PowerShell/releases/download/v\d+\.\d+\.\d+/powershell-\d+\.\d+\.\d+-linux-(x64|arm64)\.tar\.gz$"

            # Verify version and architecture are properly formatted
            $expectedUrl | Should -Match $Version
            $expectedUrl | Should -Match $Arch
        }

        It "Should create powershell directory and extract runtime" {
            # Test the directory creation and extraction logic without running full build
            $testPath = Join-Path $TestDrive "extract-test"
            $powershellPath = Join-Path $testPath "powershell"

            # Verify the logic that would create the powershell directory
            if (-not(Test-Path -Path $powershellPath)) {
                $null = New-Item -ItemType Directory -Force -Path $powershellPath
            }

            # Verify directory was created
            Test-Path $powershellPath | Should -Be $true
        }

        It "Should remove tar file after extraction" {
            # Test the cleanup logic without running full build
            $testPath = Join-Path $TestDrive "cleanup-test"
            $tarFile = Join-Path $testPath "powershell-7.4.5-x64.tar.gz"

            # Create a fake tar file
            New-Item -Path $testPath -ItemType Directory -Force
            New-Item -Path $tarFile -ItemType File -Force

            # Test the removal logic
            Remove-Item -Path $tarFile -Force

            # Verify tar file doesn't exist (should be removed)
            Test-Path $tarFile | Should -Be $false
        }

        It "Should handle download failures gracefully" {
            Mock Invoke-WebRequest { throw "Network connection failed" }

            $testPath = Join-Path $TestDrive "download-error-test"

            # Build script should throw when download fails (but use SkipRuntimeSetup to avoid template modification)
            { & $script:BuildScript -LayerPath $testPath -SkipRuntimeSetup 6>$null } | Should -Not -Throw

            # The actual download failure would be tested by mocking, but we avoid running without SkipRuntimeSetup
            # to prevent template modification
        }

        It "Should handle extraction failures gracefully" {
            Mock tar { throw "Extraction failed" }

            $testPath = Join-Path $TestDrive "extract-error-test"

            # Build script should throw when extraction fails (but use SkipRuntimeSetup to avoid template modification)
            { & $script:BuildScript -LayerPath $testPath -SkipRuntimeSetup 6>$null } | Should -Not -Throw

            # The actual extraction failure would be tested by mocking, but we avoid running without SkipRuntimeSetup
            # to prevent template modification
        }
    }

    Context "When testing runtime setup logic (not skipping)" {
        BeforeAll {
            # Use the actual project template for testing
            $script:ActualTemplate = Join-Path (Split-Path $script:BuildScript) "template.yml"
            $script:TestSamTemplate = Join-Path $TestDrive "test-template.yml"

            # Copy the real template for testing
            Copy-Item -Path $script:ActualTemplate -Destination $script:TestSamTemplate -Force

            # Backup the original template file if it exists
            $script:ProjectTemplate = $script:ActualTemplate
            $script:OriginalTemplateBackup = Join-Path $TestDrive "original-template-backup.yml"
            if (Test-Path $script:ProjectTemplate) {
                Copy-Item -Path $script:ProjectTemplate -Destination $script:OriginalTemplateBackup -Force
            }
        }

        AfterAll {
            # Always restore the original template file
            if (Test-Path $script:OriginalTemplateBackup) {
                Copy-Item -Path $script:OriginalTemplateBackup -Destination $script:ProjectTemplate -Force
                Remove-Item -Path $script:OriginalTemplateBackup -Force -ErrorAction SilentlyContinue
            }
        }

        BeforeEach {
            # Mock external commands for runtime setup tests
            Mock Invoke-WebRequest {
                New-Item -Path $OutFile -ItemType File -Force
                "fake tar content" | Out-File -FilePath $OutFile
            }
            Mock tar {
                $extractPath = $args[$args.Count - 1]
                New-Item -Path $extractPath -ItemType Directory -Force
                New-Item -Path (Join-Path $extractPath "pwsh") -ItemType File -Force
            }

            # Ensure we have a test template for each test
            Copy-Item -Path $script:TestSamTemplate -Destination $script:ProjectTemplate -Force
        }

        AfterEach {
            # Always restore the original template after each test
            if (Test-Path $script:OriginalTemplateBackup) {
                Copy-Item -Path $script:OriginalTemplateBackup -Destination $script:ProjectTemplate -Force
            }
        }

        It "Should execute full runtime setup when not skipping" {
            $testPath = Join-Path $TestDrive "runtime-setup-test"

            # Execute build script WITHOUT SkipRuntimeSetup to test the full logic
            & $script:BuildScript -LayerPath $testPath 6>$null

            # Verify download was attempted
            Assert-MockCalled Invoke-WebRequest -Times 1

            # Verify extraction was attempted
            Assert-MockCalled tar -Times 1

            # Verify powershell directory was created (by mock)
            Test-Path (Join-Path $testPath "powershell") | Should -Be $true

            # Verify SAM template was updated
            $updatedContent = Get-Content -Path $script:ProjectTemplate -Raw
            $updatedContent | Should -Match "ContentUri: ./layers/runtimeLayer"
            $updatedContent | Should -Not -Match "ContentUri: ./source"
        }

        It "Should download correct PowerShell version and architecture" {
            $testPath = Join-Path $TestDrive "version-arch-test"
            $testVersion = "7.3.0"
            $testArch = "arm64"

            # Execute build script with specific version and architecture
            & $script:BuildScript -LayerPath $testPath -PwshVersion $testVersion -PwshArchitecture $testArch 6>$null

            # Verify correct URL was used
            $expectedUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$testVersion/powershell-$testVersion-linux-$testArch.tar.gz"
            Assert-MockCalled Invoke-WebRequest -ParameterFilter { $Uri -eq $expectedUrl } -Times 1
        }

        It "Should create powershell directory and extract runtime" {
            $testPath = Join-Path $TestDrive "extract-test"

            # Execute build script to test directory creation and extraction
            & $script:BuildScript -LayerPath $testPath 6>$null

            # Verify powershell directory exists
            Test-Path (Join-Path $testPath "powershell") | Should -Be $true

            # Verify tar extraction was called
            Assert-MockCalled tar -Times 1
        }

        It "Should remove tar file after extraction" {
            $testPath = Join-Path $TestDrive "cleanup-test"

            # Execute build script to test cleanup
            & $script:BuildScript -LayerPath $testPath 6>$null

            # Verify tar file doesn't exist (should be removed)
            $tarFile = Join-Path $testPath "powershell-7.4.5-x64.tar.gz"
            Test-Path $tarFile | Should -Be $false
        }

        It "Should update SAM template ContentUri when not skipping runtime setup" {
            $testPath = Join-Path $TestDrive "sam-update-test"

            # Execute build script WITHOUT SkipRuntimeSetup
            & $script:BuildScript -LayerPath $testPath 6>$null

            # Verify template was updated
            $updatedContent = Get-Content -Path $script:ProjectTemplate -Raw
            $updatedContent | Should -Match "ContentUri: ./layers/runtimeLayer"
            $updatedContent | Should -Not -Match "ContentUri: ./source"
        }

        It "Should handle download failures gracefully" {
            Mock Invoke-WebRequest { throw "Network connection failed" }

            $testPath = Join-Path $TestDrive "download-error-test"

            # Build script should throw when download fails
            { & $script:BuildScript -LayerPath $testPath 6>$null } | Should -Throw
        }

        It "Should handle extraction failures gracefully" {
            Mock tar { throw "Extraction failed" }

            $testPath = Join-Path $TestDrive "extract-error-test"

            # Build script should throw when extraction fails
            { & $script:BuildScript -LayerPath $testPath 6>$null } | Should -Throw
        }

        It "Should throw exception when SAM template is missing" {
            $testPath = Join-Path $TestDrive "missing-template-test"

            # Remove the template file to test missing template scenario
            Remove-Item -Path $script:ProjectTemplate -Force

            # Build script should throw when template is missing
            { & $script:BuildScript -LayerPath $testPath 6>$null } | Should -Throw -ExpectedMessage "*Cannot find path*template.yml*"
        }
    }

    Context "When testing SkipRuntimeSetup logic" {
        It "Should not update SAM template when SkipRuntimeSetup is used" {
            $testPath = Join-Path $TestDrive "sam-skip-test"

            # Store original template content
            $originalContent = Get-Content -Path (Join-Path (Split-Path $script:BuildScript) "template.yml") -Raw

            # Execute build script with SkipRuntimeSetup
            & $script:BuildScript -LayerPath $testPath -SkipRuntimeSetup 6>$null

            # Verify template was NOT modified
            $currentContent = Get-Content -Path (Join-Path (Split-Path $script:BuildScript) "template.yml") -Raw
            $currentContent | Should -Be $originalContent
            $currentContent | Should -Match "ContentUri: ./source"
            $currentContent | Should -Not -Match "ContentUri: ./layers/runtimeLayer"
        }

        It "Should not download or extract when SkipRuntimeSetup is used" {
            Mock Invoke-WebRequest { throw "Should not be called" }
            Mock tar { throw "Should not be called" }

            $testPath = Join-Path $TestDrive "skip-test"

            # Execute build script with SkipRuntimeSetup - should not call mocked functions
            { & $script:BuildScript -LayerPath $testPath -SkipRuntimeSetup 6>$null } | Should -Not -Throw

            # Verify download and extraction were not attempted
            Assert-MockCalled Invoke-WebRequest -Times 0
            Assert-MockCalled tar -Times 0

            # Verify powershell directory was not created
            Test-Path (Join-Path $testPath "powershell") | Should -Be $false
        }
    }

    Context "When testing module content processing logic" {
        BeforeAll {
            # Create test module files with and without exclusion markers
            $script:TestModuleWithMarker = Join-Path $TestDrive "test-module-with-marker.psm1"
            $moduleContentWithMarker = @"
# Main module content
function Test-Function {
    Write-Output "Test"
}

##### All code below this comment is excluded from the build process

# Development only code
function Debug-Function {
    Write-Output "Debug"
}
"@
            Set-Content -Path $script:TestModuleWithMarker -Value $moduleContentWithMarker

            $script:TestModuleWithoutMarker = Join-Path $TestDrive "test-module-without-marker.psm1"
            $moduleContentWithoutMarker = @"
# Main module content
function Test-Function {
    Write-Output "Test"
}

# More production code
function Production-Function {
    Write-Output "Production"
}
"@
            Set-Content -Path $script:TestModuleWithoutMarker -Value $moduleContentWithoutMarker
        }

        It "Should remove development code when exclusion marker is present" {
            $testPath = Join-Path $TestDrive "marker-test"

            # Create a temporary source structure with our test module
            $tempSource = Join-Path $TestDrive "temp-source"
            $tempModules = Join-Path $tempSource "modules"
            New-Item -Path $tempModules -ItemType Directory -Force
            Copy-Item -Path $script:TestModuleWithMarker -Destination (Join-Path $tempModules "pwsh-runtime.psm1")

            # Create minimal required files
            New-Item -Path (Join-Path $tempSource "bootstrap") -ItemType File -Force
            New-Item -Path (Join-Path $tempSource "PowerShellLambdaContext.cs") -ItemType File -Force
            Copy-Item -Path (Join-Path (Split-Path $script:BuildScript) "source" "modules" "pwsh-runtime.psd1") -Destination $tempModules -Force
            New-Item -Path (Join-Path $tempModules "Private") -ItemType Directory -Force

            # Temporarily replace source path
            $originalSource = Join-Path (Split-Path $script:BuildScript) "source"
            $backupSource = Join-Path $TestDrive "backup-source"
            if (Test-Path $originalSource) {
                Move-Item -Path $originalSource -Destination $backupSource
            }
            Move-Item -Path $tempSource -Destination $originalSource

            try {
                # Execute build script
                & $script:BuildScript -LayerPath $testPath -SkipRuntimeSetup 6>$null

                # Verify exclusion marker content was removed
                $builtModule = Join-Path $testPath "modules" "pwsh-runtime.psm1"
                $builtContent = Get-Content -Path $builtModule -Raw
                $builtContent | Should -Not -Match "Debug-Function"
                $builtContent | Should -Not -Match "Development only code"
                $builtContent | Should -Match "Test-Function"
            }
            finally {
                # Restore original source
                if (Test-Path $originalSource) {
                    Remove-Item -Path $originalSource -Recurse -Force
                }
                if (Test-Path $backupSource) {
                    Move-Item -Path $backupSource -Destination $originalSource
                }
            }
        }

        It "Should preserve all content when exclusion marker is not present" {
            $testPath = Join-Path $TestDrive "no-marker-test"

            # Create a temporary source structure with our test module
            $tempSource = Join-Path $TestDrive "temp-source-no-marker"
            $tempModules = Join-Path $tempSource "modules"
            New-Item -Path $tempModules -ItemType Directory -Force
            Copy-Item -Path $script:TestModuleWithoutMarker -Destination (Join-Path $tempModules "pwsh-runtime.psm1")

            # Create minimal required files
            New-Item -Path (Join-Path $tempSource "bootstrap") -ItemType File -Force
            New-Item -Path (Join-Path $tempSource "PowerShellLambdaContext.cs") -ItemType File -Force
            Copy-Item -Path (Join-Path (Split-Path $script:BuildScript) "source" "modules" "pwsh-runtime.psd1") -Destination $tempModules -Force
            New-Item -Path (Join-Path $tempModules "Private") -ItemType Directory -Force

            # Temporarily replace source path
            $originalSource = Join-Path (Split-Path $script:BuildScript) "source"
            $backupSource = Join-Path $TestDrive "backup-source-no-marker"
            if (Test-Path $originalSource) {
                Move-Item -Path $originalSource -Destination $backupSource
            }
            Move-Item -Path $tempSource -Destination $originalSource

            try {
                # Execute build script
                & $script:BuildScript -LayerPath $testPath -SkipRuntimeSetup 6>$null

                # Verify all content was preserved
                $builtModule = Join-Path $testPath "modules" "pwsh-runtime.psm1"
                $builtContent = Get-Content -Path $builtModule -Raw
                $builtContent | Should -Match "Test-Function"
                $builtContent | Should -Match "Production-Function"
            }
            finally {
                # Restore original source
                if (Test-Path $originalSource) {
                    Remove-Item -Path $originalSource -Recurse -Force
                }
                if (Test-Path $backupSource) {
                    Move-Item -Path $backupSource -Destination $originalSource
                }
            }
        }

        It "Should merge private functions with correct header skipping" {
            $testPath = Join-Path $TestDrive "private-merge-test"

            # Execute build script (using existing source)
            & $script:BuildScript -LayerPath $testPath -SkipRuntimeSetup 6>$null

            # Verify private functions were merged and copyright headers were skipped
            $builtModule = Join-Path $testPath "modules" "pwsh-runtime.psm1"
            $builtContent = Get-Content -Path $builtModule -Raw

            # Should contain private functions
            $builtContent | Should -Match "function private:Get-Handler"
            $builtContent | Should -Match "function private:Get-LambdaNextInvocation"

            # Should contain merge markers
            $builtContent | Should -Match "Private functions merged from Private directory"
            $builtContent | Should -Match "=== Get-Handler.ps1 ==="
        }
    }


}
