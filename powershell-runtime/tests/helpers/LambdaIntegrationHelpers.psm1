# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Helper functions for Lambda integration tests.

.DESCRIPTION
    This module provides consolidated validation functions, schema-based validation,
    and utilities to reduce code duplication in Lambda integration tests.
#>

# Lambda Context validation schema
$script:LambdaContextSchema = @{
    AwsRequestId              = @{
        Type      = 'String'
        Required  = $true
        Validator = 'UUID'
    }
    FunctionName              = @{
        Type         = 'String'
        Required     = $true
        MatchesInput = $true
    }
    FunctionVersion           = @{
        Type      = 'String'
        Required  = $true
        Validator = 'VersionFormat'
    }
    InvokedFunctionArn        = @{
        Type      = 'String'
        Required  = $true
        Validator = 'ARN'
    }
    MemoryLimitInMB           = @{
        Type      = 'Long'
        Required  = $true
        Validator = 'LambdaMemory'
    }
    LogGroupName              = @{
        Type      = 'String'
        Required  = $false
        Validator = 'LogGroupFormat'
    }
    LogStreamName             = @{
        Type      = 'String'
        Required  = $false
        Validator = 'LogStreamFormat'
    }
    Identity                  = @{
        Type      = 'Object'
        Required  = $false
        AllowNull = $true
    }
    ClientContext             = @{
        Type      = 'Object'
        Required  = $false
        AllowNull = $true
    }
    RemainingTimeMs           = @{
        Type      = 'Double'
        Required  = $true
        Validator = 'PositiveTime'
    }
    RemainingTimeMillisMethod = @{
        Type      = 'Double'
        Required  = $true
        Validator = 'PositiveTime'
    }
    RemainingTimeSpan         = @{
        Type     = 'String'
        Required = $true
    }
    HasValidRequestId         = @{
        Type          = 'Boolean'
        Required      = $true
        ExpectedValue = $true
    }
    HasValidFunctionName      = @{
        Type          = 'Boolean'
        Required      = $true
        ExpectedValue = $true
    }
    TimeMethodsConsistent     = @{
        Type          = 'Boolean'
        Required      = $true
        ExpectedValue = $true
    }
}

# Validation rules
$script:ValidationRules = @{
    UUID            = @{
        Pattern     = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        Description = 'valid UUID format'
    }
    ARN             = @{
        Pattern          = '^arn:aws:lambda:'
        Description      = 'valid Lambda ARN format'
        AdditionalChecks = @('FunctionArnStructure')
    }
    VersionFormat   = @{
        CustomValidator = 'Test-VersionFormat'
        Description     = 'valid version format ($LATEST or number)'
    }
    LambdaMemory    = @{
        CustomValidator = 'Test-LambdaMemorySize'
        Description     = 'valid Lambda memory configuration'
    }
    LogGroupFormat  = @{
        Pattern     = '^/aws/lambda/'
        Description = 'valid CloudWatch log group format'
    }
    LogStreamFormat = @{
        Pattern     = '^\d{4}/\d{2}/\d{2}/\[.*\]'
        Description = 'valid CloudWatch log stream format'
    }
    PositiveTime    = @{
        CustomValidator = 'Test-PositiveTime'
        Description     = 'positive time value'
    }
}

# Response cache for reducing Lambda invocations
$script:HandlerResponseCache = @{}

function Initialize-HandlerResponseCache {
    <#
    .SYNOPSIS
        Initializes the handler response cache by invoking all Lambda functions once.
    #>
    param(
        [Parameter(Mandatory)]
        [array]$HandlerConfigs,

        [Parameter(Mandatory)]
        [string]$Region,

        [string]$ProfileName
    )

    $awsAuth = @{
        Region = $Region
    }
    if ($ProfileName) {
        $awsAuth['ProfileName'] = $ProfileName
    }

    $script:HandlerResponseCache = @{}

    foreach ($config in $HandlerConfigs) {
        Write-Verbose "Caching response for $($config.HandlerType) handler"

        $payload = New-TestPayload -TestKey $config.TestKey -AdditionalData $config.TestData
        $response = Invoke-TestLambdaFunction -FunctionName $config.FunctionName -Payload $payload $awsAuth

        $script:HandlerResponseCache[$config.HandlerType] = @{
            Response = $response
            Config   = $config
        }
    }
}

function Get-CachedHandlerResponse {
    <#
    .SYNOPSIS
        Retrieves a cached handler response.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$HandlerType
    )

    if (-not $script:HandlerResponseCache.ContainsKey($HandlerType)) {
        throw "No cached response found for handler type: $HandlerType"
    }

    return $script:HandlerResponseCache[$HandlerType]
}

