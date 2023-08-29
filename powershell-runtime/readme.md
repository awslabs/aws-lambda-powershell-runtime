# PowerShell-runtime

Contains the PowerShell custom runtime based on ````provided.al2```` with a number of deployment methods.

Deploy the example [demo-runtime-layer-function](../examples/demo-runtime-layer-function/) to explore how the runtime and PowerShell function work.

## Deploying the PowerShell custom runtime

You can build the custom runtime using a number of tools, including the the [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/), or with infrastructure as code tools such as [AWS CloudFormation](https://aws.amazon.com/cloudformation/), [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/), [Serverless Framework](https://serverless.com/framework/), and [AWS Cloud Development Kit (AWS CDK)](https://aws.amazon.com/cdk/).

## AWS SAM

AWS SAM deploys the custom runtime as a Lambda layer. You can amend the template to also stores the resulting layer name in AWS Systems Manager Parameter Store for easier reference in other templates

To build the custom runtime layer, AWS SAM uses a Makefile. This downloads the specified version of [PowerShell](https://github.com/PowerShell/PowerShell/releases/).

Windows does not natively support Makefiles. When using Windows, you can use either [Windows Subsystem for Linux (WSL)](https://docs.microsoft.com/en-us/windows/wsl/about), [Docker Desktop](https://docs.docker.com/get-docker/) or native PowerShell.

Clone the repository and change into the runtime directory

```shell
git clone https://github.com/awslabs/aws-lambda-powershell-runtime
cd aws-lambda-powershell-runtime
cd powershell-runtime
```

Use one of the *"Build"* options, A,B,C, depending on your operating system and tools.

### A) Build using Linux or WSL

Build the custom runtime using native Linux or WSL.

*Note:* The `make` package is required for `sam build` to work. When building in Linux environments, including WSL, you may need to install `make` before this command will work.

```shell
sam build --parallel
```

### B) Build using Docker

You can build the custom runtime using Docker. This uses a Linux-based Lambda-like Docker container to build the packages. Use this option for Windows without WSL or as an isolated Mac/Linux build environment.

```shell
sam build --parallel --use-container
```

### C) Build using PowerShell for Windows

You can use native PowerShell for Windows to download and extract the custom runtime files. This performs the same file copy functionality as the Makefile. It adds the files to the source folders rather than a build location for subsequent deployment with AWS SAM. Use this option for Windows without WSL or Docker.

```shell
.\build-PwshRuntimeLayer
```

### Deploying to the AWS Cloud

Use AWS SAM to deploy the runtime and optional SSM parameter to your AWS account. Run a guided deployment to set the default parameters for the first deploy.

```shell
sam deploy -g
```

For subsequent deployments you can use `sam deploy`.

Enter a **Stack Name** such as `powershell-runtime` and accept the remaining initial defaults.

### [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/)

coming soon...

## Powershell runtime information

### Variables

The runtime defines the following variables which are made available to the Lambda function.

| Variable   | Description  |
|:---|:---|
|`$LambdaInput`|A PSObject that contains the Lambda function input event data. |
|`$LambdaContext`|An `Amazon.Lambda.PowerShell.Internal` object that contains information about the currently running Lambda environment.|

### Lambda context object in PowerShell

When Lambda runs your function, it passes context information by making a `$LambdaContext` variable available to the script, module, or handler. This variable provides methods and properties with information about the invocation, function, and execution environment.

#### Context methods

* `getRemainingTimeInMillis` – Returns the number of milliseconds left before the invocation times out.

#### Context properties

* `FunctionName` – The name of the Lambda function.
* `FunctionVersion` – The [version](https://docs.aws.amazon.com/lambda/latest/dg/configuration-versions.html) of the function.
* `InvokedFunctionArn` – The Amazon Resource Name (ARN) that's used to invoke the function. * Indicates if the invoker specified a version number or alias.
* `MemoryLimitInMB` – The amount of memory that's allocated for the function.
* `AwsRequestId` – The identifier of the invocation request.
* `LogGroupName` – The log group for the function.
* `LogStreamName` – The log stream for the function instance.
* `RemainingTime` – The number of milliseconds left before the execution times out.
* `Identity` – (synchronous requests) Information about the Amazon Cognito identity that authorized the request.
* `ClientContext` – (synchronous requests) Client context that's provided to Lambda by the client application.
* `Logger` – The [logger](https://docs.aws.amazon.com/lambda/latest/dg/powershell-logging.html) object for the function.

### Lambda handler options

There are three different Lambda handler formats supported with this runtime.
| handler   | Description  |
|:---|:---|
|`<script.ps1>`| Run entire PowerShell script |
| `<script.ps1>::<function_name>` | PowerShell scripts that include a function handler |
| `Module::<module_name>::<function_name>` | PowerShell modules that include a function handler |

#### `<script.ps1>`

You provide a PowerShell script that is the handler. Lambda runs the entire script on each invoke. `$LambdaInput` and `$LambdaContext` are made available during the script invocation.

This experience mimics the existing .NET Core-based PowerShell implementation.

#### `<script.ps1>::<function_name>`

You provide a PowerShell script that includes a PowerShell function name.The PowerShell function name is the handler.

The PowerShell runtime [dot-sources](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts#script-scope-and-dot-sourcing) the specified `<script.ps1>`. This allows you to run PowerShell code during the function initialization cold start process. Lambda then invokes the PowerShell handler function `<function_name>` with two positional input parameters, `$LambdaInput` and `$LambdaContext`. On subsequent invokes using the same runtime environment, Lambda invokes only the handler function `<function_name>`.

This experience mimics the existing PowerShell .NET Core implementation when a PowerShell function handler is specified.

#### `Module::<module_name>::<function_name>`

You provide a PowerShell module. You include a PowerShell function as the handler within the module. Add the PowerShell module using a [Lambda Layer](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html) or by including the module in the Lambda function code package.

The PowerShell runtime imports the specified `<module_name>`. This allows you to run PowerShell code during the module initialization cold start process. Lambda then invokes the PowerShell handler function `function_name>` with two positional input parameters, `$LambdaInput` and `$LambdaContext`. On subsequent invokes using the same runtime environment, Lambda invokes only the handler function `<function_name>`.

This experience mimics the existing PowerShell .NET Core implementation when a PowerShell module and function handler is specified.

### PowerShell module support

You can include additional PowerShell modules either via a Lambda Layer, or within your function code package, or container image. Using Lambda layers provides a convenient way to package and share modules that you can use with your Lambda functions. Layers reduce the size of uploaded deployment archives and make it faster to deploy your code.

The `PSModulePath` environment variable contains a list of folder locations that are searched to find user-supplied modules. This is configured during the runtime initialization. Folders are specified in the following order:

**1. Modules as part of function package in a `/modules` subfolder.**

You can include PowerShell modules inside the published Lambda function package. This folder is first in the list for module imports. `<$env:LAMBDA_TASK_ROOT>` is the function root package folder which is extracted to `/var/task` within the Lambda runtime environment. Use the following folder structure in your package:

`<$env:LAMBDA_TASK_ROOT>/modules/<module_name>/<module_version>/<module_name.psd1>`

**2. Modules as part of Lambda layers in a `/modules` subfolder.**

You can publish Lambda Layers that include PowerShell modules. This allows you to share modules across functions and accounts. Lambda layers are extracted to `/opt` within the Lambda runtime environment. This is the preferred solution to use modules with multiple functions. Use the following folder structure in your package:

`<layer_root>/modules/<module_name>/<module_version>/<module_name.psd1>`

**3. Modules as part of the PowerShell custom runtime layer in a `/modules` subfolder.**

Default modules within the PowerShell runtime layer. You can include additional user modules. Create the layer using the following folder structure:

`<layer_root>/powershell/modules/<module_name>/<module_version>/<module_name.psd1>`

### Function logging and metrics

AWS Lambda automatically monitors Lambda functions on your behalf and sends function metrics to [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/). Your Lambda function comes with a CloudWatch Logs log group and a log stream for each instance of your function. The Lambda runtime environment sends details about each invocation to the log stream, and relays logs and other output from your function’s code. For more information, see the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/powershell-logging.html).

Output from `Write-Host`, `Write-Verbose`, `Write-Warning`, and `Write-Error` is written to the function log stream. The output from `Write-Output` is added to the pipeline, which you can use with your function response.

### Error handling

The runtime can terminate your function because it ran out of time, detected a syntax error, or failed to marshal the response object into JSON.

Your function code can throw an exception or return an error object. Lambda writes the error to CloudWatch Logs and, for synchronous invocations, also returns the error in the function response output.

See the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/powershell-exceptions.html) on how to view Lambda function invocation errors for the PowerShell runtime using the Lambda console and the AWS CLI.
