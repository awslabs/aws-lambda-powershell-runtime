# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Test utilities for PowerShell Lambda runtime testing.

.DESCRIPTION
    This module provides common test functions for setting up test environments,
    managing modules, generating test events, and handling environment variables
    for PowerShell Lambda runtime testing.
#>

# Store original environment state for restoration
$script:OriginalEnvironment = @{}
$script:OriginalPSModulePath = $env:PSModulePath
$script:TestEnvironmentInitialized = $false

<#
.SYNOPSIS
    Initialize a clean test environment with proper module paths.

.DESCRIPTION
    Sets up a clean test environment by backing up current environment variables,
    configuring PSModulePath for testing, and preparing the environment for
    PowerShell Lambda runtime testing.

.PARAMETER TestModulesPath
    Optional path to test modules directory. Defaults to tests/fixtures/test-modules.

.PARAMETER SourceModulesPath
    Optional path to source modules directory. Defaults to source/modules.

.EXAMPLE
    Initialize-TestEnvironment
    Sets up test environment with default paths.

.EXAMPLE
    Initialize-TestEnvironment -TestModulesPath "custom/test/modules"
    Sets up test environment with custom test modules path.
#>
function Initialize-TestEnvironment {
    [CmdletBinding()]
    param(
        [string]$TestModulesPath,
        [string]$SourceModulesPath
    )

    if ($script:TestEnvironmentInitialized) {
        Write-Warning "Test environment already initialized. Call Reset-TestEnvironment first."
        return
    }

    # Store original environment variables
    $script:OriginalEnvironment = @{}

    # Common Lambda environment variables to backup
    $lambdaEnvVars = @(
        'AWS_LAMBDA_RUNTIME_API',
        '_HANDLER',
        'LAMBDA_TASK_ROOT',
        'AWS_LAMBDA_FUNCTION_NAME',
        'AWS_LAMBDA_FUNCTION_VERSION',
        'AWS_LAMBDA_FUNCTION_MEMORY_SIZE',
        'AWS_LAMBDA_LOG_GROUP_NAME',
        'AWS_LAMBDA_LOG_STREAM_NAME',
        'AWS_REGION',
        'AWS_DEFAULT_REGION',
        'TZ',
        'TEMP',
        'TMP'
    )

    foreach ($envVar in $lambdaEnvVars) {
        $script:OriginalEnvironment[$envVar] = [System.Environment]::GetEnvironmentVariable($envVar)
    }

    # Store original PSModulePath
    $script:OriginalPSModulePath = $env:PSModulePath

    # Set up test module paths
    $testRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

    if (-not $TestModulesPath) {
        $TestModulesPath = Join-Path $testRoot "fixtures/test-modules"
    }

    if (-not $SourceModulesPath) {
        $projectRoot = Split-Path -Parent $testRoot
        $SourceModulesPath = Join-Path $projectRoot "powershell-runtime/source/modules"
    }

    # Configure PSModulePath for testing
    $testPaths = @(
        $SourceModulesPath,
        $TestModulesPath
    )

    # Add existing paths but filter out user-specific paths for consistency
    $existingPaths = $env:PSModulePath -split [System.IO.Path]::PathSeparator | Where-Object {
        $_ -and (Test-Path $_) -and $_ -notlike "*Users*" -and $_ -notlike "*home*"
    }

    $allPaths = ($testPaths + $existingPaths) | Select-Object -Unique
    $env:PSModulePath = $allPaths -join [System.IO.Path]::PathSeparator

    # Set default test environment variables
    $env:AWS_LAMBDA_RUNTIME_API = "localhost:8888"
    $env:LAMBDA_TASK_ROOT = Join-Path $testRoot "fixtures/mock-handlers"
    $env:AWS_LAMBDA_FUNCTION_NAME = "test-function"
    $env:AWS_LAMBDA_FUNCTION_VERSION = "1"
    $env:AWS_LAMBDA_FUNCTION_MEMORY_SIZE = "128"
    $env:AWS_REGION = "us-east-1"
    $env:AWS_DEFAULT_REGION = "us-east-1"
    $env:TZ = "UTC"

    # Set temp directories for testing
    #$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "lambda-test-$(Get-Random)"
    #New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $env:TEMP = (Resolve-Path -Path 'TestDrive:\').Path
    $env:TMP = (Resolve-Path -Path 'TestDrive:\').Path

    $script:TestEnvironmentInitialized = $true
    Write-Verbose "Test environment initialized"
}

<#
.SYNOPSIS
    Clean up after tests and restore original state.

.DESCRIPTION
    Restores the original environment variables and PSModulePath,
    cleans up temporary files and directories created during testing.

.EXAMPLE
    Reset-TestEnvironment
    Restores the original environment state.
#>
function Reset-TestEnvironment {
    [CmdletBinding()]
    param()

    if (-not $script:TestEnvironmentInitialized) {
        # PowerShell automatically handles -WarningAction parameter by setting $WarningPreference
        if ($WarningPreference -ne 'SilentlyContinue') {
            Write-Warning "Test environment was not initialized"
        }
        return
    }

    # Restore original environment variables
    foreach ($envVar in $script:OriginalEnvironment.Keys) {
        $originalValue = $script:OriginalEnvironment[$envVar]
        if ($null -eq $originalValue) {
            [System.Environment]::SetEnvironmentVariable($envVar, $null)
        }
        else {
            [System.Environment]::SetEnvironmentVariable($envVar, $originalValue)
        }
    }

    # Restore original PSModulePath
    $env:PSModulePath = $script:OriginalPSModulePath

    # Clear stored state
    $script:OriginalEnvironment = @{}
    $script:TestEnvironmentInitialized = $false

    Write-Verbose "Test environment reset"
}

<#
.SYNOPSIS
    Load modules under test with proper isolation.

.DESCRIPTION
    Imports a PowerShell module for testing with proper isolation,
    ensuring that the module is loaded fresh and doesn't interfere
    with other tests.

.PARAMETER ModulePath
    Path to the module to import. Can be a .psd1, .psm1 file, or directory containing a module.

.PARAMETER Force
    Force reimport of the module even if already loaded.

.PARAMETER PassThru
    Return the imported module object.

.EXAMPLE
    Import-TestModule -ModulePath "source/modules/pwsh-runtime"
    Imports the pwsh-runtime module for testing.

.EXAMPLE
    $module = Import-TestModule -ModulePath "source/modules/pwsh-runtime.psm1" -PassThru
    Imports the module and returns the module object.
#>
function Import-TestModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModulePath,

        [switch]$Force,

        [switch]$PassThru
    )

    # Resolve the full path
    if (-not [System.IO.Path]::IsPathRooted($ModulePath)) {
        $testRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $projectRoot = Split-Path -Parent $testRoot
        $ModulePath = Join-Path $projectRoot $ModulePath
    }

    if (-not (Test-Path $ModulePath)) {
        throw "Module path not found: $ModulePath"
    }

    # Determine if it's a directory, .psd1, or .psm1
    if (Test-Path $ModulePath -PathType Container) {
        # Directory - look for .psd1 first, then .psm1
        $manifestPath = Get-ChildItem -Path $ModulePath -Filter "*.psd1" | Select-Object -First 1
        if ($manifestPath) {
            $ModulePath = $manifestPath.FullName
        }
        else {
            $modulePath = Get-ChildItem -Path $ModulePath -Filter "*.psm1" | Select-Object -First 1
            if ($modulePath) {
                $ModulePath = $modulePath.FullName
            }
            else {
                throw "No .psd1 or .psm1 file found in directory: $ModulePath"
            }
        }
    }

    # Get module name for removal if forcing
    $moduleName = [System.IO.Path]::GetFileNameWithoutExtension($ModulePath)

    if ($Force -and (Get-Module -Name $moduleName)) {
        Remove-Module -Name $moduleName -Force
    }

    try {
        $importedModule = Import-Module -Name $ModulePath -Force:$Force -PassThru:$PassThru -ErrorAction Stop
        Write-Verbose "Imported module: $moduleName"

        if ($PassThru) {
            return $importedModule
        }
    }
    catch {
        throw "Failed to import module '$ModulePath': $($_.Exception.Message)"
    }
}

