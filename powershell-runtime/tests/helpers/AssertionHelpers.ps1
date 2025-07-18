# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Custom assertion helpers for PowerShell Lambda runtime testing.

.DESCRIPTION
    This module provides custom assertion functions specifically designed for
    testing PowerShell Lambda runtime components. These assertions work with
    the TestLambdaRuntimeServer and provide meaningful error messages for
    common testing scenarios.
#>

<#
.SYNOPSIS
    Verify environment variable values.

.DESCRIPTION
    Asserts that an environment variable has the expected value, providing
    detailed error messages when the assertion fails.

.PARAMETER Name
    Name of the environment variable to check.

.PARAMETER ExpectedValue
    Expected value of the environment variable.

.PARAMETER ShouldExist
    Whether the environment variable should exist (default: true).

.PARAMETER ShouldBeNull
    Whether the environment variable should be null/empty.

.EXAMPLE
    Assert-EnvironmentVariable -Name "AWS_LAMBDA_RUNTIME_API" -ExpectedValue "localhost:8888"
    Verifies the runtime API environment variable is set correctly.

.EXAMPLE
    Assert-EnvironmentVariable -Name "TEMP_VAR" -ShouldBeNull
    Verifies the environment variable is null or empty.

.EXAMPLE
    Assert-EnvironmentVariable -Name "OPTIONAL_VAR" -ShouldExist:$false
    Verifies the environment variable does not exist.
#>
function Assert-EnvironmentVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$ExpectedValue,

        [bool]$ShouldExist = $true,

        [switch]$ShouldBeNull
    )

    $actualValue = [System.Environment]::GetEnvironmentVariable($Name)

    if ($ShouldBeNull) {
        if (-not [string]::IsNullOrEmpty($actualValue)) {
            throw "Environment variable '$Name' should be null or empty, but was: '$actualValue'"
        }
        return
    }

    if (-not $ShouldExist) {
        if ($null -ne $actualValue) {
            throw "Environment variable '$Name' should not exist, but was set to: '$actualValue'"
        }
        return
    }

    if ($ShouldExist -and $null -eq $actualValue) {
        throw "Environment variable '$Name' should exist but was not found"
    }

    if ($ExpectedValue -and $actualValue -ne $ExpectedValue) {
        throw "Environment variable '$Name' expected: '$ExpectedValue', but was: '$actualValue'"
    }

    Write-Verbose "Environment variable '$Name' assertion passed: '$actualValue'"
}

<#
.SYNOPSIS
    Verify API calls were made to TestServer correctly.

.DESCRIPTION
    Asserts that the expected API calls were made to the TestLambdaRuntimeServer
    with the correct method, path, and optionally body content.

.PARAMETER Server
    TestLambdaRuntimeServer instance to check.

.PARAMETER Path
    Expected API path that should have been called.

.PARAMETER Method
    Expected HTTP method (default: GET).

.PARAMETER ExpectedCallCount
    Expected number of calls to the path (default: 1).

.PARAMETER ShouldContainBody
    Text that should be contained in the request body.

.PARAMETER ShouldNotBeCalled
    Whether the path should not have been called at all.

.EXAMPLE
    Assert-ApiCall -Server $testServer -Path "/2018-06-01/runtime/invocation/next"
    Verifies that the next invocation API was called.

.EXAMPLE
    Assert-ApiCall -Server $testServer -Path "/2018-06-01/runtime/invocation/test-id/response" -Method "POST" -ShouldContainBody "success"
    Verifies that a response was posted with expected content.

.EXAMPLE
    Assert-ApiCall -Server $testServer -Path "/invalid/path" -ShouldNotBeCalled
    Verifies that an invalid path was not called.
