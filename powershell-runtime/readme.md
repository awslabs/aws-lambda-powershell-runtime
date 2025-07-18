# PowerShell-runtime

Contains the PowerShell custom runtime based on `provided.al2023` with deployment methods.

Deploy the example [demo-runtime-layer-function](../examples/demo-runtime-layer-function/) to explore how the runtime and PowerShell function work.

## Deploying the PowerShell custom runtime

The recommended deployment method is AWS SAM, though other infrastructure-as-code tools are also supported.

## AWS SAM

AWS SAM deploys the custom runtime as a Lambda layer. You can amend the template to also store the resulting layer name in AWS Systems Manager Parameter Store for easier reference in other templates

To build the custom runtime layer, AWS SAM uses a Makefile. This downloads the specified version of [PowerShell](https://github.com/PowerShell/PowerShell/releases/).

Windows does not natively support Makefiles. When using Windows, you can use either [Windows Subsystem for Linux (WSL)](https://docs.microsoft.com/en-us/windows/wsl/about), [Docker Desktop](https://docs.docker.com/get-docker/) or native PowerShell.

Clone the repository and change into the runtime directory

```shell
git clone https://github.com/awslabs/aws-lambda-powershell-runtime
cd aws-lambda-powershell-runtime
cd powershell-runtime
```

### Building the Runtime

Recommended: Using Docker (cross-platform)

```shell
sam build --parallel --use-container
```

Alternative: Linux/WSL

```shell
sam build --parallel
```

Alternative: PowerShell

```shell
.\build-PwshRuntimeLayer.ps1
```

### Deploying to the AWS Cloud

Use AWS SAM to deploy the runtime and optional SSM parameter to your AWS account. Run a guided deployment to set the default parameters for the first deploy.

```shell
sam deploy -g
```

For subsequent deployments you can use `sam deploy`.

Enter a **Stack Name** such as `powershell-runtime` and accept the remaining initial defaults.

## Development and Testing

See [tests/README.md](tests/README.md) for comprehensive testing documentation and commands.

## Powershell runtime information

### Variables

The runtime defines the following variables which are made available to the Lambda function.

| Variable         | Description                                                                                                             |
| :--------------- | :---------------------------------------------------------------------------------------------------------------------- |
| `$LambdaInput`   | A PSObject that contains the Lambda function input event data.                                                          |
| `$LambdaContext` | An `Amazon.Lambda.PowerShell.Internal` object that contains information about the currently running Lambda environment. |

### Lambda context object in PowerShell

When Lambda runs your function, it passes context information by making a `$LambdaContext` variable available to the script, module, or handler. This variable provides methods and properties with information about the invocation, function, and execution environment.

#### Context methods

*   `getRemainingTimeInMillis` – Returns the number of milliseconds left before the invocation times out.

#### Context properties

*   `FunctionName` – The name of the Lambda function.
*   `FunctionVersion` – The [version](https://docs.aws.amazon.com/lambda/latest/dg/configuration-versions.html) of the function.
*   `InvokedFunctionArn` – The Amazon Resource Name (ARN) that's used to invoke the function. Indicates if the invoker specified a version number or alias.
*   `MemoryLimitInMB` – The amount of memory that's allocated for the function.
*   `AwsRequestId` – The identifier of the invocation request.
*   `LogGroupName` – The log group for the function.
*   `LogStreamName` – The log stream for the function instance.
*   `RemainingTime` – The number of milliseconds left before the execution times out.
*   `Identity` – (synchronous requests) Information about the Amazon Cognito identity that authorized the request.
*   `ClientContext` – (synchronous requests) Client context that's provided to Lambda by the client application.
*   `Logger` – The [logger](https://docs.aws.amazon.com/lambda/latest/dg/powershell-logging.html) object for the function.

### Lambda handler options

There are three different Lambda handler formats supported with this runtime.

| handler | Description |
|:---|:---|
|`<script.ps1>`| Run entire PowerShell script |
| `<script.ps1>::<function_name>` | PowerShell scripts that include a function handler |
| `Module::<module_name>::<function_name>` | PowerShell modules that include a function handler |

#### `<script.ps1>`

You provide a PowerShell script that is the handler. Lambda runs the entire script on each invoke. `$LambdaInput` and `$LambdaContext` are made available during the script invocation.

#### `<script.ps1>::<function_name>`

You provide a PowerShell script that includes a PowerShell function name. The PowerShell function name is the handler.

The PowerShell runtime [dot-sources](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts#script-scope-and-dot-sourcing) the specified `<script.ps1>`. This allows you to run PowerShell code during the function initialization cold start process. Lambda then invokes the PowerShell handler function `<function_name>` with two positional input parameters, `$LambdaInput` and `$LambdaContext`. On subsequent invokes using the same runtime environment, Lambda invokes only the handler function `<function_name>`.

#### `Module::<module_name>::<function_name>`

You provide a PowerShell module. You include a PowerShell function as the handler within the module. Add the PowerShell module using a [Lambda Layer](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html) or by including the module in the Lambda function code package.

The PowerShell runtime imports the specified `<module_name>`. This allows you to run PowerShell code during the module initialization cold start process. Lambda then invokes the PowerShell handler function `<function_name>` with two positional input parameters, `$LambdaInput` and `$LambdaContext`. On subsequent invokes using the same runtime environment, Lambda invokes only the handler function `<function_name>`.

### PowerShell module support

You can include additional PowerShell modules either via a Lambda Layer, or within your function code package, or container image. Using Lambda layers provides a convenient way to package and share modules that you can use with your Lambda functions. Layers reduce the size of uploaded deployment archives and make it faster to deploy your code.

The `PSModulePath` environment variable contains a list of folder locations that are searched to find user-supplied modules. This is configured during the runtime initialization. Folders are specified in the following order:

| Location | Path | Use Case |
|:---|:---|:---|
| Function package | `/modules/<module>/<version>/` | Single function modules |
| Lambda layers | `/opt/modules/<module>/<version>/` | **Recommended** - Shared across functions |
| Runtime layer | `/opt/powershell/modules/<module>/<version>/` | Built-in modules |

### Function logging and metrics

AWS Lambda automatically monitors Lambda functions on your behalf and sends function metrics to [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/). Your Lambda function comes with a CloudWatch Logs log group and a log stream for each instance of your function. The Lambda runtime environment sends details about each invocation to the log stream, and relays logs and other output from your function’s code. For more information, see the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/powershell-logging.html).

Output from `Write-Host`, `Write-Verbose`, `Write-Warning`, and `Write-Error` is written to the function log stream. The output from `Write-Output` is added to the pipeline, which you can use with your function response.

### Error handling

The runtime can terminate your function because it ran out of time, detected a syntax error, or failed to marshal the response object into JSON.

Your function code can throw an exception or return an error object. Lambda writes the error to CloudWatch Logs and, for synchronous invocations, also returns the error in the function response output.

See the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/powershell-exceptions.html) on how to view Lambda function invocation errors for the PowerShell runtime using the Lambda console and the AWS CLI.

### Provided Runtime options

The runtime supports both the `provided.al2` and `provided.al2023` Lambda runtimes.

#### provided.al2023

To work as expected in the `provided.al2023` runtime, the environment variable `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT` must be set to `1`. This is to prevent the need for installing the `libicu` package. If this is an issue for your environment, either continue using `provided.al2`, or open an issue in this GitHub repository.

If this environment variable is not configured, you'll see an ICU package error in your function logs. See the [Microsoft documentation](https://aka.ms/dotnet-missing-libicu) for more information.
