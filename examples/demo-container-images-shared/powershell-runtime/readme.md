# About PowerShell remoting

With the help of [`PSWSMAN`](https://github.com/jborean93/PSWSMan) PowerShell remoting into Active Directory domain-joined Windows hosts is possible, using Kerberos authentication. You will need credentials that have permission to connect to the host and session configuration.

## Lambda considerations

### Network access

Since your lambda needs to have access to your domain, it will need network access to perform the authentication and remoting, so it will usually need to be in a VPC and given a security group that allows it connect to those resources.

### Memory

Recommend at least 512 MB, as it seems to use just over 256 even without doing much of anything.

### Timeout

Consider that the authentication and connection process over WinRM/PSRP is kind of slow. On a cold start, it could take ~30 seconds until your code gets to the point where a command is executing against the remote host. On a warm start, that will be less but not instant. Consider starting with a timeout measured in minutes and pare down after you get a feel for how long things are taking. It will be even slower with less than 512 MB of memory.

## Examples

### Credential

You **must** use UPN format (`user@REALM`), and the realm **is case sensitive**.

For the Actice Directory domain `ad.contoso.com` and the user `account`, you must set the user name to `account@AD.CONTOSO.COM`.

For all of the following examples, we'll assume the use of a `PSCredential` object in the variable `$credential`.

Here's an example of retrieving it from AWS Secrets Manager, but it could come from anywhere. It is not recommended to accept Active Directory credentials as direct function input since it is not encrypted and likely to be logged.

This example assumes that the lambda already has IAM permission to read from the secret, and the ARN is set via environment variable `ConnectorSecretARN`.

It assumes that the secret is formatted as JSON with the following fields:

```json
{
    "user": "account",
    "domain_dns": "ad.contoso.com",
    "password": "correct horse battery staple"
}
```

```powershell
Import-Module -Name AWS.Tools.SecretsManager

$connector_secret = Get-SECSecretValue -SecretId $env:ConnectorSecretARN | ConvertFrom-Json
$user = "{0}@{1}" -f $connector_secret.user, $connector_secret.domain_dns.ToUpper()
$pass = ConvertTo-SecureString -String $connector_secret.password -AsPlainText -Force
$credential = [PSCredential]::new($user, $pass)
```

### Simple use

Using `Invoke-Command` implicitly creates a PSSession to run a script in and removes it (closes it) when the script is done executing.

```powershell
Invoke-Command -ComputerName server01.ad.contoso.com -Credential $credential -ScriptBlock {
    $env:COMPUTERNAME
    & whoami.exe
    Get-ChildItem
}
```

### Passing data to a remote session

Variables in the local scope are not available in the remote scope. There are two ways to pass values into the remote command.

#### The `using:` scope modifier

See also: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scopes#the-using-scope-modifier

The `using:` method is a little more straightforward in many cases where you want to use the same variable names in the local and remote side.

```powershell
$a, $b, $c = @(1, 2, 3)

Invoke-Command -ComputerName server01.ad.contoso.com -Credential $credential -ScriptBlock {
    Write-Host $using:a
    Write-Host $using:b
    Write-Host $using:c
}
```

### Arguments

The arguments method requires declaring a `param()` block in the scriptblock, but that can also be versatile. It allows full parameter declaration like `[Parameter()]` and validation attributes, and it lets you give different names to the variables for use in the remote scriptblock which can help distinguish them.

However there is no way to pass them in by name, so you have to match up your values to your parameters positionally.

```powershell
$a, $b, $c = @(1, 2, 3)

Invoke-Command -ComputerName server01.ad.contoso.com -Credential $credential -ScriptBlock {
    param($x, $y, $z)

    Write-Host $x
    Write-Host $y
    Write-Host $z
} -ArgumentList @($a, $b, $c)

# Passing a single object requires wrapping it in a single element list
Invoke-Command -ComputerName server01.ad.contoso.com -Credential $credential -ScriptBlock {
    param($x)

    Write-Host $x
} -ArgumentList @(,$a)
```

### Reusing a session

Creating the session object separately lets you use it for several commands at different points in the execution. Be sure to close the session when finished otherwise it may stay open on the remote end.

```powershell
$session = New-PSSession -ComputerName server01.ad.contoso.com -Credential $credential

try {
    $remote_output = Invoke-Command -Session $session -ScriptBlock { Invoke-CustomFunction }
    $converted_data = $remote_output | Convert-DataToSomething
    Invoke-Command -Session $session -ScriptBlock { Update-AppData -Data $using:converted_data }
}
finally {
    if ($session) {
        Remove-PSSession -InputObject $session -ErrorAction SilentlyContinue
    }
}
```

### Using JEA and custom session configurations

Using [Just Enough Administration](https://learn.microsoft.com/en-us/powershell/scripting/learn/remoting/jea/overview) you can provide very restricted endpoints and remote sessions, with different local and remote identities. The documentation above has the details on how to set this up on the remote (Windows) side. For the purposes of a connecting lambda, all you need to know is the name of the Session Configuration to connect to.

```powershell
Invoke-Command `
    -ComputerName server01.ad.contoso.com `
    -Credential $credential `
    -SessionConfiguration My.Custom.Configuration `
    -ScriptBlock { Get-Command -Module Microsoft.PowerShell.Archive }
```

```powershell
$session = New-PSSession -ComputerName server01.ad.contoso.com -Credential $credential -SessionConfiguration My.Custom.Configuration

try {
    Invoke-Command -Session $session -ScriptBlock { Invoke-CustomFunction }
}
finally {
    if ($session) {
        Remove-PSSession -InputObject $session -ErrorAction SilentlyContinue
    }
}
```