function Assert-DeepEqual {
    <#
    .SYNOPSIS
        Performs deep equality comparison between actual and expected values.
    #>
    param(
        $Actual,
        $Expected,
        [string]$Path = "root"
    )

    if ($null -eq $Expected) {
        $Actual | Should -BeNullOrEmpty -Because "$Path should be null or empty"
        return
    }

    switch ($Expected.GetType().Name) {
        'Object[]' {
            $Actual | Should -Not -BeNullOrEmpty -Because "$Path array should not be null"
            $Actual.Count | Should -Be $Expected.Count -Because "$Path array length should match"

            for ($i = 0; $i -lt $Expected.Count; $i++) {
                Assert-DeepEqual -Actual $Actual[$i] -Expected $Expected[$i] -Path "$Path[$i]"
            }
        }
        'Boolean' {
            if ($Expected) {
                $Actual | Should -BeTrue -Because "$Path should be true"
            }
            else {
                $Actual | Should -BeFalse -Because "$Path should be false"
            }
        }
        'Hashtable' {
            $Actual | Should -Not -BeNullOrEmpty -Because "$Path hashtable should not be null"

            foreach ($key in $Expected.Keys) {
                $Actual.PSObject.Properties.Name | Should -Contain $key -Because "$Path should contain key '$key'"
                Assert-DeepEqual -Actual $Actual.$key -Expected $Expected[$key] -Path "$Path.$key"
            }
        }
        default {
            $Actual | Should -Be $Expected -Because "$Path value should match expected"
        }
    }
}

function Test-VersionFormat {
    <#
    .SYNOPSIS
        Validates Lambda function version format.
    #>
    param([string]$Version)

    $isLatest = $Version -eq '$LATEST'
    $isNumber = $Version -match '^\d+$'

    return ($isLatest -or $isNumber)
}

function Test-LambdaMemorySize {
    <#
    .SYNOPSIS
        Validates Lambda memory size configuration.
    #>
    param([long]$MemoryMB)

    if ($MemoryMB -lt 128 -or $MemoryMB -gt 10240) {
        return $false
    }

    # Memory must be in 1 MB increments from 128 MB to 3,008 MB
    # and in 64 MB increments from 3,008 MB to 10,240 MB
    if ($MemoryMB -le 3008) {
        return (($MemoryMB - 128) % 1 -eq 0)
    }
    else {
        return (($MemoryMB - 3008) % 64 -eq 0)
    }
}

function Test-PositiveTime {
    <#
    .SYNOPSIS
        Validates that time value is positive and reasonable.
    #>
    param([double]$TimeMs)

    return ($TimeMs -gt 0 -and $TimeMs -lt 900000) # Less than 15 minutes
}

function Test-TimeConsistency {
    <#
    .SYNOPSIS
        Validates that time methods return consistent values.
    #>
    param(
        [double]$RemainingTimeMs,
        [double]$RemainingTimeMillisMethod,
        [double]$ToleranceMs = 100
    )

    $difference = [Math]::Abs($RemainingTimeMs - $RemainingTimeMillisMethod)
    return ($difference -lt $ToleranceMs)
}

function Assert-ValidationRule {
    <#
    .SYNOPSIS
        Applies a validation rule to a value.
    #>
    param(
        $Value,
        [string]$RuleName,
        [string]$PropertyName
    )

    $rule = $script:ValidationRules[$RuleName]
    if (-not $rule) {
        throw "Unknown validation rule: $RuleName"
    }

    if ($rule.Pattern) {
        $Value | Should -Match $rule.Pattern -Because "$PropertyName should have $($rule.Description)"
    }

    if ($rule.CustomValidator) {
        $isValid = & $rule.CustomValidator $Value
        $isValid | Should -BeTrue -Because "$PropertyName should have $($rule.Description)"
    }

    if ($rule.AdditionalChecks) {
        foreach ($check in $rule.AdditionalChecks) {
            switch ($check) {
                'FunctionArnStructure' {
                    $Value | Should -Match ':function:' -Because "$PropertyName should contain ':function:'"
                }
            }
        }
    }
}

