# Demo-ASCIIArt

This is a demo SAM application [demo-asciiart](examples/demo-asciiart/) uses AWS SAM to deploy a Lambda function that uses a Powershell script to render ASCII art using the WriteAscii Powershell module.

### Pre-requisites: 
* Deploy the [reusable-runtime](examples/reusable-runtime/) example.
* [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/)

Clone the repository and change into the example directory
```
git clone https://github.com/awslabs/aws-lambda-powershell-runtime
cd aws-lambda-powershell-runtime/examples/demo-asciiart
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

### Test the function locally

Once the build process is complete, you can use AWS SAM to test the function locally. 

```
sam local invoke
```
This uses a Lambda-like environment to run the function locally and returns the function response, which is an ASCII art rendering of "Hello, World!".

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

### View, edit, and invoke the function in the AWS Management Console

You can view, edit code, and invoke the Lambda function in the Lambda Console.

Navigate to the *Functions* page and choose the function specified in the `sam deploy` *Outputs*.

Using the built-in [code editor](https://docs.aws.amazon.com/lambda/latest/dg/foundation-console.html#code-editor), you can view the function code. 

![lambda-console-code](/img/lambda-console-code.png)

To invoke the function, select the **Test** button and create a test event. For more information on invoking a function with a test event, see the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/getting-started-create-function.html#get-started-invoke-manually). 

You can see the results in the *Execution result* pane.

You can also view a snippet of the generated *Function Logs* below the *Response*. View the full logs in [Amazon CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs). You can navigate directly via the *Monitor* tab.

![lambda-console-test](/img/lambda-console-test.png)

### Invoke the function using the AWS CLI

From a command prompt, invoke the function. Amend the `--function-name` and `--region` values for your function. This should return `"StatusCode": 200` for a successful invoke.

````
aws lambda invoke --function-name "DemoAsciiArtFunction-6W3bn1znmW8G" --region us-east-1 invoke-result 
````

View the function results which are outputted to `invoke-result`.

````
cat invoke-result
````

![cat-invoke-result.png](/img/cat-invoke-result.png)

### Invoke the function using the AWS Tools for PowerShell

You can invoke the Lambda function using the AWS Tools for PowerShell and capture the response in a variable. The response is available in the `Payload` property of the `$result` object which can be read using the .NET `StreamReader` class.
````
$Response = Invoke-LMFunction -FunctionName DemoAsciiArtFunction-HHdKLkXxnkUn -LogType Tail
[System.IO.StreamReader]::new($Response.Payload).ReadToEnd()

````
This outputs the ASCII art response.

## Cleanup

To delete the AWS resources created, run the following and confirm that you want to delete the resources that were created by this template.
````
sam delete
````
