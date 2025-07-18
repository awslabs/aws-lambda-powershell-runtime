# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Test HTTP server that mimics the AWS Lambda Runtime API for testing purposes.

.DESCRIPTION
    This module provides a minimal HTTP server for testing PowerShell Lambda Runtime
    with automatic request processing and logging capabilities.
#>

class TestLambdaRuntimeServer {
    [System.Net.HttpListener]$Listener
    [hashtable]$Responses
    [System.Collections.ArrayList]$RequestLog
    [bool]$IsRunning
    [string]$BaseUrl
    [int]$Port
    [int]$RequestCount
    [System.Management.Automation.PowerShell]$PowerShell
    [System.Management.Automation.Runspaces.Runspace]$Runspace

    TestLambdaRuntimeServer([int]$Port = 9001) {
        $this.Port = $Port
        $this.BaseUrl = "http://localhost:$Port/"
        $this.Listener = [System.Net.HttpListener]::new()
        $this.Listener.Prefixes.Add($this.BaseUrl)
        $this.Responses = @{}
        $this.RequestLog = New-Object System.Collections.ArrayList
        $this.IsRunning = $false
        $this.RequestCount = 0
        $this.SetupDefaultResponses()
    }

    [void] SetupDefaultResponses() {
        # Default Lambda event response
        $this.Responses['/2018-06-01/runtime/invocation/next'] = @{
            StatusCode = 200
            Headers    = @{
                'Lambda-Runtime-Aws-Request-Id' = 'test-request-id-12345'
                'Lambda-Runtime-Deadline-Ms'    = ([DateTimeOffset]::UtcNow.AddMinutes(5).ToUnixTimeMilliseconds()).ToString()
                'Content-Type'                  = 'application/json'
            }
            Body       = '{"test": "event", "key": "value"}'
        }

        # Default response endpoint
        $this.Responses['/2018-06-01/runtime/invocation/*/response'] = @{
            StatusCode = 202
            Body       = ''
        }

        # Default error endpoint
        $this.Responses['/2018-06-01/runtime/invocation/*/error'] = @{
            StatusCode = 202
            Body       = ''
        }
    }

    [void] Start() {
        if ($this.IsRunning) {
            return
        }

        $this.Listener.Start()
        $this.IsRunning = $true
        Write-Verbose "Test server started on $($this.BaseUrl)"
        Write-Verbose "Server will automatically process incoming requests"

        # Create a new runspace for background processing
        $this.Runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $this.Runspace.Open()

        $this.PowerShell = [System.Management.Automation.PowerShell]::Create()
        $this.PowerShell.Runspace = $this.Runspace

        # Start processing requests asynchronously
        $this.PowerShell.AddScript({
            param($listener, $responses, $serverInstance, $requestLog)

            while ($serverInstance.IsRunning -and $listener.IsListening) {
                try {
                    # Use BeginGetContext for non-blocking operation
                    $asyncResult = $listener.BeginGetContext($null, $null)

                    # Wait for request with timeout
                    if ($asyncResult.AsyncWaitHandle.WaitOne(1000)) {
                        $context = $listener.EndGetContext($asyncResult)

                        $request = $context.Request
                        $response = $context.Response

                        $method = $request.HttpMethod
                        $path = $request.Url.AbsolutePath
                        $body = ''

                        if ($request.HasEntityBody) {
                            $reader = New-Object System.IO.StreamReader($request.InputStream)
                            $body = $reader.ReadToEnd()
                            $reader.Close()
                        }

                        # Log the request
                        $requestInfo = [PSObject]@{
                            Method    = $method
                            Path      = $path
                            Body      = $body
                            Timestamp = Get-Date
                        }
                        $requestLog.Add($requestInfo) | Out-Null

                        # Find matching response
                        $responseConfig = $null
                        if ($responses.ContainsKey($path)) {
                            $responseConfig = $responses[$path]
                        } else {
                            foreach ($pattern in $responses.Keys) {
                                if ($pattern.Contains('*')) {
                                    $regex = $pattern -replace '\*', '[^/]+'
                                    if ($path -match $regex) {
                                        $responseConfig = $responses[$pattern]
                                        break
                                    }
                                }
                            }
                        }

                        if (-not $responseConfig) {
                            $responseConfig = @{
                                StatusCode = 404
                                Body = "Not Found: $path"
                            }
                        }

                        # Handle string responses (backward compatibility)
                        if ($responseConfig -is [string]) {
                            $responseConfig = @{
                                StatusCode = 200
                                Body = $responseConfig
                            }
                        }

                        $response.StatusCode = $responseConfig.StatusCode

                        if ($responseConfig.Headers) {
                            foreach ($header in $responseConfig.Headers.GetEnumerator()) {
                                try {
                                    $response.Headers.Add($header.Key, $header.Value)
                                } catch {
                                    # Skip conflicting headers
                                }
                            }
                        }

                        if ($responseConfig.Body) {
                            $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseConfig.Body)
                            $response.ContentLength64 = $buffer.Length
                            $response.OutputStream.Write($buffer, 0, $buffer.Length)
                        } else {
                            $response.ContentLength64 = 0
                        }

                        if (-not $responseConfig.Headers -or -not $responseConfig.Headers.ContainsKey('Content-Type')) {
                            $response.ContentType = "application/json"
                        }

                        $response.Close()
                        Write-Verbose "[$([DateTime]::Now.ToString('HH:mm:ss'))] $method $path -> $($responseConfig.StatusCode)"
                    }
                }
                catch {
                    Write-Verbose "Error: $($_.Exception.Message)"
                    if ($response) {
                        try {
                            $response.StatusCode = 500
                            $response.Close()
                        } catch { }
                    }
                }
            }
        }).AddArgument($this.Listener).AddArgument($this.Responses).AddArgument($this).AddArgument($this.RequestLog)

