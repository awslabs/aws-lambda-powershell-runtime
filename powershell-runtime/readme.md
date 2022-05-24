# PowerShell-runtime
Contains the PowerShell custom runtime based on ````provided.al2```` with a number of deployment methods.

Deploy the example [demo-runtime-layer-function](../examples/demo-runtime-layer-function/) to explore how the runtime and PowerShell function work.

## Deploying the PowerShell custom runtime

There are multiple ways of building this runtime
### [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/)

AWS SAM deploys the custom runtime as a Lambda layer. This template also stores the resulting layer ARN in AWS Systems Manager Parameter Store

### [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/)

### [Serverless Framework](https://serverless.com/framework/)

### [AWS Cloud Development Kit (AWS CDK)](https://aws.amazon.com/cdk/)

## Powershell runtime information

### Variables

The runtime defines the following variables which are made available to the Lambda function.

| Variable   | Description  |
|:---|:---|
|````$LambdaInput````|A PSObject that contains the Lambda function input event data. |
|````$LambdaContext````|An ````Amazon.Lambda.PowerShell.Internal```` object that contains information about the currently running Lambda environment.|

### Lambda context object in PowerShell

When Lambda runs your function, it passes context information by making a ````$LambdaContext```` variable available to the script, module, or handler. This variable provides methods and properties with information about the invocation, function, and execution environment.

**Context methods**

* ````getRemainingTimeInMillis```` – Returns the number of milliseconds left before the invocation times out.

**Context properties**

* ````FunctionName```` – The name of the Lambda function.
* ````FunctionVersion```` – The [version](https://docs.aws.amazon.com/lambda/latest/dg/configuration-versions.html) of the function.
* ````InvokedFunctionArn```` – The Amazon Resource Name (ARN) that's used to invoke the function. * Indicates if the invoker specified a version number or alias.
* ````MemoryLimitInMB```` – The amount of memory that's allocated for the function.
* ````AwsRequestId```` – The identifier of the invocation request.
* ````LogGroupName```` – The log group for the function.
* ````LogStreamName```` – The log stream for the function instance.
* ````RemainingTime```` – The number of milliseconds left before the execution times out.
* ````Identity```` – (synchronous requests) Information about the Amazon Cognito identity that authorized the request.
* ````ClientContext```` – (synchronous requests) Client context that's provided to Lambda by the client application.
* ````Logger```` – The [logger](https://docs.aws.amazon.com/lambda/latest/dg/powershell-logging.html) object for the function.

### Lambda handler options

There are three different Lambda handler formats supported with this runtime.
| handler   | Description  |
|:---|:---|
|````<script.ps1>````| Run entire PowerShell script |
| ````<script.ps1>::<function_name>```` | PowerShell scripts that include a function handler |
| ````Module::<module_name>::<function_name>```` | PowerShell modules that include a function handler |

#### ````<script.ps1>````

Using this handler format, you provide a PowerShell script that is the handler. Lambda runs the entire script on each invoke. ```$LambdaInput``` and ```$LambdaContext``` are made available during the script invocation.

This experience mimics the existing .NET Core-based PowerShell implementation.


#### ````<script.ps1>::<function_name>````

Using this handler format, you provide a PowerShell script that includes a PowerShell function name. The PowerShell function name is the handler.

The PowerShell runtime [dot-sources](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_scripts#script-scope-and-dot-sourcing) the specified ```<script.ps1>```. This allows you to run PowerShell code during the function initialization cold start process. Lambda then invokes the PowerShell handler function ```<function_name>``` with two positional input parameters, ```$LambdaInput``` and ```$LambdaContext```. On subsequent invokes using the same execution environment, Lambda invokes only the handler function ```<function_name>```.

This experience mimics the existing PowerShell .NET Core implementation when a PowerShell function handler is specified.

#### ````Module::<module_name>::<function_name>````

Using this handler format, you provide a PowerShell module. You include a PowerShell function as the handler within the module. Add the PowerShell module using a [Lambda Layer](https://docs.aws.amazon.com/lambda/latest/dg/configuration-layers.html) or by including the module in the Lambda function code package.

The PowerShell runtime imports the specified ```<module_name>```. This allows you to run PowerShell code during the module initialization cold start process. Lambda then invokes the PowerShell handler function ```<function_name>``` with two positional input parameters, ```$LambdaInput``` and ```$LambdaContext```. On subsequent invokes using the same execution environment, Lambda invokes only the handler function ```<function_name>```.

This experience mimics the existing PowerShell .NET Core implementation when a PowerShell module and function handler is specified.

### PowerShell module support

PowerShell modules can be included either via a Lambda Layer, or provided in your function code package. This provide a convenient way to package and share modules that you can use with your Lambda functions. Using layers reduces the size of uploaded deployment archives and makes it faster to deploy your code.

The ```PSModulePath``` environment variable contains a list of folder locations that are searched to find modules. This is configured during the runtime initialization where folders are specified in the following order:

**1. User supplied modules as part of function package**
You can include PowerShell modules inside the published Lambda function package. This folder is first in the list for module imports. ````<$env:LAMBDA_TASK_ROOT>```` is the function root package folder which is extracted to ````/var/task```` within the Lambda execution environment. Use the following folder structure in your package:

```<$env:LAMBDA_TASK_ROOT>/modules/<module_name>/<module_version>/<module_name.psd1>```

**2. User supplied modules as part of Lambda Layers**
You can publish Lambda Layers that include PowerShell modules. This allows you to share modules across functions and accounts. Lambda layers are extracted to ````/opt```` within the Lambda execution environment. This is the preferred solution to use modules with multiple functions. Create the layer using the following folder structure:

```<layer_root>/modules/<module_name>/<module_version>/<module_name.psd1>```

**3. Default/user supplied modules supplied with PowerShell**
Default modules within the PowerShell runtime layer. You can include additional user modules. Create the layer using the following folder structure:

```<layer_root>/powershell/modules/<module_name>/<module_version>/<module_name.psd1>```

### Function logging and metrics
AWS Lambda automatically monitors Lambda functions on your behalf and sends function metrics to [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/). Your Lambda function comes with a CloudWatch Logs log group and a log stream for each instance of your function. The Lambda runtime environment sends details about each invocation to the log stream, and relays logs and other output from your function's code. For more information, see the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/powershell-logging.html).

Output from ````Write-Host````, ````Write-Verbose````, and ````Write-Warning```` is written to the function log stream.

### Function errors
When your code raises an error, Lambda generates a JSON representation of the error. This error document appears in the invocation log and, for synchronous invocations, in the output.

See the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/powershell-exceptions.html) on how to view Lambda function invocation errors for the PowerShell runtime using the Lambda console and the AWS CLI.