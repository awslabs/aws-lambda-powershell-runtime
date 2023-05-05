Describe 'build-AWSToolsLayer' {
    BeforeAll {
        $ProgressPreference = 'SilentlyContinue'

        $TempFolder = "TestDrive:\Testing"
        $StagingPath = "$TempFolder\StagingPath"
        $LayerPath = "$TempFolder\LayerPath"
        $ModulePath = Join-Path -Path $LayerPath -ChildPath 'modules'

        $null = New-Item -Path $TempFolder -ItemType Directory -Force
        $SourceZipFile = Join-Path -Path $TempFolder -ChildPath 'AWS.Tools.zip'

        # Downloading the AWS.Tools zip file to prevent repeated downloads during testing.
        $invokeWebRequest = @{
            Uri = 'https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip'
            OutFile = $SourceZipFile
        }
        Invoke-WebRequest @invokeWebRequest

        $folder = Split-Path -Path $PSScriptRoot -Parent
        $sut = Join-Path -Path $folder -ChildPath 'build-AWSToolsLayer.ps1'

        # Prevent IDE warnings about variables not being used
        $null = $ModulePath, $StagingPath, $sut
    }

    AfterAll {
        if (Test-Path -Path $TempFolder) {
            $null = Remove-Item -Path $TempFolder -Recurse -Force
        }
    }

    BeforeEach {
        $StagingPath, $LayerPath, $ModulePath | ForEach-Object {
            if (Test-Path -Path $_) {
                $null = Remove-Item -Path $_ -Recurse
            }
        }

        # Prevent log statements
        function Write-Host {}
    }

    Context 'Successful Builds' {
        It 'Builds the layer with the AWS.Tools.Common module when provided defaults' {
            Test-Path -Path $ModulePath -PathType Container | Should -BeFalse

            & $sut -LayerPath $LayerPath -AWSToolsSource $SourceZipFile

            Test-Path -Path $ModulePath -PathType Container | Should -BeTrue
            'AWS.Tools.Common' | ForEach-Object {
                $awsModulePath = Join-Path -Path $ModulePath -ChildPath $_
                Test-Path -Path $awsModulePath -PathType Container | Should -BeTrue
                Get-ChildItem -Path $ModulePath -Recurse -Name "$_.psd1" -File | Should -HaveCount 1
            }
        }

        It 'Builds the layer with the correct AWS Tools for PowerShell modules when provided' -TestCases @(
            @{ModuleList = @('AWS.Tools.Common', 'AWS.Tools.S3')}
        ) {
            param ([string[]]$ModuleList)
            Test-Path -Path $ModulePath -PathType Container | Should -BeFalse

            & $sut -ModuleList $ModuleList -LayerPath $LayerPath -AWSToolsSource $SourceZipFile

            $ModuleList | ForEach-Object {
                Test-Path -Path (Join-Path -Path $ModulePath -ChildPath $_) -PathType Container | Should -BeTrue
                Get-ChildItem -Path $ModulePath -Recurse -Name "$_.psd1" -File | Should -HaveCount 1
            }
        }
    }

    Context 'Failures' {
        It 'Fails when an invalid AWS Tools for PowerShell module is provided' {
            { & $sut -ModuleList 'DoesNotExist' -LayerPath $LayerPath -AWSToolsSource $SourceZipFile } | Should -Throw
        }
    }
}