# PowerShell Runtime for AWS Lambda

This runtime makes it easy to run [AWS Lambda](https://aws.amazon.com/lambda/) functions written in [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/overview).

This solutions provides a custom runtime to run your native PowerShell code in Lambda to process events. Your code runs in an Amazon Linux environment that includes AWS credentials from an [AWS Identity and Access Management (IAM)](https://aws.amazon.com/iam/) role that you manage.

## Overview
Previously, running PowerShell on Lambda used the .NET Core runtime [implementation for PowerShell](https://docs.aws.amazon.com/lambda/latest/dg/lambda-powershell.html) which required compiling the PowerShell code into C# binaries to run on .NET. This runtime implements a number of changes from the existing Lambda .NET Core implementation which include:

* **Native PowerShell.** This runtime uses native PowerShell, rather than a compiled .NET hosted PowerShell runtime. The runtime is built using the Lambda [custom runtime](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html) functionality using the ```provided.al2```runtime.
  * The function execution environment matches a standard PowerShell session, which simplifies development and testing.
  * No compilation step required
  * More control over function output, error messages, and logging.
  * Allows additional functionality, such as ```Add-Type``` to provide richer context information. 
* **Code visibility.** The PowerShell code is visible, and you can directly edit the code within the AWS Management Console's built-in [code editor](https://docs.aws.amazon.com/lambda/latest/dg/foundation-console.html#code-editor). PowerShell code can also be embedded within an [AWS CloudFormation](https://aws.amazon.com/cloudformation/) template.
* **Output**. The Lambda function returns everything placed on the pipeline as the function output. The previous .NET implementation only  returned the last item in the pipeline. Unhandled exceptions are caught by the runtime, then they are logged to the log stream and a error result is returned to the caller. 

* **Handler.** The Lambda function *handler* follows a more Python- or Node-like experience which maps more closely to native PowerShell.

## Building, deploying, and invoking PowerShell Lambda functions

There are multiple ways of building this runtime: manually with the [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/), or with infrastructure as code tools such as [AWS CloudFormation](https://aws.amazon.com/cloudformation/), [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/), [Serverless Framework](https://serverless.com/framework/), and [AWS Cloud Development Kit (AWS CDK)](https://aws.amazon.com/cdk/).

Deploy the example [demo-runtime-layer-function](examples/demo-runtime-layer-function/) to explore how the runtime and PowerShell function work.

### [PowerShell-runtime](powershell-runtime/)
Contains the PowerShell custom runtime based on ````provided.al2```` with a number of deployment methods.

### [PowerShell-modules](powershell-modules/)
Contains a number of PowerShell modules you can build and add to your functions.
| Module   | Description  |
|:---|:---|
|[AWSToolsforPowerShell](powershell-modules/AWSToolsforPowerShell/)|AWS Tools for PowerShell |
|[VMwarePowerCLI](powershell-mocules/VMwarePowerCLI/)|VMware PowerCLI|

### [Examples](examples/)
Contains a number of demo applications to show the PowerShell runtime functionality.

| Example   | Description  |
|:---|:---|
|[demo-runtime-layer-function](examples/demo-runtime-layer-function/)|All-in-one Powershell runtime layer, AWS Tools for PowerShell layer, Lambda function with all three handler options |
|[powershell-function](powershell-function/)| Lambda function that uses previously deployed Powershell runtime from [powershell-runtime](powershell-runtime/).|

The demo application [demo-runtime-layer-function](examples/demo-runtime-layer-function/) uses AWS SAM to deploy the following:
1. PowerShell custom runtime based on ````provided.al2```` as a Lambda layer.
2. Lambda layer including select modules from [AWSTools for PowerShell](https://aws.amazon.com/powershell/).
    * ````AWS.Tools.Common````
    * ````AWS.Tools.S3````
3. Lambda function with three different handler options.

## Powershell runtime information
See the [PowerShell-runtime](powershell-runtime/) page for more information on how the runtime works, including:

* Variables
* Lambda handler options
* Lambda context object in PowerShell
* PowerShell module support
* Function logging and metrics
* Function errors

## Acknowledgements

This custom runtime builds on the work of [Norm Johanson](https://twitter.com/socketnorm), [Kevin Marquette](https://twitter.com/KevinMarquette), [Andrew Pearce](https://twitter.com/austoonz), Afroz Mohammed, and Jonathan Nunn.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.