<#
.SYNOPSIS
    Generate sample Lambda events for different scenarios.

.DESCRIPTION
    Creates sample Lambda event objects for testing different event types
    such as API Gateway, S3, CloudWatch, and custom events.

.PARAMETER EventType
    Type of event to generate. Valid values: ApiGateway, S3, CloudWatch, Custom.

.PARAMETER CustomData
    Custom data to include in the event (for Custom event type).

.PARAMETER HttpMethod
    HTTP method for API Gateway events (default: GET).

.PARAMETER Path
    Path for API Gateway events (default: /test).

.PARAMETER BucketName
    S3 bucket name for S3 events (default: test-bucket).

.PARAMETER ObjectKey
    S3 object key for S3 events (default: test-object.txt).

.EXAMPLE
    $event = New-TestEvent -EventType ApiGateway
    Creates a sample API Gateway event.

.EXAMPLE
    $event = New-TestEvent -EventType S3 -BucketName "my-bucket" -ObjectKey "my-file.txt"
    Creates a sample S3 event with custom bucket and object.

.EXAMPLE
    $event = New-TestEvent -EventType Custom -CustomData @{ message = "Hello World" }
    Creates a custom event with specified data.
#>
function New-TestEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ApiGateway', 'S3', 'CloudWatch', 'Custom')]
        [string]$EventType,

        [hashtable]$CustomData,

        [string]$HttpMethod = 'GET',

        [string]$Path = '/test',

        [string]$BucketName = 'test-bucket',

        [string]$ObjectKey = 'test-object.txt'
    )

    switch ($EventType) {
        'ApiGateway' {
            return @{
                resource              = $Path
                path                  = $Path
                httpMethod            = $HttpMethod
                headers               = @{
                    Accept       = "*/*"
                    Host         = "api.example.com"
                    'User-Agent' = "TestAgent"
                }
                queryStringParameters = @{
                    param1 = "value1"
                    param2 = "value2"
                }
                pathParameters        = @{
                    id = "123"
                }
                stageVariables        = $null
                requestContext        = @{
                    resourceId        = "abc123"
                    resourcePath      = $Path
                    httpMethod        = $HttpMethod
                    extendedRequestId = "request-id"
                    requestTime       = "01/Jan/2023:00:00:00 +0000"
                    path              = $Path
                    accountId         = "123456789012"
                    protocol          = "HTTP/1.1"
                    stage             = "test"
                    domainPrefix      = "api"
                    requestTimeEpoch  = 1672531200000
                    requestId         = "test-request-id-$(Get-Random)"
                    identity          = @{
                        cognitoIdentityPoolId         = $null
                        accountId                     = $null
                        cognitoIdentityId             = $null
                        caller                        = $null
                        sourceIp                      = "127.0.0.1"
                        principalOrgId                = $null
                        accessKey                     = $null
                        cognitoAuthenticationType     = $null
                        cognitoAuthenticationProvider = $null
                        userArn                       = $null
                        userAgent                     = "TestAgent"
                        user                          = $null
                    }
                    domainName        = "api.example.com"
                    apiId             = "api123"
                }
                body                  = $null
                isBase64Encoded       = $false
            }
        }

        'S3' {
            return @{
                Records = @(
                    @{
                        eventVersion      = "2.1"
                        eventSource       = "aws:s3"
                        eventTime         = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        eventName         = "s3:ObjectCreated:Put"
                        userIdentity      = @{
                            principalId = "test-principal"
                        }
                        requestParameters = @{
                            sourceIPAddress = "127.0.0.1"
                        }
                        responseElements  = @{
                            'x-amz-request-id' = "test-request-id-$(Get-Random)"
                            'x-amz-id-2'       = "test-id-2"
                        }
                        s3                = @{
                            s3SchemaVersion = "1.0"
                            configurationId = "test-config"
                            bucket          = @{
                                name          = $BucketName
                                ownerIdentity = @{
                                    principalId = "test-principal"
                                }
                                arn           = "arn:aws:s3:::$BucketName"
                            }
                            object          = @{
                                key       = $ObjectKey
                                size      = 1024
                                eTag      = "test-etag"
                                sequencer = "test-sequencer"
                            }
                        }
                    }
                )
            }
        }

        'CloudWatch' {
            return @{
                'account'     = "123456789012"
                'region'      = "us-east-1"
                'detail'      = @{
                    'test-key'  = 'test-value'
                    'timestamp' = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                }
                'detail-type' = "Test Event"
                'source'      = "test.application"
                'time'        = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                'id'          = "test-event-id-$(Get-Random)"
                'resources'   = @()
            }
        }

        'Custom' {
            $baseEvent = @{
                eventType = 'Custom'
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                requestId = "custom-request-id-$(Get-Random)"
            }

            if ($CustomData) {
                foreach ($key in $CustomData.Keys) {
                    $baseEvent[$key] = $CustomData[$key]
                }
            }

            return $baseEvent
        }
    }
}