        # Start the background processing
        $this.PowerShell.BeginInvoke()
    }

    [hashtable] FindResponseConfig([string]$Path) {
        # Exact match first
        if ($this.Responses.ContainsKey($Path)) {
            return $this.Responses[$Path]
        }

        # Wildcard match
        foreach ($pattern in $this.Responses.Keys) {
            if ($pattern.Contains('*')) {
                $regex = $pattern -replace '\*', '[^/]+'
                if ($Path -match $regex) {
                    return $this.Responses[$pattern]
                }
            }
        }

        return $null
    }

    [void] SetResponse([string]$Path, [string]$Response) {
        $this.Responses[$Path] = $Response
    }

    [void] SetResponse([string]$Path, [hashtable]$ResponseConfig) {
        $this.Responses[$Path] = $ResponseConfig
    }

    [array] GetRequestLog() {
        return $this.RequestLog
    }

    [void] ClearRequestLog() {
        $this.RequestLog.Clear()
    }

    [int] GetRequestCount() {
        return $this.RequestLog.Count
    }

    [int] GetRequestCount([string]$Path = $null) {
        if ($Path) {
            $matchingRequests = @($this.RequestLog | Where-Object { $_.Path -eq $Path })
            return $matchingRequests.Count
        }
        return $this.RequestLog.Count
    }

    [array] GetRequestsForPath([string]$Path) {
        # Using comma to ensure the output is an array
        return ,@($this.RequestLog | Where-Object { $_.Path -eq $Path })
    }

    [void] Stop() {
        $this.IsRunning = $false

        if ($this.Listener.IsListening) {
            $this.Listener.Stop()
        }

        if ($this.PowerShell) {
            $this.PowerShell.Stop()
            $this.PowerShell.Dispose()
        }

        if ($this.Runspace) {
            $this.Runspace.Close()
            $this.Runspace.Dispose()
        }

        $this.Listener.Close()
    }
}

function Start-TestLambdaRuntimeServer {
    param(
        [int]$Port = 9001,
        [switch]$MockOnly
    )

    $server = [TestLambdaRuntimeServer]::new($Port)
    if (-not $MockOnly) {
        $server.Start()
        # Give the server a moment to start
        Start-Sleep -Milliseconds 200
    }
    return $server
}

function Stop-TestLambdaRuntimeServer {
    param([TestLambdaRuntimeServer]$Server)
    $Server.Stop()
}

function Set-TestServerLambdaEvent {
    param(
        [TestLambdaRuntimeServer]$Server,
        [hashtable]$LambdaEvent,
        [string]$RequestId = (New-Guid).ToString()
    )

    $headers = @{
        'Lambda-Runtime-Aws-Request-Id' = $RequestId
        'Lambda-Runtime-Deadline-Ms'    = ([DateTimeOffset]::UtcNow.AddMinutes(5).ToUnixTimeMilliseconds()).ToString()
        'Content-Type'                  = 'application/json'
    }

    $Server.SetResponse('/2018-06-01/runtime/invocation/next', @{
            StatusCode = 200
            Headers    = $headers
            Body       = ($LambdaEvent | ConvertTo-Json -Compress -Depth 10)
        })
}

function Reset-TestServer {
    param([TestLambdaRuntimeServer]$Server)
    $Server.ClearRequestLog()
    $Server.Responses.Clear()
    $Server.SetupDefaultResponses()
}

function Assert-TestServerRequest {
    param(
        [TestLambdaRuntimeServer]$Server,
        [string]$Path,
        [string]$Method = 'GET'
    )

    $requests = $Server.GetRequestsForPath($Path)
    $matchingRequest = $requests | Where-Object { $_.Method -eq $Method }

    if (-not $matchingRequest) {
        throw "Expected $Method request to $Path was not found. Found requests: $($requests | ForEach-Object { "$($_.Method) $($_.Path)" } | Join-String ', ')"
    }
}

function Get-TestServerRequestBody {
    param(
        [TestLambdaRuntimeServer]$Server,
        [string]$Path,
        [string]$Method = 'POST'
    )

    $requests = $Server.GetRequestsForPath($Path)
    $matchingRequest = $requests | Where-Object { $_.Method -eq $Method } | Select-Object -First 1

    if ($matchingRequest) {
        return $matchingRequest.Body
    }

    return $null
}

function Set-TestServerResponse {
    param(
        [TestLambdaRuntimeServer]$Server,
        [string]$Path,
        [int]$StatusCode = 200,
        [string]$Body = '',
        [hashtable]$Headers = @{}
    )

    $responseConfig = @{
        StatusCode = $StatusCode
        Body = $Body
    }

    if ($Headers.Count -gt 0) {
        $responseConfig.Headers = $Headers
    }

    $Server.SetResponse($Path, $responseConfig)
}