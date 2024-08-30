# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function SendRuntimeApiRequest {
    [CmdletBinding()]
    param (
        [Parameter(Position=0)]
        [System.Net.Http.HttpClient]$private:HttpClient,

        [Parameter(Position=1)]
        [string]$private:Uri,

        [Parameter(Position=2)]
        $private:Body,

        [Parameter(Position=3)]
        $private:Headers
    )

    $private:request = [System.Net.Http.HttpRequestMessage]::new()
    $private:request.Headers.Add('User-Agent', "aws-lambda-powershell/$env:POWERSHELL_VERSION")
    if ($private:Headers) {
        $private:Headers | ForEach-Object {
            $private:request.Headers.Add($_.Key, $_.Value)
        }
    }
    $private:request.Method = 'POST'
    $private:request.RequestUri = $private:Uri
    $private:request.Content = [System.Net.Http.StringContent]::new($private:Body)

    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host '[RUNTIME-SendRuntimeApiRequest]Sending POST request to Runtime API' }
    $private:runtimeResponse = $private:HttpClient.SendAsync($private:request).GetAwaiter().GetResult()
    $private:runtimeResponseContent =  $private:runtimeResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    if ($env:POWERSHELL_RUNTIME_VERBOSE -eq 'TRUE') { Write-Host "[RUNTIME-SendRuntimeApiRequest]Runtime API Response: $private:runtimeResponseContent" }

    if ($private:runtimeResponse) { $private:runtimeResponse.Dispose() }
}