<#
.SYNOPSIS
    Get paths to source modules for testing.

.DESCRIPTION
    Returns the path to source modules directory or specific module files
    for use in testing scenarios.

.PARAMETER ModuleName
    Optional specific module name to get path for.

.PARAMETER ReturnAll
    Return all available module paths.

.EXAMPLE
    $modulePath = Get-TestModulePath
    Gets the base source modules directory path.

.EXAMPLE
    $runtimePath = Get-TestModulePath -ModuleName "pwsh-runtime"
    Gets the path to the pwsh-runtime module.

.EXAMPLE
    $allPaths = Get-TestModulePath -ReturnAll
    Gets all available module paths.
#>
function Get-TestModulePath {
    [CmdletBinding()]
    param(
        [string]$ModuleName,

        [switch]$ReturnAll
    )

    $testRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $projectRoot = Split-Path -Parent $testRoot
    $sourceModulesPath = Join-Path $projectRoot "powershell-runtime/source/modules"

    if (-not (Test-Path $sourceModulesPath)) {
        throw "Source modules path not found: $sourceModulesPath"
    }

    if ($ReturnAll) {
        $allModules = @{}

        # Get .psd1 files
        Get-ChildItem -Path $sourceModulesPath -Filter "*.psd1" | ForEach-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            $allModules[$name] = $_.FullName
        }

        # Get .psm1 files
        Get-ChildItem -Path $sourceModulesPath -Filter "*.psm1" | ForEach-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            if (-not $allModules.ContainsKey($name)) {
                $allModules[$name] = $_.FullName
            }
        }

        return $allModules
    }

    if ($ModuleName) {
        # Look for specific module
        $manifestPath = Join-Path $sourceModulesPath "$ModuleName.psd1"
        if (Test-Path $manifestPath) {
            return $manifestPath
        }

        $modulePath = Join-Path $sourceModulesPath "$ModuleName.psm1"
        if (Test-Path $modulePath) {
            return $modulePath
        }

        throw "Module '$ModuleName' not found in source modules directory"
    }

    return $sourceModulesPath
}