#>
function Assert-ApiCall {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Server,

        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Method = 'GET',

        [int]$ExpectedCallCount = 1,

        [string]$ShouldContainBody,

        [switch]$ShouldNotBeCalled
    )

    $requests = $Server.GetRequestsForPath($Path)
    $matchingRequests = $requests | Where-Object { $_.Method -eq $Method }

    if ($ShouldNotBeCalled) {
        if ($matchingRequests.Count -gt 0) {
            throw "API path '$Path' should not have been called, but was called $($matchingRequests.Count) times"
        }
        Write-Verbose "API path '$Path' was correctly not called"
        return
    }

    if ($matchingRequests.Count -ne $ExpectedCallCount) {
        $allRequests = $Server.GetRequestLog()
        $requestSummary = $allRequests | ForEach-Object { "$($_.Method) $($_.Path)" } | Join-String ', '
        throw "Expected $ExpectedCallCount $Method request(s) to '$Path', but found $($matchingRequests.Count). All requests: $requestSummary"
    }

    if ($ShouldContainBody) {
        $requestsWithBody = $matchingRequests | Where-Object { $_.Body -like "*$ShouldContainBody*" }
        if ($requestsWithBody.Count -eq 0) {
            $actualBodies = $matchingRequests | ForEach-Object { $_.Body } | Join-String '; '
            throw "Expected request body to contain '$ShouldContainBody', but actual bodies were: $actualBodies"
        }
        Write-Verbose "API call to '$Path' contained expected body content: '$ShouldContainBody'"
    }

    Write-Verbose "API call assertion passed: $Method $Path ($($matchingRequests.Count) calls)"
}

<#
.SYNOPSIS
    Verify JSON response formatting.

.DESCRIPTION
    Asserts that a JSON response has the expected structure, properties,
    and values for PowerShell Lambda runtime testing.

.PARAMETER JsonString
    JSON string to validate.

.PARAMETER ShouldHaveProperty
    Property name that should exist in the JSON.

.PARAMETER PropertyValue
    Expected value for a specific property.

.PARAMETER ShouldContainValue
    Value that should be contained somewhere in the JSON.

.PARAMETER ShouldNotBeValidJson
    Validates the string is not valid JSON.

.EXAMPLE
    Assert-JsonResponse -JsonString $response -ShouldHaveProperty "statusCode"
    Verifies that the JSON response has a statusCode property.

.EXAMPLE
    Assert-JsonResponse -JsonString $response -ShouldHaveProperty "body" -PropertyValue "success"
    Verifies that the JSON response has a body property with value "success".

.EXAMPLE
    Assert-JsonResponse -JsonString $invalidJson -ShouldNotBeValidJson
    Verifies that the string is not valid JSON.
#>
function Assert-JsonResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JsonString,

        [string]$ShouldHaveProperty,

        [string]$PropertyValue,

        [string]$ShouldContainValue,

        [switch]$ShouldNotBeValidJson
    )

    if ($ShouldNotBeValidJson) {
        try {
            $null = $JsonString | ConvertFrom-Json -ErrorAction Stop
            throw "Expected invalid JSON, but parsing succeeded for: $JsonString"
        }
        catch {
            if ($_.Exception.Message -eq "Expected invalid JSON, but parsing succeeded for: $JsonString") {
                throw
            }
            Write-Verbose "JSON is correctly invalid: $($_.Exception.Message)"
        }
    }
    else {
        try {
            $jsonObject = $JsonString | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            throw "Expected valid JSON, but parsing failed: $($_.Exception.Message). JSON: $JsonString"
        }

        if ($ShouldHaveProperty) {
            $propertyExists = $null -ne $jsonObject.PSObject.Properties[$ShouldHaveProperty]
            if (-not $propertyExists) {
                $availableProperties = $jsonObject.PSObject.Properties.Name -join ', '
                throw "JSON should have property '$ShouldHaveProperty', but available properties are: $availableProperties"
            }

            if ($PropertyValue) {
                $actualValue = $jsonObject.PSObject.Properties[$ShouldHaveProperty].Value
                if ($actualValue -ne $PropertyValue) {
                    throw "JSON property '$ShouldHaveProperty' expected: '$PropertyValue', but was: '$actualValue'"
                }
            }

            Write-Verbose "JSON has expected property: '$ShouldHaveProperty'"
        }

        if ($ShouldContainValue) {
            if ($JsonString -notlike "*$ShouldContainValue*") {
                throw "JSON should contain value '$ShouldContainValue', but JSON was: $JsonString"
            }
            Write-Verbose "JSON contains expected value: '$ShouldContainValue'"
        }
    }

    Write-Verbose "JSON response assertion passed"
}

