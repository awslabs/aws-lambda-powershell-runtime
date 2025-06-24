function private:Test-RuntimePackedModule {
    <#
    .SYNOPSIS
        Tests whether the current runtime environment contains compressed module packages (combined .zip or per-module .nupkg)
    .DESCRIPTION
        Tests whether the current runtime environment contains compressed module packages (combined .zip or per-module .nupkg)
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
        Test-MyTestFunction -Verbose
        Explanation of the function or its result. You can include multiple examples with additional .EXAMPLE lines
    #>

    [CmdletBinding()]
    param(
        # Looks for combined module archives (modules.zip).
        [Parameter(
            Mandatory,
            ParameterSetName="Combined"
        )]
        [Switch]
        $Combined,

        # Looks for individual module packages (*.nupkg).
        [Parameter(
            Mandatory,
            ParameterSetName="NuPkg"
        )]
        [Switch]
        $NuPkg
    )

    $BaseDirectories = @(
        "/opt",
        $Env:LAMBDA_TASK_ROOT
    )

    switch ($PSCmdlet.ParameterSetName) {
        "Combined" {

            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Test-RuntimePackedModule]Searching for combined module archives" }

            $BaseDirectories | Join-Path -ChildPath "modules.zip" | Get-Item -ErrorAction SilentlyContinue | Set-Variable FoundItems

        }
        "NuPkg" {

            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Test-RuntimePackedModule]Searching for individual module packages" }

            $BaseDirectories | Join-Path -ChildPath "module-nupkgs" -AdditionalChildPath "*.nupkg" | Get-Item -ErrorAction SilentlyContinue | Set-Variable FoundItems

        }
    }

    If ($FoundItems) {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Test-RuntimePackedModule]Found $($FoundItems | Measure-Object | % Count) match(es)" }
        return $true
    } else {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Test-RuntimePackedModule]No matches found" }
        return $false
    }
}