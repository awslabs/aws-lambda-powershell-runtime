#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Central test runner for PowerShell Lambda Runtime tests

.DESCRIPTION
    This script provides a centralized entry point for executing all tests in the PowerShell Lambda Runtime project.

    Test Modes:
    - Source: Tests source files directly (fast development)
    - BuiltModule: Tests the built/merged module (validation)

.PARAMETER TestType
    Specifies which type of tests to run. Valid values: 'LocalUnit', 'Unit', 'Build', 'Private', 'Integration'
    - LocalUnit: Runs all local unit tests (Build, Module, and Private) - Default
    - Unit: Runs Module and Private unit tests
    - Build: Runs only Build tests
    - Private: Runs only Private unit tests
    - Integration: Runs only integration tests

.PARAMETER Path
    Specifies specific test files or directories to run

.PARAMETER TestBuiltModule
    Test against the built module instead of source files

.PARAMETER CI
    Indicates the script is running in a CI/CD environment

.PARAMETER Coverage
    Enables code coverage analysis

.PARAMETER OutputFormat
    Specifies the output format for test results. Valid values: 'NUnitXml', 'JUnitXml', 'Console'

.PARAMETER DetailedOutput
    Enables detailed Pester output for debugging

.PARAMETER StackName
    Name of the CloudFormation stack for integration tests (default: "powershell-runtime-integration-test-infrastructure")
    Only used when TestType is 'Integration'

.PARAMETER Region
    AWS region for infrastructure deployment (default: "us-east-1")
    Only used when TestType is 'Integration'

.PARAMETER ProfileName
    AWS profile name for authentication
    Only used when TestType is 'Integration'

.EXAMPLE
    ./Invoke-Tests.ps1
    Runs all local unit tests (Build, Module, Private) in Source mode (fastest for development)

.EXAMPLE
    ./Invoke-Tests.ps1 -TestBuiltModule -Coverage
    Runs all local unit tests against built module with coverage analysis

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Private
    Runs only Private unit tests

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Build
    Runs only Build tests

.EXAMPLE
    ./Invoke-Tests.ps1 -Path './tests/unit/Private/Get-Handler.Tests.ps1'
    Runs a specific test file

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Integration
    Runs integration tests with default stack name and region, automatically sets up and cleans up environment

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Integration -StackName "my-test-stack" -Region "us-west-2" -ProfileName "dev"
    Runs integration tests with custom stack, region, and AWS profile

.EXAMPLE
    ./Invoke-Tests.ps1 -CI -OutputFormat NUnitXml
    Runs all tests in CI mode with NUnit XML output
#>

[CmdletBinding()]
param(
    [ValidateSet('LocalUnit', 'Unit', 'Build', 'Private', 'Integration')]
    [string]$TestType = 'LocalUnit',

    [string[]]$Path,
    [switch]$TestBuiltModule,
    [switch]$CI,
    [switch]$Coverage,

    [ValidateSet('NUnitXml', 'JUnitXml', 'Console')]
    [string]$OutputFormat = 'Console',

    [switch]$DetailedOutput,

    # Integration test parameters
    [string]$StackName = "powershell-runtime-integration-test-infrastructure",
    [string]$Region = "us-east-1",
    [string]$ProfileName
)

# Set error action preference for consistent behavior
$ErrorActionPreference = 'Stop'

# Get script directory and project root
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ProjectRoot = Split-Path -Parent $script:ScriptDir
$script:TestRequirementsPath = Join-Path $script:ProjectRoot 'test-requirements.psd1'
$script:CurrentPSModulePath = $env:PSModulePath

# Script-scoped variables for consistent state management
$script:CI = $CI
$script:Coverage = $Coverage
$script:CIStartTime = if ($CI) { Get-Date } else { $null }

if ($script:CI) {
    $TestBuiltModule = $true
    Write-Host "CI mode detected: Automatically enabling TestBuiltModule for validation" -ForegroundColor Yellow
}

Write-Host "PowerShell Runtime Test Runner" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# Handle verbose preference
if ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    $VerbosePreference = 'Continue'
    Write-Verbose "PowerShell verbose output enabled"
}

