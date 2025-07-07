@{
    # Test configuration settings
    PrivateData = @{
        TestSettings = @{
            # Output configuration
            OutputFormat = 'NUnitXml'
            OutputFile = 'TestResults.xml'

            # Code coverage settings
            CodeCoverage = @{
                Enabled = $true
                OutputFile = 'CodeCoverage.xml'
                OutputFormat = 'JaCoCo'
                Threshold = 80
            }

            # Parallel execution settings
            Parallel = @{
                Enabled = $true
                MaxJobs = 4
            }

            # Test discovery settings
            TestPath = @(
                'tests/unit'
                'tests/integration'
            )

            # Timeout settings (in seconds)
            Timeout = @{
                Unit = 30
                Integration = 120
                Build = 300
            }
        }

        # Mock configuration
        MockSettings = @{
            RuntimeApiUrl = 'http://localhost:9001'
            DefaultTimeout = 30
            VerboseLogging = $false
            RetryAttempts = 3
        }

        # CI/CD specific settings
        CISettings = @{
            FailOnCoverageThreshold = $true
            GenerateTestReport = $true
            UploadArtifacts = $true
            ParallelExecution = $true
        }
    }
}