<#
.SYNOPSIS
    Manage environment variables for testing.

.DESCRIPTION
    Sets environment variables for testing scenarios and provides
    utilities for managing Lambda-specific environment variables.

.PARAMETER Variables
    Hashtable of environment variables to set.

.PARAMETER Handler
    Lambda handler specification (sets _HANDLER environment variable).

.PARAMETER RuntimeApi
    Lambda runtime API endpoint (sets AWS_LAMBDA_RUNTIME_API).

.PARAMETER TaskRoot
    Lambda task root directory (sets LAMBDA_TASK_ROOT).

.PARAMETER FunctionName
    Lambda function name (sets AWS_LAMBDA_FUNCTION_NAME).

.PARAMETER Clear
    Clear specified environment variables instead of setting them.

.EXAMPLE
    Set-TestEnvironmentVariables -Handler "test-handler.ps1" -RuntimeApi "localhost:9001"
    Sets basic Lambda environment variables for testing.

.EXAMPLE
    Set-TestEnvironmentVariables -Variables @{ CUSTOM_VAR = "test-value" }
    Sets custom environment variables.

.EXAMPLE
    Set-TestEnvironmentVariables -Variables @{ TEMP = $null } -Clear
    Clears the TEMP environment variable.
#>
function Set-TestEnvironmentVariables {
    [CmdletBinding()]
    param(
        [hashtable]$Variables,

        [string]$Handler,

        [string]$RuntimeApi,

        [string]$TaskRoot,

        [string]$FunctionName,

        [switch]$Clear
    )

    # Build variables hashtable from parameters
    if (-not $Variables) {
        $Variables = @{
            POWERSHELL_VERSION = $PSVersionTable.PSVersion.ToString()
        }
    }

    if ($Handler) {
        $Variables['_HANDLER'] = $Handler
    }

    if ($RuntimeApi) {
        $Variables['AWS_LAMBDA_RUNTIME_API'] = $RuntimeApi
    }

    if ($TaskRoot) {
        $Variables['LAMBDA_TASK_ROOT'] = $TaskRoot
    }

    if ($FunctionName) {
        $Variables['AWS_LAMBDA_FUNCTION_NAME'] = $FunctionName
    }

    # Set or clear variables
    foreach ($varName in $Variables.Keys) {
        $varValue = $Variables[$varName]

        if ($Clear -or $null -eq $varValue) {
            [System.Environment]::SetEnvironmentVariable($varName, $null)
            Write-Verbose "Cleared environment variable: $varName"
        }
        else {
            [System.Environment]::SetEnvironmentVariable($varName, $varValue)
            Write-Verbose "Set environment variable: $varName = $varValue"
        }
    }
}

