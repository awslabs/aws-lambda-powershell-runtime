# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

Set-PSDebug -Strict

$Script:ModulePaths = @{
    Packed = @{
        Combined = @{
            Layer = "/opt/modules.zip"
            Root = "$Env:LAMBDA_TASK_ROOT/modules.zip"
        }
        NuPkg = @{
            Layer = "/opt/module-nupkgs/*.nupkg"
            Root = "$Env:LAMBDA_TASK_ROOT/module-nupkgs/*.nupkg"
        }
    }
    Unpacked = @{
        Combined = '/tmp/powershell-custom-runtime-unpacked-modules/combined'
        NuPkg = '/tmp/powershell-custom-runtime-unpacked-modules/nupkg'
    }
}

##### All code below this comment is excluded from the build process

# All Private modules merged into this file during build process to speed up module loading.

# Conditional loading of private functions
# This section is only used when testing source files directly
# During the build process, private functions are merged into this file and this directory is removed
$privateFunctionsPath = Join-Path $PSScriptRoot 'Private'
if (Test-Path $privateFunctionsPath) {
    # We're running from source - dot-source all private functions
    Get-ChildItem -Path $privateFunctionsPath -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }
}
