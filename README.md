# PowerShell Runtime for AWS Lambda

This new [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/overview) custom runtime for [AWS Lambda](https://aws.amazon.com/lambda/) makes it even easier to run Lambda functions written in PowerShell to process events.

Your code runs in an Amazon Linux environment that includes AWS credentials from an [AWS Identity and Access Management (IAM)](https://aws.amazon.com/iam/) role that you manage.

## Overview

Lambda has supported running PowerShell since 2018. However, the existing solution uses the .NET Core runtime [implementation for PowerShell](https://docs.aws.amazon.com/lambda/latest/dg/lambda-powershell.html). It uses the additional [AWSLambdaPSCore](https://www.powershellgallery.com/packages/AWSLambdaPSCore/3.0.1.0) modules for deployment and publishing, which require compiling the PowerShell code into C# binaries to run on .NET. This adds additional steps to the development process.

This new runtime uses Lambda's [custom runtime](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html) functionality based on the `provided.al2` runtime.

## PowerShell custom runtime benefits

* **Native PowerShell.** This new runtime uses native PowerShell.
  * The function runtime environment matches a standard PowerShell session, which simplifies the development and testing process.
  * No compilation step required and no hosting on the .NET runtime.
  * Allows additional functionality, such as `Add-Type` to provide richer context information.

* **Code visibility.** You can now also view and edit PowerShell code within the Lambda console's built-in [code editor](https://docs.aws.amazon.com/lambda/latest/dg/foundation-console.html#code-editor). You can embed PowerShell code within an [AWS CloudFormation](https://aws.amazon.com/cloudformation/) template, or other infrastructure as code tools.
* **Output**. This custom runtime returns everything placed on the pipeline as the function output, including the output of `Write-Output`.This gives you more control over the function output, error messages, and logging. With the previous .NET runtime implementation, your function returns only the last output from the PowerShell pipeline. Unhandled exceptions are caught by the runtime, then they are logged to the log stream and a error result is returned to the caller.

## Building, deploying, and invoking PowerShell Lambda functions

You can build the custom runtime using a number of tools, including the the [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/), or with infrastructure as code tools such as [AWS CloudFormation](https://aws.amazon.com/cloudformation/), [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/), [Serverless Framework](https://serverless.com/framework/), and [AWS Cloud Development Kit (AWS CDK)](https://aws.amazon.com/cdk/).

Deploy the example [demo-runtime-layer-function](examples/demo-runtime-layer-function/) to explore how the runtime and PowerShell function work.

### [PowerShell-runtime](powershell-runtime/)

Contains the PowerShell custom runtime based on ````provided.al2```` with a number of deployment methods.

### [PowerShell-modules](powershell-modules/)

Contains a number of PowerShell modules you can build and add to your functions.
| Module   | Description  |
|:---|:---|
|[AWSToolsforPowerShell](powershell-modules/AWSToolsforPowerShell/)|AWS Tools for PowerShell |
|[VMwarePowerCLI](powershell-modules/VMwarePowerCLI/)|VMware PowerCLI|

### [Examples folder](examples/)

Contains a number of demo applications to show the PowerShell runtime functionality.

Initial demo application [demo-runtime-layer-function](examples/demo-runtime-layer-function/) uses AWS SAM to deploy the following:

1. PowerShell custom runtime based on ````provided.al2```` as a Lambda layer.
2. Additional Lambda layer including the [AWSTools for PowerShell](https://aws.amazon.com/powershell/) with the following module.
    * ````AWS.Tools.Common````
3. Both layers store their Amazon Resource Names (ARNs) as parameters in [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) which can be referenced in other templates

4. Lambda function with three different handler options.

| Example   | Description  |
|:---|:---|
|[demo-runtime-layer-function](examples/demo-runtime-layer-function/)|All-in-one Powershell runtime layer, AWS Tools for PowerShell layer, Lambda function with all three handler options |
|[demo-s3-lambda-eventbridge](examples/demo-s3-lambda-eventbridge/)|Demo to show an event-drive application in PowerShell. Copy .CSV file to S3 which triggers PowerShell Lambda function which parses the file. Sends each file line as an event to EventBridge which writes it to CLoudWatch Logs. |

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
