@{
    # Pester configuration settings for PowerShell Lambda Runtime

    # Test discovery settings
    Discovery = @{
        # Include test files matching these patterns
        Include = @('*.Tests.ps1')

        # Exclude test files matching these patterns
        Exclude = @('*.Skip.Tests.ps1', '*.Manual.Tests.ps1')
    }

    # Test execution settings
    Execution = @{
        # Stop on first failure for fast feedback
        StopOnFirstFailure = $false

        # Retry failed tests
        RetryFailedTests = $false

        # Test timeout in seconds
        TestTimeout = 300
    }

    # Output settings
    Output = @{
        # Verbosity levels: None, Normal, Detailed, Diagnostic
        Verbosity = 'Normal'

        # Show test progress
        ShowProgress = $true

        # Show test timing
        ShowTiming = $true

        # Stack trace verbosity: None, Filtered, Full
        StackTraceVerbosity = 'Filtered'
    }

    # Code coverage settings
    CodeCoverage = @{
        # Enable code coverage by default
        Enabled = $true

        # Output format: JaCoCo, CoverageGutters
        OutputFormat = 'JaCoCo'

        # Coverage threshold percentage
        CoveragePercentTarget = 80

        # Paths to include in coverage analysis
        Path = @(
            'source/modules/*.ps1'
            'source/modules/Private/*.ps1'
            'build-PwshRuntimeLayer.ps1'
        )

        # Paths to exclude from coverage
        ExcludeTests = $true

        # Use breakpoints for coverage (more accurate but slower)
        UseBreakpoints = $false
    }

    # Test result reporting
    TestResult = @{
        # Enable test result output
        Enabled = $true

        # Output format: NUnitXml, JUnitXml
        OutputFormat = 'NUnitXml'

        # Include test hierarchy in results
        IncludeVSCodeMarker = $true
    }

    # Parallel execution settings (experimental)
    Parallel = @{
        # Enable parallel execution
        Enabled = $false

        # Maximum number of parallel jobs
        MaxJobs = 4

        # Parallel execution scope: Context, Describe, It
        Scope = 'Context'
    }

    # Mock settings
    Mock = @{
        # Enable mock verification
        VerifyMocks = $true

        # Mock call history retention
        RetainHistory = $true

        # Strict mock verification
        StrictMode = $false
    }

    # Environment settings
    Environment = @{
        # Clean environment variables between tests
        CleanEnvironment = $true

        # Preserve specific environment variables
        PreserveVariables = @(
            'PATH'
            'PSModulePath'
            'TEMP'
            'TMP'
        )

        # Test-specific environment variables
        TestVariables = @{
            'AWS_LAMBDA_RUNTIME_API' = 'localhost:9001'
            'AWS_REGION' = 'us-east-1'
            'AWS_DEFAULT_REGION' = 'us-east-1'
            '_HANDLER' = 'test.handler'
            'LAMBDA_TASK_ROOT' = '/var/task'
            'LAMBDA_RUNTIME_DIR' = '/var/runtime'
        }
    }

    # Debugging settings
    Debug = @{
        # Enable debug output
        Enabled = $false

        # Show mock call details
        ShowMockCalls = $false

        # Show test setup/teardown details
        ShowSetupTeardown = $false

        # Write debug information to file
        WriteToFile = $false

        # Debug output file path
        OutputPath = 'debug-output.log'
    }
}