# Load test configuration
if (Test-Path $script:TestRequirementsPath) {
    Write-Host "Loading test requirements from: $script:TestRequirementsPath" -ForegroundColor Green
    $script:TestConfig = Import-PowerShellDataFile -Path $script:TestRequirementsPath
}
else {
    Write-Warning "Test requirements file not found, using defaults"
    $script:TestConfig = @{
        PrivateData = @{
            TestSettings = @{
                CodeCoverage = @{ Threshold = 80 }
            }
        }
    }
}

function Exit-TestScript {
    param($ExitCode, $ExitMessage)

    $env:PSModulePath = $script:CurrentPSModulePath

    if ($script:CI) {
        exit $ExitCode
    }

    if ($ExitCode -ne 0 -and $ExitMessage) {
        throw $ExitMessage
    }
    elseif ($ExitCode -ne 0) {
        throw "Exiting with exit code $ExitCode"
    }
}

function Initialize-TestFramework {
    Write-Host "Initializing test framework..." -ForegroundColor Yellow

    if (-not (Get-Module -Name Pester -ListAvailable)) {
        Write-Host "Installing Pester..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
    }

    Import-Module Pester -Force
    Write-Host "Pester ready" -ForegroundColor Green
}

function Get-CoveragePaths {
    param($TestPaths, $ProjectRoot, $TestBuiltModule, $TestType)

    # Build tests - only cover build script
    if ($TestType -eq 'Build') {
        $buildScript = Join-Path $ProjectRoot "build-PwshRuntimeLayer.ps1"
        if (Test-Path $buildScript) {
            return @($buildScript)
        }
        else {
            Write-Warning "Build script not found at: $buildScript"
            return @()
        }
    }

    # Private tests - only cover private source functions
    if ($TestType -eq 'Private') {
        $privatePath = Join-Path $ProjectRoot "source/modules/Private"
        if (Test-Path $privatePath) {
            return Get-ChildItem -Path $privatePath -Filter "*.ps1" -Recurse | ForEach-Object { $_.FullName }
        }
        else {
            Write-Warning "Private source path not found at: $privatePath"
            return @()
        }
    }

    # For Unit/LocalUnit tests:
    # - If TestBuiltModule: only cover built module
    # - If source testing: cover all source files
    if ($TestBuiltModule) {
        $builtModule = Join-Path $ProjectRoot "layers/runtimeLayer/modules/pwsh-runtime.psm1"
        if (Test-Path $builtModule) {
            return @($builtModule)
        }
        else {
            Write-Warning "Built module not found at: $builtModule"
            return @()
        }
    }
    else {
        # Source testing - cover all source files
        $sourcePath = Join-Path $ProjectRoot "source/modules"
        if (Test-Path $sourcePath) {
            return Get-ChildItem -Path $sourcePath -Filter "*.ps1" -Recurse | ForEach-Object { $_.FullName }
        }
        else {
            Write-Warning "Source path not found at: $sourcePath"
            return @()
        }
    }
}

function Write-CIDiagnostics {
    param([string]$Phase)

    if (-not $script:CI -or -not $script:CIStartTime) {
        return
    }

    $timeSpan = (Get-Date) - $script:CIStartTime

    $elapsed = [math]::Round($timeSpan.TotalSeconds, 1)
    $unit = "sec"

    Write-Host "CI $Phase - Runtime: ${elapsed}${unit}" -ForegroundColor Cyan
}

function Invoke-CICleanup {
    if (-not $script:CI) {
        return
    }

    Write-Host "CI Cleanup: Starting resource cleanup" -ForegroundColor Yellow

    # Clean up test processes
    Get-Process | Where-Object { $_.ProcessName -like "*Test*" -and $_.Id -ne $PID } | Stop-Process -Force -ErrorAction SilentlyContinue

    # Restore PSModulePath
    $env:PSModulePath = $script:CurrentPSModulePath

    Write-Host "CI Cleanup: Completed" -ForegroundColor Green
}

