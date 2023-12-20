# Demo-container-image-all-aws-sdk

Demo application to deploy a PowerShell Lambda function using a [container image](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html). The container image can be up to 10Gb in size which allows you to build functions larger than the 256MB limit for .zip archive functions. This allows you to include the entire [AWSTools for PowerShell](https://aws.amazon.com/powershell/) SDK, for example.

The container image contains the following components:

1. PowerShell custom runtime based on ````provided.al2023````. This downloads the specified version of [PowerShell](https://github.com/PowerShell/PowerShell/releases/) and adds the custom runtime files from the [PowerShell-runtime](../../powershell-runtime/) folder.
2. The [AWSTools for PowerShell](https://aws.amazon.com/powershell/) with the entire AWS SDK. You can amend the loaded modules within the Dockerfile to only include specific modules. ````AWS.Tools.Common```` is required
3. Lambda function code in the [function](./function) folder.

You can build and deploy the demo using either of the two options:

* A: [Docker Desktop](https://docs.docker.com/get-docker/) and the AWS CLI
* B: [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/)

Use one of the *"Build and deploy"* options, A,B depending on your tools.

## A) Build and deploy using Docker Desktop and the AWS CLI.

### Pre-requisites

* [Docker Desktop](https://docs.docker.com/get-docker/)
* [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/)

### Build and push the container image

1. Clone the repository and change into the example directory

```shell
git clone https://github.com/awslabs/aws-lambda-powershell-runtime
cd aws-lambda-powershell-runtime/examples/demo-container-image-all-aws-sdk
```

2. Create an [Amazon Elastic Container Registry (ECR)](https://aws.amazon.com/ecr/) repository to store the container image.

3. Login to ECR. Replace the `<region>` and `<account>` values.
```shell
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
```

4. Create the repository. Rename `--repository-name` from `demo-container-image-all-aws-sdk` to your prefered name if required.
```shell
aws ecr create-repository --repository-name demo-container-image-all-aws-sdk
```

5. Build the Docker image. Rename the image name in the following steps from `demo-container-image-all-aws-sdk:latest` if required.
```shell
docker build -t demo-container-image-all-aws-sdk:latest .
```

6. Tag and push the Docker image. Replace the `<region>` and `<account>` values.
```shell
docker tag demo-container-image-all-aws-sdk:latest <account>.dkr.ecr.<region>.amazonaws.com/demo-container-image-all-aws-sdk:latest
docker push <account>.dkr.ecr.<region>.amazonaws.com/demo-container-image-all-aws-sdk:latest
```

### Create the Lambda function
1. Create a Lambda function execution IAM Role using the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html).

2. Create a Lambda function using the AWS CLI. Replace the `<region>` and `<account>` values. Enter the correct IAM Role name for `--role`. You can amend the `--memory-size` and `--timeout` if required.
```shell
aws lambda create-function --region <region>  --function-name demo-container-image-all-aws-sdk --package-type Image --memory-size 1024 --timeout 30 --code ImageUri=<account>.dkr.ecr.<region>.amazonaws.com/demo-container-image-all-aws-sdk:latest --role "arn:aws:iam::<account>:role/lambda-exec-role"
```

To make further configuration changes, you can use `aws lambda update-function-configuration`. For example, to increase the timeout.

```shell
aws lambda update-function-configuration --region <region> --function-name demo-container-image-all-aws-sdk  --timeout 45
```
### Invoke the function using the AWS CLI

Once the Lambda function is deployed, you can invoke it using the AWS CLI.

1. From a command prompt, invoke the function. Amend the `--function-name` and `--region` values for your function.

This should return `"StatusCode": 200` for a successful invoke.

````shell
aws lambda invoke --function-name demo-container-image-all-aws-sdk --region <region> invoke-result
````

2. View the function results which are outputted to `invoke-result`.

````shell
cat invoke-result
````

![cat-invoke-result.png](/img/cat-invoke-result.png)

## B) Build and deploy using [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/).

### Pre-requisites

* [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/)
* [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/)

### Build the container image function
1. Clone the repository and change into the example directory

```shell
git clone https://github.com/awslabs/aws-lambda-powershell-runtime
cd aws-lambda-powershell-runtime/examples/demo-container-image-all-aws-sdk
```

2. use `sam build` to build the container image.

```shell
sam build
```
### Test the function locally

Once the build process is complete, you can use AWS SAM to test the function locally.

```shell
sam local invoke
```

This uses a Lambda-like environment to run the function locally and returns the function response, which is the result of `Get-AWSRegion`.

![sam local invoke](/img/sam-local-invoke.png)

### Deploying to the AWS Cloud

Use AWS SAM to deploy the resources to your AWS account.

1. Run a guided deployment to set the default parameters for the first deploy.

```shell
sam deploy -g
```
For subsequent deployments you can use `sam deploy`.

2. Enter a **Stack Name** such as `demo-container-image-all-aws-sdk` and accept the remaining initial defaults.

AWS SAM deploys the infrastructure and outputs the function name `Value`.

### Invoke the function using AWS SAM

Once the Lambda function is deployed, you can invoke it in the cloud using AWS SAM `remote invoke`.

1. From a command prompt, invoke the function. Amend the `--stack-name` from `demo-container-image-all-aws-sdk` if required.

```shell
sam remote invoke --stack-name demo-container-image-all-aws-sdk
```

This should return a successful invoke with the result of `Get-AWSRegion`.

### Invoke the function using the AWS CLI

Once the Lambda function is deployed, you can also invoke it using the AWS CLI.

1. From a command prompt, invoke the function. Amend the `--function-name` and `--region` values for your function.

This should return `"StatusCode": 200` for a successful invoke.

````shell
aws lambda invoke --function-name demo-container-image-all-aw-DemoPowerShellFunction-Nwecb1EWXKq6 --region <region> invoke-result
````

2. View the function result of `AWS-GetRegion` which is outputted to `invoke-result`.

````shell
cat invoke-result
````

![cat-invoke-result.png](/img/cat-invoke-result.png)

### AWS SAM cleanup

To delete the AWS resources created, run the following and confirm that you want to delete the resources that were created by this template.

````shell
sam delete
````

