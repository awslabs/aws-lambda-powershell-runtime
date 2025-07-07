#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Central test runner for PowerShell Lambda Runtime tests

.DESCRIPTION
    This script provides a centralized entry point for executing all tests in the PowerShell Lambda Runtime project.
    It supports three testing modes via parameter sets:

    1. SourceTesting (default): Tests source files directly for fast development
    2. BuiltModuleTesting: Tests the built/merged module for validation
    3. SpecificPathTesting: Tests specific files or directories for targeted development

    Note: The -Verbose parameter controls PowerShell's verbose output for this script, while -DetailedOutput
    controls Pester's detailed test output. These can be used independently or together.

.PARAMETER TestType
    Specifies which type of tests to run. Valid values: 'All', 'Unit', 'Build'
    Available in all parameter sets.

.PARAMETER Path
    Specifies specific test files or directories to run. This parameter is mandatory and exclusive
    to the SpecificPathTesting parameter set. Cannot be used with -TestBuiltModule.

.PARAMETER CI
    Indicates the script is running in a CI/CD environment, enabling CI-specific behaviors.
    Available in all parameter sets.

.PARAMETER Coverage
    Enables code coverage analysis. Coverage paths are determined by the active parameter set.
    Available in all parameter sets.

.PARAMETER Parallel
    Enables parallel test execution where supported.
    Available in all parameter sets.

.PARAMETER OutputFormat
    Specifies the output format for test results. Valid values: 'NUnitXml', 'JUnitXml', 'Console'
    Available in all parameter sets.

.PARAMETER DetailedOutput
    Enables detailed Pester output for debugging (sets Pester output verbosity to 'Detailed').
    Available in all parameter sets.

.PARAMETER TestBuiltModule
    Test against the built module instead of source files. This parameter is mandatory and exclusive
    to the BuiltModuleTesting parameter set. Cannot be used with -Path.

.EXAMPLE
    ./Invoke-Tests.ps1
    Runs all tests with default settings

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Unit -Coverage
    Runs only unit tests with code coverage

.EXAMPLE
    ./Invoke-Tests.ps1 -CI -OutputFormat NUnitXml
    Runs all tests in CI mode with NUnit XML output

.EXAMPLE
    ./Invoke-Tests.ps1 -DetailedOutput
    Runs all tests with detailed Pester output for debugging

.EXAMPLE
    ./Invoke-Tests.ps1 -Path './tests/unit/Private/Set-LambdaContext.Tests.ps1' -DetailedOutput
    Runs a specific test file with detailed Pester output

.EXAMPLE
    ./Invoke-Tests.ps1 -Verbose
    Runs all tests with PowerShell verbose output enabled

.EXAMPLE
    ./Invoke-Tests.ps1 -DetailedOutput -Verbose
    Runs all tests with both detailed Pester output and PowerShell verbose output

.EXAMPLE
    ./Invoke-Tests.ps1 -TestType Unit
    Uses SourceTesting parameter set to run unit tests against source files (default - fastest for development)

.EXAMPLE
    ./Invoke-Tests.ps1 -TestBuiltModule
    Uses BuiltModuleTesting parameter set to build and test the merged module (validation testing)

.EXAMPLE
    ./Invoke-Tests.ps1 -Path './tests/unit/Private/Get-Handler.Tests.ps1'
    Uses SpecificPathTesting parameter set to run a specific test file

.EXAMPLE
    ./Invoke-Tests.ps1 -Path './tests/helpers/TestUtilities.Tests.ps1' -Coverage
    Uses SpecificPathTesting parameter set with coverage analysis for targeted development
#>