function Initialize-IntegrationTestEnvironment {
    [CmdletBinding()]
    param(
        [string]$StackName,
        [string]$Region,
        [string]$ProfileName
    )

    Write-Host "Setting up integration test environment..." -ForegroundColor Yellow

    # Import required AWS modules
    Write-Host "Importing required AWS modules..." -ForegroundColor Yellow
    if (-not (Get-Module -Name AWS.Tools.CloudFormation -ListAvailable)) {
        throw "AWS.Tools.CloudFormation module is not installed. Please install it with: Install-Module -Name AWS.Tools.CloudFormation -Force"
    }
    Import-Module AWS.Tools.CloudFormation -ErrorAction Stop
    Write-Host "AWS modules imported successfully" -ForegroundColor Green

    # Set up authentication parameters
    $awsParams = @{
        Region = $Region
    }

    # Add profile if specified
    if ($ProfileName) {
        $awsParams.ProfileName = $ProfileName
    }

    Write-Host "Retrieving stack outputs for $StackName..." -ForegroundColor Yellow

    try {
        $stack = Get-CFNStack -StackName $StackName @awsParams
    }
    catch {
        Write-Error "Failed to retrieve stack information: $_"
        throw "Could not find stack '$StackName'. Make sure the stack exists and you have permission to access it."
    }

    # Convert outputs to environment variables
    $outputCount = 0
    foreach ($output in ($stack.Outputs | Sort-Object -Property OutputKey)) {
        $envVarName = "PWSH_TEST_$($output.OutputKey.ToUpper())"
        Write-Host "Setting $envVarName = $($output.OutputValue)" -ForegroundColor Cyan
        [Environment]::SetEnvironmentVariable($envVarName, $output.OutputValue, "Process")
        $outputCount++
    }

    # Set a flag indicating infrastructure is available
    [Environment]::SetEnvironmentVariable("PWSH_TEST_INFRASTRUCTURE_DEPLOYED", "TRUE", "Process")

    # Set configuration environment variables for use by other scripts/tests
    Write-Host "Setting configuration environment variables..." -ForegroundColor Yellow
    [Environment]::SetEnvironmentVariable("PWSH_TEST_STACK_NAME", $StackName, "Process")
    Write-Host "Setting PWSH_TEST_STACK_NAME = $StackName" -ForegroundColor Cyan

    [Environment]::SetEnvironmentVariable("PWSH_TEST_AWS_REGION", $Region, "Process")
    Write-Host "Setting PWSH_TEST_AWS_REGION = $Region" -ForegroundColor Cyan

    if ($ProfileName) {
        [Environment]::SetEnvironmentVariable("PWSH_TEST_PROFILE_NAME", $ProfileName, "Process")
        Write-Host "Setting PWSH_TEST_PROFILE_NAME = $ProfileName" -ForegroundColor Cyan
    }

    Write-Host "Successfully set $outputCount stack output environment variables for integration tests" -ForegroundColor Green
    Write-Host "Environment variable PWSH_TEST_INFRASTRUCTURE_DEPLOYED has been set to TRUE" -ForegroundColor Green
    Write-Host "Configuration environment variables (PWSH_TEST_STACK_NAME, PWSH_TEST_AWS_REGION$(if ($ProfileName) { ', PWSH_TEST_PROFILE_NAME' })) have been set" -ForegroundColor Green
}

function Clear-IntegrationTestEnvironment {
    [CmdletBinding()]
    param()

    Write-Host "Cleaning up integration test environment variables..." -ForegroundColor Yellow

    # Get all environment variables that start with PWSH_TEST_
    $testEnvVars = [Environment]::GetEnvironmentVariables("Process").Keys | Where-Object { $_ -like "PWSH_TEST_*" }

    $cleanedCount = 0
    foreach ($envVar in $testEnvVars) {
        Write-Host "Removing $envVar" -ForegroundColor Cyan
        [Environment]::SetEnvironmentVariable($envVar, $null, "Process")
        $cleanedCount++
    }

    if ($cleanedCount -gt 0) {
        Write-Host "Successfully cleaned up $cleanedCount integration test environment variables" -ForegroundColor Green
    }
    else {
        Write-Host "No integration test environment variables found to clean up" -ForegroundColor Yellow
    }
}



