# Demo-reusable-pwsh-runtime

A set of reusable Lambda layers [reusable-pwsh-runtime](examples/reusable-pwsh-runtime/) uses AWS SAM to deploy the following:
1. PowerShell custom runtimes for arm64 and x64 processor architectures based on ````provided.al2```` as a Lambda layer.
2. Additional Lambda layer including the [AWSTools for PowerShell](https://aws.amazon.com/powershell/) with the following module.
    * ````AWS.Tools.Common````
3. Both layers store their Amazon Resource Names (ARNs) as parameters in [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) which can be referenced in other templates

To build the custom runtime and the AWS Tools for PowerShell layer for this example, AWS SAM uses a Makefile. This downloads the specified version of [PowerShell](https://github.com/PowerShell/PowerShell/releases/) and select modules from the [AWSTools](https://sdk-for-net.amazonwebservices.com/ps/v4/latest/AWS.Tools.zip)

Windows does not natively support Makefiles. When using Windows, you can use either [Windows Subsystem for Linux (WSL)](https://docs.microsoft.com/en-us/windows/wsl/about), [Docker Desktop](https://docs.docker.com/get-docker/) or native PowerShell.

### Pre-requisites: 
* [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/)
* If building on Windows:
   * [Windows Subsystem for Linux (WSL)](https://docs.microsoft.com/en-us/windows/wsl/about) *or*
   * [Docker Desktop](https://docs.docker.com/get-docker/) *or*
   * [PowerShell for Windows](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)

Clone the repository and change into the example directory
```
git clone https://github.com/awslabs/aws-lambda-powershell-runtime
cd aws-lambda-powershell-runtime/examples/reusable-pwsh-runtime
```
Use one of the *"Build"* options, A,B,C, depending on your operating system and tools.

### A) Build using Linux or WSL
Build the custom runtime, Lambda layer, and function packages using native Linux or WSL.
```
sam build --parallel
```
![sam build --parallel](../../img/sam-build-parallel.png)

### B) Build using Docker
You can build the custom runtime, Lambda layer, and function packages using Docker. This uses a Linux-based Lambda-like Docker container to build the packages. Use this option for Windows without WSL or as an isolated Mac/Linux build environment.

```
sam build --parallel --use-container
```
![sam build --parallel --use-container](/img/sam-build-parallel-use-container.png)

### C) Build using PowerShell for Windows
You can use native PowerShell for Windows to download and extract the custom runtime and Lambda layer files. This performs the same file copy functionality as the Makefile. It adds the files to the source folders rather than a build location for subsequent deployment with AWS SAM. Use this option for Windows without WSL or Docker.

```
.\build-layers.ps1
```
![.\build-layers.ps1](/img/build-layers.png)

### Test the function locally

Once the build process is complete, you can use AWS SAM to test the function locally. 

```
sam local invoke
```
This uses a Lambda-like environment to run the function locally and returns the function response, which is the result of `Get-AWSRegion`.

![sam local invoke](/img/sam-local-invoke.png)

### Deploying to the AWS Cloud
Use AWS SAM to deploy the resources to your AWS account. Run a guided deployment to set the default parameters for the first deploy.
```
sam deploy -g
```
For subsequent deployments you can use `sam deploy`.

Enter a **Stack Name** and accept the remaining initial defaults.

![sam deploy -g](/img/sam-deploy-g.png)

AWS SAM deploys the infrastructure and outputs the details of the resources.

![AWS SAM resources](/img/aws-sam-resources.png)

### Using the reusable runtimes and AWS.Tools.Common layer in a SAM template

This example deploys layers that can be used to build a Lambda function written in Powershell. Each runtime registers a Systems Manager Parameter Store parameter with the value being the Amazon Resource Name (ARN) of the latest version of that layer:
* Arm64: lambda-powershell-runtime-arm64-latest-version-arn
* x86_64: lambda-powershell-runtime-x64-latest-version-arn
* AWS.Tools.Common: lambda-powershell-PSAWSTools-latest-version-arn

An example of usage:
```
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31

Resources:
  MyPowershellFunction:
    Type: AWS::Serverless::Function
    Properties:
      Description: A function that uses the arm64 runtime
      CodeUri: function/ # Place your Powershell scripts/modules in this folder
      Runtime: provided.al2
      Architectures: [ arm64 ]
      # Assuming you are using the 'script' method - ensure this script is in the folder named "function"
      Handler: script.ps1
      MemorySize: 1024
      Timeout: 100
      # Use CloudFormation's native support for SSM parameters to look up the latest version
      Layers: [ '{{resolve:ssm:lambda-powershell-runtime-arm64-latest-version-arn}}' ]
```

## Cleanup

To delete the AWS resources created, run the following and confirm that you want to delete the resources that were created by this template.
````
sam delete
````
