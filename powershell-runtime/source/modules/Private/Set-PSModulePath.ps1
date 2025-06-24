# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function private:Set-PSModulePath {
    <#
        .SYNOPSIS
            Modify $env:PSModulePath to support Lambda module file paths.

        .DESCRIPTION
            Modify $env:PSModulePath to support Lambda module file paths.

        .Notes
            Module folders are added in a specific order:
                1: Modules supplied with pwsh
                2: User supplied modules as part of Lambda Layers
                3: User supplied modules as part of function package
                4: Compressed modules
    #>
    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Set-PSModulePath]Start: Set-PSModulePath' }
    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Set-PSModulePath]Setting PSModulePath environment variable' }
    $env:PSModulePath = @(
        '/opt/powershell/modules', # Modules supplied with pwsh
        '/opt/modules', # User supplied modules as part of Lambda Layers
        [System.IO.Path]::Combine($env:LAMBDA_TASK_ROOT, 'modules') # User supplied modules as part of function package
    ) -join ':'
    If (Test-RuntimePackedModule -Combined) {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Set-PSModulePath]Combined module package detected, adding unpack directory to PSModulePath" }
        $env:PSModulePath += (':' + '/tmp/powershell-custom-runtime-unpacked-modules/combined') # Modules unpacked via Import-ModuleArchive
    }
    If (Test-RuntimePackedModule -NuPkg) {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Set-PSModulePath]Nupkg module package(s) detected, adding unpack directory to PSModulePath" }
        $env:PSModulePath += (':' + '/tmp/powershell-custom-runtime-unpacked-modules/nupkg') # Modules unpacked via Import-ModulePackage
    }
    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Set-PSModulePath]PSModulePath environment variable set to: $($env:PSModulePath)" }
}