<#
.SYNOPSIS
    Import the PowerShell runtime module for testing with different execution modes.

.DESCRIPTION
    Imports the PowerShell runtime module using one of three modes:
    - TestSource: Import source module directly (fastest for development)
    - BuildModule: Build and import the merged module (default behavior)
    - NoBuild: Use existing built module without rebuilding (fastest for debugging)

.PARAMETER TestSource
.PARAMETER TestBuiltModule
    When true, test against the built module instead of source files.
    Default behavior (false) tests source files directly for faster development.

.PARAMETER FunctionName
    Optional name of the specific function being tested (for verbose output).

.EXAMPLE
    Import-RuntimeModuleForTesting
    Imports source files directly for testing (default - fast development mode).

.EXAMPLE
    Import-RuntimeModuleForTesting -TestBuiltModule
    Imports the built module for validation testing.

.EXAMPLE
    Import-RuntimeModuleForTesting -FunctionName "Get-LambdaNextInvocation"
    Imports source module for testing a specific function with verbose output.

.EXAMPLE
    Import-RuntimeModuleForTesting -TestBuiltModule -FunctionName "Get-LambdaNextInvocation"
    Imports built module for testing a specific function with verbose output.
#>
function Import-RuntimeModuleForTesting {
    [CmdletBinding()]
    param(
        [switch]$TestBuiltModule = $false,
        [string]$FunctionName
    )

    # Determine the project root path
    $testRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $projectRoot = Split-Path -Parent $testRoot

    if ($TestBuiltModule) {
        Write-Host "Testing built module (validation mode)" -ForegroundColor Yellow
        if ($FunctionName) {
            Write-Host "Testing function: $FunctionName" -ForegroundColor Yellow
        }

        # Import the built module (should already be built by Invoke-Tests.ps1)
        $builtModulePath = Join-Path $projectRoot "powershell-runtime/layers/runtimeLayer/modules/pwsh-runtime.psd1"
        if (Test-Path $builtModulePath) {
            Import-Module $builtModulePath -Force -Verbose:$false
            Write-Verbose "Imported built module from: $builtModulePath"
            Write-Host "Built module imported" -ForegroundColor Green
        } else {
            throw "Built module not found at: $builtModulePath. This should have been built by Invoke-Tests.ps1"
        }

    } else {
        Write-Host "Testing source files directly (fast development mode)" -ForegroundColor Cyan
        if ($FunctionName) {
            Write-Host "Testing function: $FunctionName" -ForegroundColor Cyan
        }

        # Import the source module - it will automatically dot-source private functions
        $sourceModulePath = Join-Path $projectRoot "powershell-runtime/source/modules/pwsh-runtime.psd1"
        if (Test-Path $sourceModulePath) {
            Import-Module $sourceModulePath -Force -Verbose:$false
            Write-Verbose "Imported source module from: $sourceModulePath"
            Write-Host "Source module imported with private functions" -ForegroundColor Green
        } else {
            throw "Source module not found at: $sourceModulePath"
        }
    }
}

# Functions are available when dot-sourced
# To use: . ./TestUtilities.ps1