[CmdletBinding(DefaultParameterSetName = 'SourceTesting')]
param(
    [Parameter(ParameterSetName = 'SourceTesting')]
    [Parameter(ParameterSetName = 'BuiltModuleTesting')]
    [Parameter(ParameterSetName = 'SpecificPathTesting')]
    [ValidateSet('All', 'Unit', 'Build')]
    [string]$TestType = 'All',

    [Parameter(ParameterSetName = 'SpecificPathTesting', Mandatory = $true)]
    [string[]]$Path,

    [Parameter(ParameterSetName = 'SourceTesting')]
    [Parameter(ParameterSetName = 'BuiltModuleTesting')]
    [Parameter(ParameterSetName = 'SpecificPathTesting')]
    [switch]$CI,

    [Parameter(ParameterSetName = 'SourceTesting')]
    [Parameter(ParameterSetName = 'BuiltModuleTesting')]
    [Parameter(ParameterSetName = 'SpecificPathTesting')]
    [switch]$Coverage,

    [Parameter(ParameterSetName = 'SourceTesting')]
    [Parameter(ParameterSetName = 'BuiltModuleTesting')]
    [Parameter(ParameterSetName = 'SpecificPathTesting')]
    [switch]$Parallel,

    [Parameter(ParameterSetName = 'SourceTesting')]
    [Parameter(ParameterSetName = 'BuiltModuleTesting')]
    [Parameter(ParameterSetName = 'SpecificPathTesting')]
    [ValidateSet('NUnitXml', 'JUnitXml', 'Console')]
    [string]$OutputFormat = 'Console',

    [Parameter(ParameterSetName = 'SourceTesting')]
    [Parameter(ParameterSetName = 'BuiltModuleTesting')]
    [Parameter(ParameterSetName = 'SpecificPathTesting')]
    [switch]$DetailedOutput,

    # Test against the built module instead of source files (mutually exclusive with Path)
    [Parameter(ParameterSetName = 'BuiltModuleTesting', Mandatory = $true)]
    [switch]$TestBuiltModule
)

# Set error action preference for consistent behavior
$ErrorActionPreference = 'Stop'

# Get script directory and project root
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$TestRequirementsPath = Join-Path $ProjectRoot 'test-requirements.psd1'
$script:CurrentPSModulePath = $env:PSModulePath

Write-Host "PowerShell Runtime Test Runner" -ForegroundColor Cyan
Write-Host "===============================" -ForegroundColor Cyan

# Handle verbose preference - separate from DetailedOutput parameter
if ($PSBoundParameters.ContainsKey('Verbose') -and $PSBoundParameters['Verbose']) {
    $VerbosePreference = 'Continue'
    Write-Verbose "PowerShell verbose output enabled"
}

# Load test requirements and configuration
if (Test-Path $TestRequirementsPath) {
    Write-Host "Loading test requirements from: $TestRequirementsPath" -ForegroundColor Green
    Write-Verbose "Reading test configuration from $TestRequirementsPath"
    $TestConfig = Import-PowerShellDataFile -Path $TestRequirementsPath
}
else {
    Write-Warning "Test requirements file not found at: $TestRequirementsPath"
    Write-Host "Using default configuration..." -ForegroundColor Yellow
    $TestConfig = @{
        PrivateData = @{
            TestSettings = @{
                OutputFormat = 'Console'
                CodeCoverage = @{ Enabled = $false; Threshold = 80 }
                Parallel     = @{ Enabled = $false; MaxJobs = 4 }
                TestPath     = @('tests/unit')
                Timeout      = @{ Unit = 30; Build = 300 }
            }
        }
    }
}

function Exit-TestScript {
    param (
        $ExitCode,
        $ExitMessage
    )
    $env:PSModulePath = $script:CurrentPSModulePath

    # In CI mode, always exit the process
    if ($CI) {
        exit $ExitCode
    }

    if ($ExitCode -ne 0 -and $ExitMessage) {
        throw $ExitMessage
    }
    elseif ($ExitCode -ne 0) {
        throw "Exiting with exit code $ExitCode"
    }
    else {
        return
    }
}

# Function to ensure Pester is available
function Initialize-TestFramework {
    Write-Host "Initializing test framework..." -ForegroundColor Yellow
    Write-Verbose "Checking for Pester module availability"

    # Check if Pester is available
    $PesterModule = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1

    if (-not $PesterModule) {
        Write-Host "Pester not found. Installing Pester..." -ForegroundColor Yellow
        try {
            Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
            Write-Host "Pester installed" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install Pester: $_"
            Exit-TestScript -ExitCode 1 -ExitMessage "Failed to install Pester: $_"
        }
    }
    else {
        Write-Host "Found Pester version: $($PesterModule.Version)" -ForegroundColor Green
    }

    # Import Pester with specific version if available
    try {
        Import-Module Pester -Force
        Write-Host "Pester imported" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to import Pester: $_"
        Exit-TestScript -ExitCode 1 -ExitMessage "Failed to import Pester: $_"
    }
}

