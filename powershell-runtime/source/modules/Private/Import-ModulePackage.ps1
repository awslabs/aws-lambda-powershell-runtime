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
    [CmdletBinding()]
    param(
        [ValidatePattern(".nupkg$")]
        [ValidateNotNullOrEmpty()]
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [System.IO.FileInfo[]]$PackagePath
    )

    Begin {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Import-ModulePackage]Creating unpack directory for individual module packages' }
        $UnpackDirectory = [System.IO.Directory]::CreateDirectory($Script:ModulePaths.Unpacked.NuPkg)
    }

    Process {
        $PackagePath | Group-Object -Property Directory | ForEach-Object {

            # The group key should be the directory for the folder containing the nupkgs.
            $PackageDirectory = $_.Name
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Importing module packages from $PackageDirectory" }

            # We split-path that directory to strip off "module-nupkgs".
            $RepositoryName = "Lambda-Local-$($_.Group | Split-Path -Parent)"

            # Attach a PSResourceGet repository to the directory holding the packages.
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Registering local package repository $RepositoryName" }
            Register-PSResourceRepository -Name $RepositoryName -Uri $PackageDirectory -Trusted -Priority 1

            # Then, enumerate all the packages in that repository (again, just a directory) and "save" (install/unpack them) into /tmp.
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Enumerating packages in $PackageDirectory (PSResource repository $RepositoryName)" }
            Find-PSResource -Name * -Repository $RepositoryName | ForEach-Object -Parallel {
                if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Saving package $($_.Name) version $($_.Version) (PSResource repository $($using:RepositoryName))" }
                $_ | Save-PSResource -SkipDependencyCheck -Path $using:UnpackDirectory -Quiet -AcceptLicense -Confirm:$false
            }

            # Clean up the local repository config. This doesn't uninstall anything (just edits some XML files in PSResourceGet)
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModulePackage]Registering local package repository $RepositoryName" }
            Unregister-PSResourceRepository -Name $RepositoryName -Confirm:$false
        }
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Import-ModulePackage]Archive unpack complete' }
    }
}