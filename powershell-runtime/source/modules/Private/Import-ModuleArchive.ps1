function private:Import-ModuleArchive {
    <#
    .SYNOPSIS
        Unpacks compressed PowerShell modules from .zip archives (modules.zip)
    .DESCRIPTION
        Unpacks compressed PowerShell modules from .zip archives (modules.zip) into a subdirectory of /tmp.

        This folder is later added to $env:PSModulePath, before user code runs, if module archives existed.
    .NOTES
        The contents of this archive should match the format of a folder in $Env:PSModulePath. More specifically:
        * Module names should be top-level directories.
        * One or more versions of the same module may be hosted in their own subdirectories, with respective version numbers.
        * The module root (.psd1/.psm1 files, etc.) is contained within either the module-named or module-versioned directory.

        Module packages are imported from two locations, from lowest to highest precedence:
        * /opt/ (Combined Lambda layer directory)
        * $Env:LAMBDA_TASK_ROOT (Lambda Function Package deployment directory)

        If archives are detected at both locations, they will be extracted over the top of each-other.
    #>
    [CmdletBinding()]
    param(
        [ValidatePattern(".zip$")]
        [ValidateNotNullOrEmpty()]
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [System.IO.FileInfo[]]$ArchivePath
    )

    Begin {
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Import-ModuleArchive]Creating unpack directory for combined module archives' }
        $UnpackDirectory = [System.IO.Directory]::CreateDirectory($Script:ModulePaths.Unpacked.Combined)
    }

    Process {
        $ArchivePath | ForEach-Object {
            if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-Import-ModuleArchive]Unpacking $_ to $UnpackDirectory" }
            Expand-Archive -LiteralPath $_ -DestinationPath $UnpackDirectory -Force
        }
        if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Import-ModuleArchive]Archive unpack complete' }
    }
}