function Write-GitHubStepSummary {
    param($Results, $CoverageThreshold = 80, $TestType, $Duration)

    if (-not $script:CI -or -not $env:GITHUB_STEP_SUMMARY) {
        return
    }

    Write-Host "Generating GitHub Step Summary..." -ForegroundColor Yellow

    # Determine status emoji
    $statusEmoji = if ($Results.FailedCount -eq 0) { "✅" } else { "❌" }

    # Create summary content
    $summary = @()
    $summary += "## $statusEmoji PowerShell Runtime $TestType Test Results"
    $summary += ""

    # Test type and duration info
    $summary += "**Test Type:** $TestType"
    if ($Duration) {
        $durationFormatted = "{0:mm\:ss}" -f ([datetime]$Duration.Ticks)
        $summary += "**Duration:** $durationFormatted"
    }
    $summary += ""

    # Overall statistics table
    $summary += "### 📊 Test Statistics"
    $summary += ""
    $summary += "| Metric | Count |"
    $summary += "|--------|-------|"
    $summary += "| Total Tests | $($Results.TotalCount) |"
    $summary += "| ✅ Passed | $($Results.PassedCount) |"
    $summary += "| ❌ Failed | $($Results.FailedCount) |"
    $summary += "| ⏭️ Skipped | $($Results.SkippedCount) |"
    $summary += ""

    # Code coverage section
    if ($Results.CodeCoverage -and $Results.CodeCoverage.CommandsAnalyzedCount -gt 0) {
        $CommandsAnalyzed = $Results.CodeCoverage.CommandsAnalyzedCount
        $CommandsExecuted = $Results.CodeCoverage.CommandsExecutedCount
        $CoveragePercent = [math]::Round(($CommandsExecuted / $CommandsAnalyzed) * 100, 2)
        $coverageEmoji = if ($CoveragePercent -ge $CoverageThreshold) { "✅" } else { "⚠️" }

        $summary += "### 📈 Code Coverage"
        $summary += ""
        $summary += "| Metric | Value |"
        $summary += "|--------|-------|"
        $summary += "| $coverageEmoji Coverage | $CoveragePercent% |"
        $summary += "| Commands Executed | $CommandsExecuted |"
        $summary += "| Commands Analyzed | $CommandsAnalyzed |"
        $summary += "| Threshold | $CoverageThreshold% |"
        $summary += ""

        if ($CoveragePercent -lt $CoverageThreshold) {
            $summary += "> ⚠️ **Warning:** Code coverage is below the required threshold of $CoverageThreshold%"
            $summary += ""
        }
    }

    # Failed tests details
    if ($Results.FailedCount -gt 0) {
        $summary += "### ❌ Failed Tests"
        $summary += ""

        # Group failed tests by container/describe block
        $failedByContainer = @{}
        foreach ($failedTest in $Results.Failed) {
            $containerName = if ($failedTest.Block -and $failedTest.Block.Name) {
                $failedTest.Block.Name
            }
            else {
                "Unknown"
            }

            if (-not $failedByContainer.ContainsKey($containerName)) {
                $failedByContainer[$containerName] = @()
            }
            $failedByContainer[$containerName] += $failedTest
        }

        foreach ($container in $failedByContainer.Keys) {
            $summary += "#### 📁 $container"
            $summary += ""

            foreach ($test in $failedByContainer[$container]) {
                $summary += "- **$($test.Name)**"
                if ($test.ErrorRecord -and $test.ErrorRecord.Exception) {
                    $errorMessage = $test.ErrorRecord.Exception.Message -replace "`r`n", "`n" -replace "`n", " "
                    if ($errorMessage.Length -gt 200) {
                        $errorMessage = $errorMessage.Substring(0, 200) + "..."
                    }
                    $summary += "  ``` "
                    $summary += "  $errorMessage "
                    $summary += "  ``` "
                }
                $summary += ""
            }
        }
    }

    # Success message
    if ($Results.FailedCount -eq 0) {
        $summary += "### 🎉 All Tests Passed!"
        $summary += ""
        $summary += "Great job! All tests are passing successfully."
        $summary += ""
    }

    # Write to GitHub Step Summary
    try {
        $summary -join "`n" | Out-File -FilePath $env:GITHUB_STEP_SUMMARY -Encoding UTF8 -Append
        Write-Host "GitHub Step Summary generated successfully" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to write GitHub Step Summary: $_"
    }
}

