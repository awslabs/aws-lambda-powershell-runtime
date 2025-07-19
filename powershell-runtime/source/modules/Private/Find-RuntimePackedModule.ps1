function private:Find-RuntimePackedModule {
    <#
    .SYNOPSIS
        Searches runtime environment filesystem for compressed module packages (combined .zip or per-module .nupkg)
    .DESCRIPTION
        Searches the current runtime environment's filesystem for compressed module packages (combined .zip or per-module .nupkg). Any resolved paths are returned in a dictionary. If nothing is found, no object is returned.
    .NOTES
        Looks for module packages in two locations:
            * /opt/ (Combined Lambda layer directory)
            * $Env:LAMBDA_TASK_ROOT (Lambda Function package directory)

        Module packages can take two forms:
            * A single, combined module archive, named "modules.zip".
              The contents of this archive should match the format of a folder in $Env:PSModulePath.
              (Module names as top-level directories, optional version subdirectory, corresponding module root)
            * Individual module archives, as .nupkg files, inside a subdirectory named "module-nupkgs"
              These files should match:
                * The naming convention used by PSResourceGet. (e.g. <module-name>.<version>.nupkg)
                * The Nupkg archive spec (module root at archive root, NuGet [Content_Types].xml/_rels, etc.)

        The following file locations should all be detected (assume $Env:LAMBDA_TASK_ROOT = /var/lambda/)
        * /opt/modules.zip
        * /var/lambda/modules.zip
        * /opt/module-nupkgs/AWS.Tools.Common.4.1.833.nupkg
        * /var/lambda/module-nupkgs/AWS.Tools.Common.4.1.833.nupkg
    .EXAMPLE
        PS> Find-RuntimePackedModule
        Name                           Value
        ----                           -----
        Combined                       {/opt/modules.zip}
        NuPkg                          {/var/lambda/module-nupkgs/AWS.Tools.Common.4.1.833.nupkg, /var/lambda/module-nupkgs/AWS.Tools.S3.4.1.833.nupkg}
    #>

    [CmdletBinding()]
    param(
    )

    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Test-RuntimePackedModule]Searching for packed modules" }

    $ResolvedModules = @{
        Combined = $(
            $Script:ModulePaths.Packed.Combined.Values | Get-Item -ErrorAction SilentlyContinue
        )
        NuPkg = $(
            $Script:ModulePaths.Packed.NuPkg.Values | Get-Item -ErrorAction SilentlyContinue
        )
    }


    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Test-RuntimePackedModule]Found $($ResolvedModules.Combined | Measure-Object | ForEach-Object Count) combined module archive(s)" }
    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Test-RuntimePackedModule]Found $($ResolvedModules.NuPkg | Measure-Object | ForEach-Object Count) individual module package(s)" }

    # Only return a value if we found either combined or NuPkg module packages
    If ($ResolvedModules.Combined -or $ResolvedModules.NuPkg) {
        return $ResolvedModules
    }
}