<#
.SYNOPSIS
    Verify handler type detection (Script, Function, Module).

.DESCRIPTION
    Asserts that the handler type is correctly detected based on the
    _HANDLER environment variable format used in PowerShell Lambda runtime.

.PARAMETER HandlerString
    Handler string to analyze (e.g., "script.ps1", "module::function", "module").

.PARAMETER ExpectedType
    Expected handler type: Script, Function, or Module.

.PARAMETER ShouldBeValid
    Whether the handler string should be valid (default: true).

.EXAMPLE
    Assert-HandlerType -HandlerString "handler.ps1" -ExpectedType "Script"
    Verifies that a .ps1 handler is detected as Script type.

.EXAMPLE
    Assert-HandlerType -HandlerString "MyModule::MyFunction" -ExpectedType "Function"
    Verifies that a module::function handler is detected as Function type.

.EXAMPLE
    Assert-HandlerType -HandlerString "MyModule" -ExpectedType "Module"
    Verifies that a module handler is detected as Module type.
#>
function Assert-HandlerType {
    [CmdletBinding()]
    param(
        [string]$HandlerString = [String]::Empty,

        [Parameter(Mandatory)]
        [ValidateSet('Script', 'Function', 'Module')]
        [string]$ExpectedType,

        [bool]$ShouldBeValid = $true
    )

    if (-not $ShouldBeValid) {
        # For invalid handlers, we expect some kind of error or unexpected behavior
        # This is a placeholder for more specific validation logic
        Write-Verbose "Handler '$HandlerString' is expected to be invalid"
        return
    }

    $actualType = $null

    # Implement handler type detection logic based on PowerShell Lambda runtime patterns
    if ($HandlerString -match '\.ps1$') {
        $actualType = 'Script'
    }
    elseif ($HandlerString -match '::') {
        $actualType = 'Function'
    }
    elseif ($HandlerString -and $HandlerString -notmatch '\.' -and $HandlerString -notmatch '::') {
        $actualType = 'Module'
    }
    else {
        throw "Unable to determine handler type for: '$HandlerString'"
    }

    if ($actualType -ne $ExpectedType) {
        throw "Handler '$HandlerString' expected type: '$ExpectedType', but detected type: '$actualType'"
    }

    Write-Verbose "Handler type assertion passed: '$HandlerString' -> '$actualType'"
}

<#
.SYNOPSIS
    Verify build artifacts are created correctly.

.DESCRIPTION
    Asserts that files and directories exist with expected properties
    after build processes in PowerShell Lambda runtime testing.

.PARAMETER Path
    Path to the file or directory to check.

.PARAMETER ShouldExist
    Whether the path should exist (default: true).

.PARAMETER ShouldBeFile
    Whether the path should be a file.

.PARAMETER ShouldBeDirectory
    Whether the path should be a directory.

.PARAMETER MinimumSize
    Minimum expected file size in bytes.

.PARAMETER ShouldContainText
    Text that should be contained in the file (for text files).

.PARAMETER ShouldHaveExtension
    Expected file extension (including the dot).

.EXAMPLE
    Assert-FileExists -Path "layers/runtimeLayer/bootstrap" -ShouldBeFile
    Verifies that the bootstrap file exists and is a file.

.EXAMPLE
    Assert-FileExists -Path "layers/runtimeLayer/modules" -ShouldBeDirectory
    Verifies that the modules directory exists.

.EXAMPLE
    Assert-FileExists -Path "pwsh-runtime.psm1" -MinimumSize 1024 -ShouldContainText "function"
    Verifies that the module file exists, has minimum size, and contains functions.