function Test-Results {
    param($Results, $CoverageThreshold = 80)

    Write-Host "`nTest Results:" -ForegroundColor Cyan
    Write-Host "Tests: $($Results.PassedCount)/$($Results.TotalCount) passed" -ForegroundColor $(if ($Results.FailedCount -eq 0) { 'Green' } else { 'Red' })

    if ($Results.FailedCount -gt 0) {
        Write-Host "Failed Tests:" -ForegroundColor Red
        foreach ($FailedTest in $Results.Failed) {
            Write-Host "  - $($FailedTest.Name): $($FailedTest.ErrorRecord.Exception.Message)" -ForegroundColor Red
        }
    }

    # Check code coverage if enabled
    if ($Results.CodeCoverage -and $Results.CodeCoverage.CommandsAnalyzedCount -gt 0) {
        $CommandsAnalyzed = $Results.CodeCoverage.CommandsAnalyzedCount
        $CommandsExecuted = $Results.CodeCoverage.CommandsExecutedCount
        $CoveragePercent = [math]::Round(($CommandsExecuted / $CommandsAnalyzed) * 100, 2)

        Write-Host "Coverage: $CoveragePercent% ($CommandsExecuted/$CommandsAnalyzed commands)" -ForegroundColor $(if ($CoveragePercent -ge $CoverageThreshold) { 'Green' } else { 'Red' })

        if ($CoveragePercent -lt $CoverageThreshold) {
            Write-Warning "Code coverage ($CoveragePercent%) is below threshold ($CoverageThreshold%)"
            return $Results.FailedCount -eq 0 -and (-not $script:CI -or $CoveragePercent -ge $CoverageThreshold)
        }
    }

    return $Results.FailedCount -eq 0
}

