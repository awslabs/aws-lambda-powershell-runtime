# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function private:Send-FunctionHandlerError {
    <#
        .SYNOPSIS
            POST function invocation error back to Runtime API.

        .DESCRIPTION
            POST function invocation error back to Runtime API.

        .Notes

    #>
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        [System.Net.Http.HttpClient]$private:HttpClient,

        [Parameter(Mandatory, Position=1)]
        $private:Exception
    )

    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-Send-FunctionHandlerError]Start: Send-FunctionHandlerError' }
    Write-Host $private:Exception

    $private:uri = "http://$env:AWS_LAMBDA_RUNTIME_API/2018-06-01/runtime/invocation/$env:AWS_LAMBDA_RUNTIME_AWS_REQUEST_ID/error"
    $private:body = ConvertTo-Json -Compress -InputObject @{
        errorMessage = $private:Exception.Exception.Message
        errorType    = $private:Exception.CategoryInfo.Reason
    }
    $private:headers = @(@{
        Key = 'Lambda-Runtime-Function-Error-Type'
        Value = '{0}.{1}' -f $private:Exception.CategoryInfo.Category, $private:Exception.CategoryInfo.Reason
    })
    SendRuntimeApiRequest $private:HttpClient $private:uri $private:body $private:headers
}
