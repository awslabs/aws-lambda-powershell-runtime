# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

@{
    RootModule = 'test-module-handler.psm1'
    ModuleVersion = '1.0.0'
    GUID = '12345678-1234-1234-1234-123456789012'
    Author = 'AWS'
    CompanyName = 'Amazon Web Services'
    Copyright = 'Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.'
    Description = 'Test module for PowerShell Lambda Runtime integration tests'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Invoke-TestModuleHandler')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('AWS', 'Lambda', 'PowerShell', 'Test')
            LicenseUri = 'https://github.com/awslabs/aws-lambda-powershell-runtime/blob/main/LICENSE'
            ProjectUri = 'https://github.com/awslabs/aws-lambda-powershell-runtime'
        }
    }
}