# Function to get test path based on test type
function Get-TestPath {
    param([string]$Type, [string[]]$SpecificPath)

    if ($SpecificPath) {
        $ValidPaths = @()
        foreach ($path in $SpecificPath) {
            if (Test-Path $path) {
                $ValidPaths += $path
            }
            else {
                Write-Error "Specified path does not exist: $path"
                Exit-TestScript -ExitCode 1 -ExitMessage "Specified path does not exist: $path"
            }
        }
        return $ValidPaths
    }

    $TestsDir = Join-Path $ProjectRoot 'tests'

    switch ($Type) {
        'Unit' {
            return @(Join-Path $TestsDir 'unit')
        }
        'Build' {
            return @(Join-Path $TestsDir 'unit/Build')
        }
        'All' {
            return @(
                (Join-Path $TestsDir 'unit')
            )
        }
        default {
            return @(
                (Join-Path $TestsDir 'unit')
            )
        }
    }
}

# Helper function to map test files to their corresponding source files
function Get-SourceFileFromTestFile {
    <#
    .SYNOPSIS
        Maps a test file to its corresponding source file(s).

    .DESCRIPTION
        Analyzes a test file path and determines which source files should be included
        in code coverage analysis based on established naming conventions and directory structure.

    .PARAMETER TestFilePath
        Path to the test file to analyze.

    .PARAMETER ProjectRoot
        Root directory of the project.

    .RETURNS
        Array of source file paths that correspond to the test file.
    #>
    param(
        [string]$TestFilePath,
        [string]$ProjectRoot
    )

    $SourceFiles = @()
    $TestFileName = Split-Path -Leaf $TestFilePath
    $TestDirectory = Split-Path -Parent $TestFilePath

    # Remove .Tests.ps1 suffix to get the base name
    if ($TestFileName -match '^(.+)\.Tests\.ps1$') {
        $BaseName = $Matches[1]

        # Determine source file location based on test directory structure
        $RelativeTestPath = $TestDirectory.Replace($ProjectRoot, '').TrimStart('\', '/')

        Write-Verbose "Mapping test file: $TestFileName (Base: $BaseName)"
        Write-Verbose "Test directory: $RelativeTestPath"

        switch -Regex ($RelativeTestPath) {
            'tests[/\\]unit[/\\]Private' {
                # Private function tests -> source/modules/Private/*.ps1
                $SourceFile = Join-Path $ProjectRoot "source/modules/Private/$BaseName.ps1"
                if (Test-Path $SourceFile) {
                    $SourceFiles += $SourceFile
                    Write-Verbose "Found private function source: $SourceFile"
                }
            }

            'tests[/\\]unit[/\\]Module' {
                # Module tests -> source/modules/*.psm1 and *.psd1
                $ModuleFile = Join-Path $ProjectRoot "source/modules/$BaseName.psm1"
                $ManifestFile = Join-Path $ProjectRoot "source/modules/$BaseName.psd1"

                if (Test-Path $ModuleFile) {
                    $SourceFiles += $ModuleFile
                    Write-Verbose "Found module source: $ModuleFile"
                }
                if (Test-Path $ManifestFile) {
                    $SourceFiles += $ManifestFile
                    Write-Verbose "Found module manifest: $ManifestFile"
                }
            }

            'tests[/\\]unit[/\\]Build' {
                # Build script tests -> build scripts in project root
                $BuildScript = Join-Path $ProjectRoot "build-$BaseName.ps1"
                if (Test-Path $BuildScript) {
                    $SourceFiles += $BuildScript
                    Write-Verbose "Found build script: $BuildScript"
                }

                # Also check for the main build script
                $MainBuildScript = Join-Path $ProjectRoot "build-PwshRuntimeLayer.ps1"
                if (Test-Path $MainBuildScript -and $BaseName -like "*Build*") {
                    $SourceFiles += $MainBuildScript
                    Write-Verbose "Found main build script: $MainBuildScript"
                }
            }

            'tests[/\\]helpers' {
                # Helper tests -> the helper files themselves
                $HelperFile = Join-Path $ProjectRoot "tests/helpers/$BaseName.ps1"
                if (Test-Path $HelperFile) {
                    $SourceFiles += $HelperFile
                    Write-Verbose "Found helper source: $HelperFile"
                }
            }

            default {
                Write-Verbose "No specific mapping rule for test path: $RelativeTestPath"
            }
        }
    }

    return $SourceFiles
}

# Helper function to get coverage path based on priority order
function Get-CoveragePathForTest {
    <#
    .SYNOPSIS
        Determines coverage paths based on clear priority order.

    .DESCRIPTION
        Determines coverage paths using this priority order:
        1. If BuiltModule mode: Use built module files
        2. If specific Path provided: Use files corresponding to those paths
        3. Otherwise: Use default based on TestSource flag

    .PARAMETER TestPaths
        Array of test paths (files or directories) being executed.

    .PARAMETER ProjectRoot
        Root directory of the project.

    .PARAMETER IsBuiltModule
        Whether testing against built module.

    .PARAMETER IsSpecificPath
        Whether specific test paths were provided.

    .PARAMETER TestSource
        Whether testing source files (used for default behavior).

    .RETURNS
        Array of source file paths to include in coverage analysis.
    #>
    param(
        [string[]]$TestPaths,
        [string]$ProjectRoot,
        [bool]$IsBuiltModule,
        [bool]$IsSpecificPath,
        [bool]$TestSource
    )

    $CoveragePaths = @()

    Write-Verbose "Coverage path determination:"
    Write-Verbose "  IsBuiltModule: $IsBuiltModule"
    Write-Verbose "  IsSpecificPath: $IsSpecificPath"
    Write-Verbose "  TestSource: $TestSource"
    Write-Verbose "  TestPaths: $($TestPaths -join ', ')"

    # Priority 1: If BuiltModule, use built module files
    if ($IsBuiltModule) {
        Write-Verbose "Priority 1: Using built module files for coverage"

        $BuiltModulePath = Join-Path $ProjectRoot "layers/runtimeLayer/modules/pwsh-runtime.psm1"
        if (Test-Path $BuiltModulePath) {
            $CoveragePaths += $BuiltModulePath
            Write-Verbose "Added built module: $BuiltModulePath"
        }

        # Include build script if build tests are present
        $HasBuildTests = $TestPaths | Where-Object { $_ -like "*Build*" -or $_ -like "*build*" }
        if ($HasBuildTests) {
            $BuildScriptPath = Join-Path $ProjectRoot "build-PwshRuntimeLayer.ps1"
            if (Test-Path $BuildScriptPath) {
                $CoveragePaths += $BuildScriptPath
                Write-Verbose "Added build script: $BuildScriptPath"
            }
        }
    }
    # Priority 2: If specific Path provided, use corresponding source files
    elseif ($IsSpecificPath) {
        Write-Verbose "Priority 2: Using files corresponding to specific test paths"

        $AllTestFiles = @()

        # Expand test paths to individual test files
        foreach ($TestPath in $TestPaths) {
            if (Test-Path $TestPath -PathType Container) {
                $TestFiles = Get-ChildItem -Path $TestPath -Filter "*.Tests.ps1" -Recurse
                $AllTestFiles += $TestFiles.FullName
                Write-Verbose "Expanded directory $TestPath to $($TestFiles.Count) test files"
            }
            elseif ($TestPath -like "*.Tests.ps1" -and (Test-Path $TestPath)) {
                $AllTestFiles += $TestPath
                Write-Verbose "Added test file: $TestPath"
            }
        }

        # Map test files to source files
        foreach ($TestFile in $AllTestFiles) {
            $SourceFiles = Get-SourceFileFromTestFile -TestFilePath $TestFile -ProjectRoot $ProjectRoot
            $CoveragePaths += $SourceFiles
        }

        # Remove duplicates
        $CoveragePaths = $CoveragePaths | Select-Object -Unique
        Write-Verbose "Mapped $($AllTestFiles.Count) test files to $($CoveragePaths.Count) source files"
    }
    # Priority 3: Default behavior based on TestSource flag
    else {
        Write-Verbose "Priority 3: Using default coverage based on TestSource flag"

        if ($TestSource) {
            # Default for source testing: all source files
            $SourceModulesPath = Join-Path $ProjectRoot "source/modules"
            if (Test-Path $SourceModulesPath) {
                $SourceFiles = Get-ChildItem -Path $SourceModulesPath -Filter "*.ps1" -Recurse | ForEach-Object { $_.FullName }
                $CoveragePaths += $SourceFiles
                Write-Verbose "Added all source files: $($SourceFiles.Count) files"
            }

            # Include helper files
            $HelpersPath = Join-Path $ProjectRoot "tests/helpers"
            if (Test-Path $HelpersPath) {
                $HelperFiles = Get-ChildItem -Path $HelpersPath -Filter "*.ps1" -Exclude "*.Tests.ps1" | ForEach-Object { $_.FullName }
                $CoveragePaths += $HelperFiles
                Write-Verbose "Added helper files: $($HelperFiles.Count) files"
            }
        }
        else {
            # Default for built module testing: built module
            $BuiltModulePath = Join-Path $ProjectRoot "layers/runtimeLayer/modules/pwsh-runtime.psm1"
            if (Test-Path $BuiltModulePath) {
                $CoveragePaths += $BuiltModulePath
                Write-Verbose "Added built module (default): $BuiltModulePath"
            }
        }
    }

    # Filter to existing files and remove duplicates
    $ValidCoveragePaths = $CoveragePaths | Where-Object { Test-Path $_ } | Select-Object -Unique

    Write-Verbose "Final coverage paths: $($ValidCoveragePaths.Count) files"
    foreach ($path in $ValidCoveragePaths) {
        Write-Verbose "  - $path"
    }

    return $ValidCoveragePaths
}

# Function to configure Pester settings
function New-TestPesterConfiguration {
    <#
    .SYNOPSIS
        Configures Pester test settings including code coverage for different test modes.

    .DESCRIPTION
        This function configures Pester to run tests with appropriate code coverage paths
        based on the test execution mode:
        - Standard/BuildOnce/NoBuild: Coverage on built/merged module
        - TestSource: Coverage on individual source files
    #>
    param(
        [string[]]$TestPaths,
        [bool]$EnableCoverage,
        [bool]$EnableParallel,
        [string]$Format,
        [bool]$IsCI,
        [int]$CoverageThreshold = 80,
        [bool]$TestSource = $false,
        [string]$ProjectRoot
    )

    $Config = New-PesterConfiguration

    # Run configuration
    $Config.Run.Path = $TestPaths
    $Config.Run.PassThru = $true

    # Output configuration
    if ($Format -ne 'Console' -or $IsCI) {
        $Config.TestResult.Enabled = $true
        $Config.TestResult.OutputFormat = $Format
        $Config.TestResult.OutputPath = Join-Path $ProjectRoot "TestResults.xml"
    }

    # Code coverage configuration
    if ($EnableCoverage) {
        $Config.CodeCoverage.Enabled = $true
        $Config.CodeCoverage.OutputFormat = 'JaCoCo'
        $Config.CodeCoverage.OutputPath = Join-Path $ProjectRoot "CodeCoverage.xml"

        # Set coverage threshold from configuration
        $Config.CodeCoverage.CoveragePercentTarget = $CoverageThreshold

        # Use the new priority-based coverage path detection
        $IsSpecificPath = $null -ne $Path -and $Path.Count -gt 0
        Write-Verbose "Configuring code coverage with priority-based logic"

        $CoveragePaths = Get-CoveragePathForTest -TestPaths $TestPaths -ProjectRoot $ProjectRoot -IsBuiltModule (-not $TestSource) -IsSpecificPath $IsSpecificPath -TestSource $TestSource

        if ($CoveragePaths.Count -gt 0) {
            $Config.CodeCoverage.Path = $CoveragePaths

            Write-Host "Code Coverage Configuration:" -ForegroundColor Yellow
            Write-Host "  Built Module: $(-not $TestSource)" -ForegroundColor White
            Write-Host "  Specific Path: $IsSpecificPath" -ForegroundColor White
            Write-Host "  Test Source: $TestSource" -ForegroundColor White
            Write-Host "  Files: $($CoveragePaths.Count)" -ForegroundColor White
            Write-Host "  Paths:" -ForegroundColor White
            foreach ($path in $CoveragePaths) {
                $relativePath = $path.Replace($ProjectRoot, '').TrimStart('\', '/')
                Write-Host "    - $relativePath" -ForegroundColor Gray
            }
        }
        else {
            Write-Warning "No coverage paths determined for the specified test paths"
            Write-Host "This may indicate:" -ForegroundColor Yellow
            Write-Host "  - Test files don't follow expected naming conventions" -ForegroundColor Yellow
            Write-Host "  - Corresponding source files don't exist" -ForegroundColor Yellow
            Write-Host "  - Test paths are not in recognized directory structure" -ForegroundColor Yellow
        }
    }

    # Output verbosity
    if ($DetailedOutput -or $IsCI) {
        $Config.Output.Verbosity = 'Detailed'
    }
    else {
        $Config.Output.Verbosity = 'Normal'
    }

    return $Config
}

# Function to build the PowerShell runtime module once for all tests
function Invoke-ModuleBuild {
    <#
    .SYNOPSIS
        Builds the PowerShell runtime module once for all tests.

    .DESCRIPTION
        Executes the build script to create the merged runtime module.
        This is used in BuildOnce mode to avoid rebuilding for each test file.

    .PARAMETER ProjectRoot
        The root directory of the PowerShell runtime project.
    #>
    param([string]$ProjectRoot)

    Write-Host "Building PowerShell runtime module..." -ForegroundColor Yellow
    Write-Verbose "Project root: $ProjectRoot"

    $buildScript = Join-Path $ProjectRoot "build-PwshRuntimeLayer.ps1"

    if (Test-Path $buildScript) {
        Write-Verbose "Executing build script: $buildScript"
        & $buildScript -SkipRuntimeSetup 6>$null

        # Verify the build was successful
        $builtModulePath = Join-Path $ProjectRoot "layers/runtimeLayer/modules/pwsh-runtime.psd1"
        if (Test-Path $builtModulePath) {
            Write-Host "Module build completed" -ForegroundColor Green
            Write-Verbose "Built module available at: $builtModulePath"
        }
        else {
            throw "Module build failed - built module not found at: $builtModulePath"
        }
    }
    else {
        throw "Build script not found at: $buildScript"
    }
}

# Function to check if the built module exists
function Test-BuiltModuleExists {
    <#
    .SYNOPSIS
        Checks if the built PowerShell runtime module exists.

    .DESCRIPTION
        Verifies that the built module file exists and is accessible.
        Used in NoBuild mode to ensure the module is available before testing.

    .PARAMETER ProjectRoot
        The root directory of the PowerShell runtime project.

    .RETURNS
        Boolean indicating whether the built module exists.
    #>
    param([string]$ProjectRoot)

    $builtModulePath = Join-Path $ProjectRoot "layers/runtimeLayer/modules/pwsh-runtime.psd1"
    $exists = Test-Path $builtModulePath

    Write-Verbose "Checking for built module at: $builtModulePath"
    Write-Verbose "Built module exists: $exists"

    return $exists
}

# Function to invoke test with appropriate parameters based on execution mode
function Invoke-TestWithParameters {
    <#
    .SYNOPSIS
        Invokes Pester tests with the appropriate parameters based on test mode.

    .DESCRIPTION
        Configures and executes Pester tests with parameters that control how
        individual test files build and import the runtime module.

    .PARAMETER TestPaths
        Array of test paths to execute.

    .PARAMETER BuildModule
        Whether individual test files should build the module.

    .PARAMETER TestSource
        Whether to test source files directly instead of built module.

    .PARAMETER PesterConfig
        The Pester configuration object to use for test execution.

    .RETURNS
        Pester test results object.
    #>
    param(
        [string[]]$TestPaths,
        [bool]$BuildModule,
        [bool]$TestSource,
        [object]$PesterConfig
    )

    Write-Verbose "Configuring test execution with parameters:"
    Write-Verbose "  BuildModule: $BuildModule"
    Write-Verbose "  TestSource: $TestSource"
    Write-Verbose "  TestPaths: $($TestPaths -join ', ')"

    # Prepare test parameters to pass to individual test files
    $testParams = @{}
    if ($TestBuiltModule) {
        $testParams['TestBuiltModule'] = $true
    }

    # If we have parameters to pass, use Pester containers
    if ($testParams.Count -gt 0) {
        Write-Host "Configuring test containers with parameters: $($testParams.Keys -join ', ')" -ForegroundColor Yellow

        $containers = @()
        foreach ($path in $TestPaths) {
            if (Test-Path $path -PathType Container) {
                # Directory - find all test files
                Write-Verbose "Processing directory: $path"
                $testFiles = Get-ChildItem -Path $path -Filter "*.Tests.ps1" -Recurse
                Write-Verbose "Found $($testFiles.Count) test files in directory"

                foreach ($file in $testFiles) {
                    Write-Verbose "Adding container for: $($file.FullName)"
                    $container = New-PesterContainer -Path $file.FullName -Data $testParams
                    $containers += $container
                }
            }
            else {
                # Single file
                Write-Verbose "Adding container for single file: $path"
                $container = New-PesterContainer -Path $path -Data $testParams
                $containers += $container
            }
        }

        # Set the containers and clear the Path
        $PesterConfig.Run.Container = $containers
        $PesterConfig.Run.Path = @()

        Write-Host "Configured $($PesterConfig.Run.Container.Count) test containers" -ForegroundColor Green
    }
    else {
        Write-Host "Using standard test execution (no special parameters)" -ForegroundColor Yellow
    }

    # Run tests
    Write-Verbose "Starting Pester test execution"
    return Invoke-Pester -Configuration $PesterConfig
}

# Function to validate test results
function Test-Results {
    param($Results, $CoverageThreshold = 80)

    $Success = $true

    Write-Host "`nTest Results Summary:" -ForegroundColor Cyan
    Write-Host "===================" -ForegroundColor Cyan
    Write-Host "Total Tests: $($Results.TotalCount)" -ForegroundColor White
    Write-Host "Passed: $($Results.PassedCount)" -ForegroundColor Green
    Write-Host "Failed: $($Results.FailedCount)" -ForegroundColor $(if ($Results.FailedCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host "Skipped: $($Results.SkippedCount)" -ForegroundColor Yellow
    Write-Host "Duration: $($Results.Duration)" -ForegroundColor White

    if ($Results.FailedCount -gt 0) {
        Write-Host "`nFailed Tests:" -ForegroundColor Red
        foreach ($FailedTest in $Results.Failed) {
            Write-Host "  - $($FailedTest.Name): $($FailedTest.ErrorRecord.Exception.Message)" -ForegroundColor Red
        }
        $Success = $false
    }

    # Check code coverage if enabled
    if ($Results.CodeCoverage) {
        # Debug: Show coverage object structure
        Write-Verbose "Coverage object type: $($Results.CodeCoverage.GetType().FullName)"
        Write-Verbose "Coverage properties: $($Results.CodeCoverage | Get-Member -MemberType Property | Select-Object -ExpandProperty Name)"

        $CommandsAnalyzed = $Results.CodeCoverage.CommandsAnalyzedCount
        $CommandsExecuted = $Results.CodeCoverage.CommandsExecutedCount

        Write-Verbose "Commands analyzed: $CommandsAnalyzed"
        Write-Verbose "Commands executed: $CommandsExecuted"

        if ($CommandsAnalyzed -gt 0) {
            $CoveragePercent = [math]::Round(($CommandsExecuted / $CommandsAnalyzed) * 100, 2)
            Write-Host "`nCode Coverage: $CoveragePercent% ($CommandsExecuted/$CommandsAnalyzed commands)" -ForegroundColor $(if ($CoveragePercent -ge $CoverageThreshold) { 'Green' } else { 'Red' })

            if ($CoveragePercent -lt $CoverageThreshold) {
                Write-Warning "Code coverage ($CoveragePercent%) is below threshold ($CoverageThreshold%)"
                if ($CI) {
                    $Success = $false
                }
            }
        }
        else {
            Write-Warning "No commands found for coverage analysis (Analyzed: $CommandsAnalyzed, Executed: $CommandsExecuted) - this may indicate:"
            Write-Host "  - Coverage paths not correctly configured" -ForegroundColor Yellow
            Write-Host "  - Module files not accessible during coverage analysis" -ForegroundColor Yellow
            Write-Host "  - Coverage analysis failed to parse the target files" -ForegroundColor Yellow
            if ($CI) {
                $Success = $false
            }
        }
    }

    return $Success
}

# Main execution
try {
    # Initialize test framework
    Initialize-TestFramework

    # Determine test mode based on switch parameter
    $TestSourceFiles = -not $TestBuiltModule
    Write-Verbose "Test mode determined: $(if ($TestSourceFiles) { 'Source Files' } else { 'Built Module' })"

    # Get test paths
    $TestPaths = Get-TestPath -Type $TestType -SpecificPath $Path
    Write-Host "Test paths: $($TestPaths -join ', ')" -ForegroundColor Yellow
    Write-Verbose "Resolved test paths: $($TestPaths | ForEach-Object { "`n  - $_" })"

    # Validate test paths exist
    foreach ($TestPath in $TestPaths) {
        if (-not (Test-Path $TestPath)) {
            Write-Warning "Test path does not exist: $TestPath"
        }
    }

    # Handle build requirements based on test mode
    Write-Host "TestBuiltModule: $TestBuiltModule"
    if ($TestBuiltModule) {
        Write-Host "Built module testing mode - building module for validation testing" -ForegroundColor Cyan
        Write-Verbose "Building module before running tests"
        Invoke-ModuleBuild -ProjectRoot $ProjectRoot
        $BuildModule = $false  # Module already built, don't build in individual tests
        $ShouldTestSource = $false
        Write-Host "Module built - tests will use built module" -ForegroundColor Green
    }
    else {
        Write-Host "Source file testing mode - testing source files directly (fast development)" -ForegroundColor Cyan
        Write-Verbose "Tests will import and test source files directly"
        $BuildModule = $false  # Don't build module, test source files
        $ShouldTestSource = $true
        Write-Host "Tests will run against source files (no module build required)" -ForegroundColor Green
    }

    # Configure Pester
    $EnableCoverage = $Coverage -or $CI
    $EnableParallel = $Parallel -or ($CI -and $TestConfig.PrivateData.CISettings.ParallelExecution)
    $Format = if ($CI) { 'NUnitXml' } else { $OutputFormat }

    Write-Host "`nConfiguration:" -ForegroundColor Yellow
    Write-Host "  Test Type: $TestType" -ForegroundColor White
    Write-Host "  Test Mode: $(if ($TestBuiltModule) { 'Built Module' } else { 'Source Files' })" -ForegroundColor White
    Write-Host "  Build Module in Tests: $BuildModule" -ForegroundColor White
    Write-Host "  Test Source Files: $ShouldTestSource" -ForegroundColor White
    Write-Host "  Coverage: $EnableCoverage" -ForegroundColor White
    Write-Host "  Parallel: $EnableParallel" -ForegroundColor White
    Write-Host "  Output Format: $Format" -ForegroundColor White
    Write-Host "  CI Mode: $CI" -ForegroundColor White
    Write-Host "  Detailed Output: $DetailedOutput" -ForegroundColor White
    Write-Host "  PowerShell Verbose: $($VerbosePreference -ne 'SilentlyContinue')" -ForegroundColor White

    # Get coverage threshold from configuration
    $CoverageThreshold = $TestConfig.PrivateData.TestSettings.CodeCoverage.Threshold

    $PesterConfig = New-TestPesterConfiguration -TestPaths $TestPaths -EnableCoverage $EnableCoverage -EnableParallel $EnableParallel -Format $Format -IsCI $CI -CoverageThreshold $CoverageThreshold -TestSource $ShouldTestSource -ProjectRoot $ProjectRoot

    # Run tests with appropriate parameters
    Write-Host "`nExecuting tests..." -ForegroundColor Green
    Write-Verbose "Starting Pester test execution with configuration"
    $Results = Invoke-TestWithParameters -TestPaths $TestPaths -BuildModule $BuildModule -TestSource $ShouldTestSource -PesterConfig $PesterConfig

    # Validate results
    $CoverageThreshold = $TestConfig.PrivateData.TestSettings.CodeCoverage.Threshold
    $TestSuccess = Test-Results -Results $Results -CoverageThreshold $CoverageThreshold

    # Exit with appropriate code
    if ($TestSuccess) {
        Write-Host "`nAll tests completed" -ForegroundColor Green
        Exit-TestScript -ExitCode 0
    }
    else {
        Write-Host "`nTests failed or coverage threshold not met!" -ForegroundColor Red
        Exit-TestScript -ExitCode 1 -ExitMessage "Tests failed or coverage threshold not met"
    }

}
catch {
    Write-Error "Test execution failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    Exit-TestScript -ExitCode 1 -ExitMessage "Test execution failed: $_"
}