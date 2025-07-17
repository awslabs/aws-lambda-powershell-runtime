# PowerShell Runtime for AWS Lambda

This [PowerShell](https://docs.microsoft.com/en-us/powershell/scripting/overview) custom runtime for [AWS Lambda](https://aws.amazon.com/lambda/) enables running Lambda functions written in PowerShell to process events.

Your code runs in an Amazon Linux environment that includes AWS credentials from an [AWS Identity and Access Management (IAM)](https://aws.amazon.com/iam/) role that you manage.

## Overview

Lambda has supported running PowerShell since 2018. However, the existing solution uses the .NET Core runtime [implementation for PowerShell](https://docs.aws.amazon.com/lambda/latest/dg/lambda-powershell.html). It uses the additional [AWSLambdaPSCore](https://www.powershellgallery.com/packages/AWSLambdaPSCore/3.0.1.0) modules for deployment and publishing, which require compiling the PowerShell code into C# binaries to run on .NET. This adds additional steps to the development process.

This runtime uses Lambda's [custom runtime](https://docs.aws.amazon.com/lambda/latest/dg/runtimes-custom.html) functionality based on the `provided.al2023` runtime.

## PowerShell custom runtime benefits

*   **Native PowerShell.** This runtime uses native PowerShell.
    *   The function runtime environment matches a standard PowerShell session, which simplifies the development and testing process.
    *   No compilation step required and no hosting on the .NET runtime.
    *   Allows additional functionality, such as `Add-Type` to provide richer context information.

*   **Code visibility.** You can view and edit PowerShell code within the Lambda console's built-in [code editor](https://docs.aws.amazon.com/lambda/latest/dg/foundation-console.html#code-editor) when using .zip archive functions (not container images). You can embed PowerShell code within an [AWS CloudFormation](https://aws.amazon.com/cloudformation/) template, or other infrastructure as code tools.
*   **Output**. This custom runtime returns everything placed on the pipeline as the function output, including the output of `Write-Output`.This gives you more control over the function output, error messages, and logging. With the previous .NET runtime implementation, your function returns only the last output from the PowerShell pipeline. Unhandled exceptions are caught by the runtime, then they are logged to the log stream and a error result is returned to the caller.

## Development Requirements

*   **PowerShell 7.0 or later** for development and testing
    *   Download from: <https://github.com/PowerShell/PowerShell/releases>
    *   Required for development tools and test suite

### Testing

The runtime includes unit tests and integration tests:

* **Unit Tests**: Automated tests covering runtime functions and build processes
* **Integration Tests**: Manual tests with real AWS Lambda functions for end-to-end validation

See [powershell-runtime/tests/README.md](powershell-runtime/tests/README.md) for testing documentation and commands.

## Building and Deploying

You can build the custom runtime using AWS SAM or other infrastructure-as-code tools. Deploy the example [demo-runtime-layer-function](examples/demo-runtime-layer-function/) to explore how the runtime works.

See [powershell-runtime/README.md](powershell-runtime/README.md) for detailed deployment instructions.

## Project Structure

*   **[powershell-runtime/](powershell-runtime/)** - Custom runtime implementation and deployment methods
*   **[powershell-modules/](powershell-modules/)** - Pre-built PowerShell modules (AWS Tools, VMware PowerCLI)
*   **[examples/](examples/)** - Demo applications showing runtime functionality

## Examples

| Example   | Description  |
|:---|:---|
|[demo-runtime-layer-function](examples/demo-runtime-layer-function/)|Complete runtime layer with AWS Tools and multiple handler options |
|[demo-s3-lambda-eventbridge](examples/demo-s3-lambda-eventbridge/)|Event-driven application processing S3 files with EventBridge |
|[demo-container-image-all-aws-sdk](examples/demo-container-image-all-aws-sdk/)|Container image deployment with full AWS SDK |
|[demo-container-images-shared](examples/demo-container-image-all-aws-sdk/)|Shared container layers for multiple functions |

## Runtime Information

See the [PowerShell-runtime](powershell-runtime/) documentation for detailed information on runtime variables, handler options, context objects, module support, logging, and error handling.

## Acknowledgements

This custom runtime builds on the work of [Norm Johanson](https://twitter.com/socketnorm), [Kevin Marquette](https://twitter.com/KevinMarquette), [Andrew Pearce](https://twitter.com/austoonz), Afroz Mohammed, and Jonathan Nunn.

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This project is licensed under the Apache-2.0 License.