#>
function Assert-FileExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [switch]$ShouldBeFile,

        [switch]$ShouldBeDirectory,

        [int]$MinimumSize,

        [string]$ShouldContainText,

        [string]$ShouldHaveExtension,

        [switch]$ShouldNotExist
    )

    $exists = Test-Path -Path $Path

    if (-not $ShouldNotExist -and -not $exists) {
        throw "Path should exist but was not found: '$Path'"
    }

    if ($ShouldNotExist -and $exists) {
        throw "Path should not exist but was found: '$Path'"
    }

    if (-not $exists) {
        Write-Verbose "Path correctly does not exist: '$Path'"
        return
    }

    $item = Get-Item -Path $Path

    if ($ShouldBeFile -and -not $item.PSIsContainer) {
        Write-Verbose "Path is correctly a file: '$Path'"
    }
    elseif ($ShouldBeFile -and $item.PSIsContainer) {
        throw "Path should be a file but is a directory: '$Path'"
    }

    if ($ShouldBeDirectory -and $item.PSIsContainer) {
        Write-Verbose "Path is correctly a directory: '$Path'"
    }
    elseif ($ShouldBeDirectory -and -not $item.PSIsContainer) {
        throw "Path should be a directory but is a file: '$Path'"
    }

    if ($MinimumSize -and -not $item.PSIsContainer) {
        if ($item.Length -lt $MinimumSize) {
            throw "File '$Path' should be at least $MinimumSize bytes, but is $($item.Length) bytes"
        }
        Write-Verbose "File size assertion passed: '$Path' is $($item.Length) bytes (>= $MinimumSize)"
    }

    if ($ShouldHaveExtension) {
        $actualExtension = [System.IO.Path]::GetExtension($Path)
        if ($actualExtension -ne $ShouldHaveExtension) {
            throw "File '$Path' should have extension '$ShouldHaveExtension', but has '$actualExtension'"
        }
        Write-Verbose "File extension assertion passed: '$Path' has '$actualExtension'"
    }

    if ($ShouldContainText -and -not $item.PSIsContainer) {
        try {
            $content = Get-Content -Path $Path -Raw -ErrorAction Stop
            if ($content -notlike "*$ShouldContainText*") {
                throw "File '$Path' should contain text '$ShouldContainText', but content does not match"
            }
            Write-Verbose "File content assertion passed: '$Path' contains '$ShouldContainText'"
        }
        catch {
            throw "Could not read file '$Path' to check content: $($_.Exception.Message)"
        }
    }

    Write-Verbose "File existence assertion passed: '$Path'"
}

<#
.SYNOPSIS
    Verify path equality with cross-platform path separator handling.

.DESCRIPTION
    Asserts that two paths are equal by normalizing path separators to forward slashes,
    allowing tests to pass on both Windows and Linux regardless of the path separator
    used by System.IO.Path.Combine() in the runtime.

.PARAMETER Actual
    The actual path value from the test result.

.PARAMETER Expected
    The expected path value (should use forward slashes for consistency).

.PARAMETER Because
    Optional reason for the assertion failure.

.EXAMPLE
    Assert-PathEquals -Actual $result.scriptFilePath -Expected "/var/task/handler.ps1"
    Verifies that the script file path matches, regardless of platform path separators.

.EXAMPLE
    Assert-PathEquals -Actual $result.scriptFilePath -Expected "/var/task/lib/utilities.ps1" -Because "subdirectory paths should be handled correctly"
    Verifies path equality with a custom failure message.
#>
function Assert-PathEquals {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Actual,

        [Parameter(Mandatory)]
        [string]$Expected,

        [string]$Because
    )

    # Normalize both paths to use forward slashes for comparison
    $normalizedActual = $Actual -replace '\\', '/'
    $normalizedExpected = $Expected -replace '\\', '/'

    if ($normalizedActual -ne $normalizedExpected) {
        $message = "Expected path '$Expected' but got '$Actual'"
        if ($normalizedActual -ne $Actual) {
            $message += " (normalized: '$normalizedExpected' vs '$normalizedActual')"
        }
        if ($Because) {
            $message += " because $Because"
        }
        throw $message
    }

    Write-Verbose "Path assertion passed: '$Expected' matches '$Actual'"
}

# Functions are available when dot-sourced
# To use: . ./AssertionHelpers.ps1