function Assert-LambdaContextSchema {
    <#
    .SYNOPSIS
        Validates Lambda context against the defined schema.
    #>
    param(
        [Parameter(Mandatory)]
        $ContextInfo,

        [Parameter(Mandatory)]
        [string]$FunctionName
    )

    # Validate all schema properties
    foreach ($propertyName in $script:LambdaContextSchema.Keys) {
        $schema = $script:LambdaContextSchema[$propertyName]
        $actualValue = $ContextInfo.$propertyName

        # Check if property exists
        $ContextInfo.PSObject.Properties.Name | Should -Contain $propertyName -Because "Context should contain $propertyName property"

        # Handle optional properties that can be null
        if (-not $schema.Required -and $schema.AllowNull -and $null -eq $actualValue) {
            continue
        }

        # Validate required properties are not null
        if ($schema.Required) {
            $actualValue | Should -Not -BeNullOrEmpty -Because "$propertyName should not be null or empty"
        }

        # Type validation
        if ($schema.Type -and $actualValue) {
            switch ($schema.Type) {
                'String' { $actualValue | Should -BeOfType [string] -Because "$propertyName should be a string" }
                'Long' { $actualValue | Should -BeOfType [long] -Because "$propertyName should be a long integer" }
                'Double' { $actualValue | Should -BeOfType [double] -Because "$propertyName should be a double" }
                'Boolean' { $actualValue | Should -BeOfType [bool] -Because "$propertyName should be a boolean" }
            }
        }

        # Expected value validation
        if ($schema.ExpectedValue) {
            $actualValue | Should -Be $schema.ExpectedValue -Because "$propertyName should be $($schema.ExpectedValue)"
        }

        # Custom validation rules
        if ($schema.Validator -and $actualValue) {
            Assert-ValidationRule -Value $actualValue -RuleName $schema.Validator -PropertyName $propertyName
        }

        # Special validations
        if ($schema.MatchesInput -and $propertyName -eq 'FunctionName') {
            $actualValue | Should -Be $FunctionName -Because "FunctionName should match the invoked function"
        }
    }

    # Validate time consistency
    $timeConsistent = Test-TimeConsistency -RemainingTimeMs $ContextInfo.RemainingTimeMs -RemainingTimeMillisMethod $ContextInfo.RemainingTimeMillisMethod
    $timeConsistent | Should -BeTrue -Because "Time methods should return consistent values"
}

function Test-LambdaHandlerValidation {
    <#
    .SYNOPSIS
        Performs complete validation of a Lambda handler response.
    #>
    param(
        [Parameter(Mandatory)]
        $Response,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    # Basic response validation
    $Response | Should -Not -BeNullOrEmpty -Because "Response should not be null"
    $Response.statusCode | Should -Be 200 -Because "Response should have status code 200"
    $Response.body | Should -Not -BeNullOrEmpty -Because "Response body should not be empty"

    $responseBody = $Response.body | ConvertFrom-Json

    # Message validation
    $responseBody.message | Should -Be $Config.ExpectedMessage -Because "Response message should match expected"

    # Input validation using deep equality
    $responseBody.input | Should -Not -BeNullOrEmpty -Because "Response should contain input data"
    $responseBody.input.testKey | Should -Be $Config.TestKey -Because "Test key should match"

    # Validate test data using deep comparison
    Assert-DeepEqual -Actual $responseBody.input -Expected (@{ testKey = $Config.TestKey } + $Config.TestData)

    # Context validation
    $responseBody.contextInfo | Should -Not -BeNullOrEmpty -Because "Response should contain context info"
    Assert-LambdaContextSchema -ContextInfo $responseBody.contextInfo -FunctionName $Config.FunctionName
}

function New-TestPayload {
    <#
    .SYNOPSIS
        Creates a test payload for Lambda function invocation.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TestKey,

        [hashtable]$AdditionalData = @{}
    )

    $payload = @{
        "testKey"   = $TestKey
        "timestamp" = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    foreach ($key in $AdditionalData.Keys) {
        $payload[$key] = $AdditionalData[$key]
    }

    return ($payload | ConvertTo-Json -Depth 10)
}

function Get-AwsAuthParameters {
    <#
    .SYNOPSIS
        Creates a standardized AWS authentication hashtable for Lambda operations.

    .EXAMPLE
        $awsAuth = Get-AwsAuthParameters
        Invoke-LMFunction -FunctionName $functionName -Payload $payload @awsAuth
    #>
    [CmdletBinding()]
    param()

    # Set up AWS region from test environment
    $region = $env:PWSH_TEST_AWS_REGION
    if (-not $region) {
        $region = "us-east-1"
    }

    $awsAuth = @{
        Region = $region
    }

    if ($env:PWSH_TEST_PROFILE_NAME) {
        $awsAuth['ProfileName'] = $env:PWSH_TEST_PROFILE_NAME
    }

    return $awsAuth
}

function Invoke-TestLambdaFunction {
    <#
    .SYNOPSIS
        Invokes a Lambda function and returns the parsed response.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FunctionName,

        [Parameter(Mandatory)]
        [string]$Payload,

        [Parameter(Mandatory)]
        [hashtable]$AwsAuth
    )

    $result = Invoke-LMFunction -FunctionName $FunctionName -Payload $Payload @AwsAuth
    $response = [System.IO.StreamReader]::new($result.Payload).ReadToEnd() | ConvertFrom-Json
    return $response
}

# Export functions
Export-ModuleMember -Function @(
    'Assert-DeepEqual',
    'Assert-LambdaContextSchema',
    'Get-AwsAuthParameters',
    'Get-CachedHandlerResponse',
    'Initialize-HandlerResponseCache',
    'Invoke-TestLambdaFunction',
    'New-TestPayload',
    'Test-LambdaHandlerValidation'
)
