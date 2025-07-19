function private:Import-ModulePackage {
    <#
    .SYNOPSIS
        Installs compressed PowerShell modules from NuGet packages (*.nupkg)
    .DESCRIPTION
        Installs compressed PowerShell modules from NuGet packages (*.nupkg) into a subdirectory of /tmp.

        This folder is later added to $env:PSModulePath, before user code runs, if module packages existed.
    .NOTES
        These packages should match the NuPkg format used by PSResourceGet or PowerShellGet.

        Packages can be exported either by:
        * Downloading the .nupkg files directly from an upstream source (e.g. PowerShell Gallery)
        * Using the -AsNuPkg parameter on Save-PSResource in the Microsoft.PowerShell.PSResourceGet module.

        Module packages are imported from two locations, from lowest to highest precedence:
        * /opt/module-nupkgs/ (Combined Lambda layer directory)
        * $Env:LAMBDA_TASK_ROOT/module-nupkgs/ (Lambda Function Package deployment directory)
    #>
    $SearchPaths = $Script:ModulePaths.Packed.NuPkg

    If ($SearchPaths.Values | Where-Object { Test-Path $_ }) {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Import-ModulePackage]Creating unpack directory for individual module packages' }
        [System.IO.Directory]::CreateDirectory($Script:ModulePaths.Unpacked.NuPkg)
        $SearchPaths.GetEnumerator() | Where-Object { Test-Path $_.Value } | ForEach-Object {
            $PackageDirectory = Split-Path $_.Value -Parent
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Importing module packages from $PackageDirectory" }
            $RepositoryName = "Lambda-Local-$($_.Key)"
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Registering local package repository $RepositoryName" }
            Register-PSResourceRepository -Name $RepositoryName -Uri $PackageDirectory -Trusted -Priority 1
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Enumerating packages in $PackageDirectory (PSResource repository $RepositoryName)" }
            Find-PSResource -Name * -Repository $RepositoryName | ForEach-Object -Parallel {
                if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Saving package $($_.Name) version $($_.Version) (PSResource repository $($using:RepositoryName))" }
                $_ | Save-PSResource -SkipDependencyCheck -Path $using:PackageDirectory -Quiet -AcceptLicense -Confirm:$false
            }
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Registering local package repository $RepositoryName" }
            Unregister-PSResourceRepository -Name $RepositoryName -Confirm:$false
        }
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Import-ModulePackage]Archive unpack complete' }
    }
    else {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Import-ModulePackage]No module archives detected; nothing to do.' }
    }

}