# Main execution
try {
    # Initialize
    if ($script:CI) {
        Write-CIDiagnostics -Phase 'Start'
    }

    Initialize-TestFramework

    # Set up integration test environment if needed
    if ($TestType -eq 'Integration') {
        try {
            Initialize-IntegrationTestEnvironment -StackName $StackName -Region $Region -ProfileName $ProfileName
        }
        catch {
            Write-Error "Failed to initialize integration test environment: $_"
            throw "Integration test environment setup failed. Please ensure the CloudFormation stack '$StackName' exists in region '$Region' and you have appropriate permissions."
        }
    }

    # Configure paths
    $TestPaths = if ($Path) {
        $Path | Where-Object { Test-Path $_ }
    }
    else {
        switch ($TestType) {
            'Unit' {
                @(
                    (Join-Path $script:ProjectRoot 'tests/unit/Module'),
                    (Join-Path $script:ProjectRoot 'tests/unit/Private')
                )
            }
            'Build' { Join-Path $script:ProjectRoot 'tests/unit/Build' }
            'Private' { Join-Path $script:ProjectRoot 'tests/unit/Private' }
            'Integration' { Join-Path $script:ProjectRoot 'tests/integration' }
            'LocalUnit' {
                @(
                    (Join-Path $script:ProjectRoot 'tests/unit/Build'),
                    (Join-Path $script:ProjectRoot 'tests/unit/Module'),
                    (Join-Path $script:ProjectRoot 'tests/unit/Private')
                )
            }
        }
    }

    Write-Host "Test paths: $($TestPaths -join ', ')" -ForegroundColor Yellow

    # Build if needed
    if ($TestBuiltModule) {
        Write-Host "Building module for validation testing..." -ForegroundColor Cyan
        $buildScript = Join-Path $script:ProjectRoot "build-PwshRuntimeLayer.ps1"
        & $buildScript -SkipRuntimeSetup 6>$null
        Write-Host "Module built" -ForegroundColor Green
    }

    # Configure Pester
    $Config = New-PesterConfiguration
    $Config.Run.Path = $TestPaths
    $Config.Run.PassThru = $true
    $Config.Output.Verbosity = if ($DetailedOutput) { 'Detailed' } else { 'Normal' }

    # Configure coverage
    if ($script:Coverage -or $script:CI) {
        $Config.CodeCoverage.Enabled = $true
        $Config.CodeCoverage.OutputFormat = 'JaCoCo'
        $Config.CodeCoverage.OutputPath = Join-Path $script:ProjectRoot "CodeCoverage.xml"
        $coveragePaths = Get-CoveragePaths -TestPaths $TestPaths -ProjectRoot $script:ProjectRoot -TestBuiltModule $TestBuiltModule -TestType $TestType
        $Config.CodeCoverage.Path = $coveragePaths

        $coverageThreshold = $script:TestConfig.PrivateData.TestSettings.CodeCoverage.Threshold
        $Config.CodeCoverage.CoveragePercentTarget = $coverageThreshold

        Write-Host "Coverage enabled for $($coveragePaths.Count) files:" -ForegroundColor Yellow
        foreach ($path in $coveragePaths) {
            $relativePath = $path -replace [regex]::Escape($script:ProjectRoot), '.'
            Write-Host "  - $relativePath" -ForegroundColor Cyan
        }
    }

    # Configure output
    if ($script:CI -or $OutputFormat -ne 'Console') {
        $Config.TestResult.Enabled = $true
        $Config.TestResult.OutputFormat = if ($script:CI) { 'JUnitXml' } else { $OutputFormat }
        $Config.TestResult.OutputPath = Join-Path $script:ProjectRoot "TestResults.xml"
    }

    # Configure test containers for built module testing
    if ($TestBuiltModule) {
        $containers = @()
        foreach ($path in $TestPaths) {
            $testFiles = if (Test-Path $path -PathType Container) {
                Get-ChildItem -Path $path -Filter "*.Tests.ps1" -Recurse
            }
            else {
                @($path)
            }

            foreach ($file in $testFiles) {
                $containers += New-PesterContainer -Path $file.FullName -Data @{TestBuiltModule = $true }
            }
        }
        $Config.Run.Container = $containers
        $Config.Run.Path = @()

        Write-Host "Configured $($containers.Count) test containers for built module testing" -ForegroundColor Yellow
    }

    # Run tests
    Write-Host "`nExecuting tests..." -ForegroundColor Green
    if ($script:CI) {
        Write-CIDiagnostics -Phase 'Progress'
    }

    $testStartTime = Get-Date
    $Results = Invoke-Pester -Configuration $Config
    $testDuration = (Get-Date) - $testStartTime

    # Generate GitHub Step Summary for CI
    if ($script:CI) {
        $coverageThreshold = $script:TestConfig.PrivateData.TestSettings.CodeCoverage.Threshold
        Write-GitHubStepSummary -Results $Results -CoverageThreshold $coverageThreshold -TestType $TestType -Duration $testDuration
    }

    # Check results
    $coverageThreshold = $script:TestConfig.PrivateData.TestSettings.CodeCoverage.Threshold
    $Success = Test-Results -Results $Results -CoverageThreshold $coverageThreshold

    # Cleanup and exit
    if ($script:CI) {
        Write-CIDiagnostics -Phase 'End'
        Invoke-CICleanup
    }

    Exit-TestScript -ExitCode $(if ($Success) { 0 } else { 1 })
}
catch {
    Write-Error "Test execution failed: $_"
    if ($script:CI) {
        Invoke-CICleanup
    }
    Exit-TestScript -ExitCode 1 -ExitMessage "Test execution failed: $_"
}
finally {
    # Always clean up integration test environment variables
    if ($TestType -eq 'Integration') {
        try {
            Clear-IntegrationTestEnvironment
        }
        catch {
            Write-Warning "Failed to clean up integration test environment: $_"
        }
    }
}
