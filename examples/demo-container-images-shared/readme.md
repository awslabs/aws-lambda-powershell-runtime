# Demo-container-images-shared

Demo application to deploy a PowerShell Lambda function using existing [container image](https://docs.aws.amazon.com/lambda/latest/dg/images-create.html) layers. The container image can be up to 10Gb in size which allows you to build functions larger than the 256MB limit for .zip archive functions. This allows you to include the entire [AWSTools for PowerShell](https://aws.amazon.com/powershell/) SDK, for example.

The build process initially creates two base image layers which makes it easier to share these base layers with multiple functions:

1. PowerShell custom runtime based on ````provided.al2023````. This downloads the specified version of [PowerShell](https://github.com/PowerShell/PowerShell/releases/) and adds the custom runtime files from the [PowerShell-runtime](../../powershell-runtime/) folder.
2. The [AWSTools for PowerShell](https://aws.amazon.com/powershell/) with the entire AWS SDK. You can amend the loaded modules within the Dockerfile to only include specific modules. ````AWS.Tools.Common```` is required

You can then create Lambda functions by importing the two image layers and then adding the function code in the [function](./function) folder.

You build the initial base layers using [Docker Desktop](https://docs.docker.com/get-docker/) and the AWS CLI.

### Pre-requisites

* [Docker Desktop](https://docs.docker.com/get-docker/)
* [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/)

1. Clone the repository and change into the example directory

```shell
git clone https://github.com/awslabs/aws-lambda-powershell-runtime
cd aws-lambda-powershell-runtime/examples/demo-container-images-shared
```

2. Login to [Amazon Elastic Container Registry (ECR)](https://aws.amazon.com/ecr/) which is used to store the container images. Replace the `<region>` and `<account>` values.
```shell
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com
```

## Build the PowerShell runtime base layer.

1. Change into the `powershell-runtime` directory

```shell
cd powershell-runtime
```
2. Create an ECR repository. Rename `--repository-name` from `powershell-runtime` to your prefered name if required.
```shell
aws ecr create-repository --repository-name powershell-runtime
```

3. Build the Docker image. Rename the image name in the following steps from `powershell-runtime:latest` if required. Replace the `<region>` and `<account>` values.
```shell
docker build -t <account>.dkr.ecr.<region>.amazonaws.com/powershell-runtime:latest .
```

4. Push the Docker image. Replace the `<region>` and `<account>` values.
```shell
docker push <account>.dkr.ecr.<region>.amazonaws.com/powershell-runtime:latest
```

## Build the PowerShell modules AWS Tools base layer.

1. Change into the `powershell-modules-aws-tools` directory

```shell
cd ../powershell-modules-aws-tools
```
2. Create an ECR repository. Rename `--repository-name` from `powershell-modules-aws-tools` to your prefered name if required.
```shell
aws ecr create-repository --repository-name powershell-modules-aws-tools
```

3. Build the Docker image. Rename the image name in the following steps from `powershell-modules-aws-tools:latest` if required. Replace the `<region>` and `<account>` values.
```shell
docker build -t <account>.dkr.ecr.<region>.amazonaws.com/powershell-modules-aws-tools:latest .
```

4. Push the Docker image. Replace the `<region>` and `<account>` values.
```shell
docker push <account>.dkr.ecr.<region>.amazonaws.com/powershell-runtime:latest
```

## Build the Lambda function

The [Dockerfile](Dockerfile) for the container image then adds the previously created layers and adds the function code.

You can then use the same process to build multiple Lambda functions using the same base layers which simplifies the build process and allows you to manage the base layers separately.
```Dockerfile
#FROM public.ecr.aws/lambda/provided:al2023
## INSTALL POWERSHELL RUNTIME
FROM <account>.dkr.ecr.<region>.amazonaws.com/runtime-powershell:latest as runtime-files
## INSTALL AWS SDK
FROM <account>.dkr.ecr.<region>.amazonaws.com/powershell-modules-aws-tools:latest as module-files

## Build final image
FROM public.ecr.aws/lambda/provided:al2023
## Copy PowerShell runtime files
COPY --from=runtime-files . /
## Copy Module files
COPY --from=module-files . /
## Function files
COPY /function/ /var/task
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1
WORKDIR /var/task
ENTRYPOINT  [ "/var/runtime/bootstrap" ]
CMD [ "examplehandler.ps1::handler" ]
```

1. Change into the parent directory

```shell
cd ..
```
2. Create an ECR repository. Rename `--repository-name` from `demo-container-images-shared` to your prefered name if required.
```shell
aws ecr create-repository --repository-name demo-container-images-shared
```

3. Build the Docker image. Rename the image name in the following steps from `demo-container-images-shared:latest` if required. Replace the `<region>` and `<account>` values.
```shell
docker build -t <account>.dkr.ecr.<region>.amazonaws.com/demo-container-images-shared:latest .
```

4. Push the Docker image. Replace the `<region>` and `<account>` values.
```shell
docker push <account>.dkr.ecr.<region>.amazonaws.com/demo-container-images-shared:latest
```

### Create the Lambda function
1. Create a Lambda function execution IAM Role using the [documentation](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html).

2. Create a Lambda function using the AWS CLI. Replace the `<region>` and `<account>` values. Enter the correct IAM Role name for `--role`. You can amend the `--memory-size` and `--timeout` if required.
```shell
aws lambda create-function --region <region> --function-name demo-container-images-shared --package-type Image --memory-size 1024 --timeout 30 --code ImageUri=<account>.dkr.ecr.<region>.amazonaws.com/demo-container-images-shared:latest --role "arn:aws:iam::<account>:role/lambda-exec-role"
```

To make further configuration changes, you can use `aws lambda update-function-configuration`. For example, to increase the timeout.

```shell
aws lambda update-function-configuration --region <region> --function-name demo-container-images-shared --timeout 45
```
### Invoke the function using the AWS CLI

Once the Lambda function is deployed, you can invoke it using the AWS CLI.

1. From a command prompt, invoke the function. Amend the `--function-name` and `--region` values for your function.

This should return `"StatusCode": 200` for a successful invoke.

````shell
aws lambda invoke --function-name demo-container-images-shared --region <region> invoke-result
````

2. View the function results which are outputted to `invoke-result`.

````shell
cat invoke-result
````

![cat-invoke-result.png](/img/cat-invoke-result.png)

## Build and deploy using [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/).

You can also build and deploy the Lambda function using AWS SAM, once the base layers are built and pushed to the ECR repositories using Docker.

### Pre-requisites

* [AWS Serverless Application Model (AWS SAM)](https://aws.amazon.com/serverless/sam/)
* [AWS Command Line Interface (AWS CLI)](https://aws.amazon.com/cli/)

### Build the container image function

1. use `sam build` to build the container image.

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

2. Enter a **Stack Name** such as `demo-container-images-shared` and accept the remaining initial defaults.

AWS SAM deploys the infrastructure and outputs the function name `Value`.

### Invoke the function using AWS SAM

Once the Lambda function is deployed, you can invoke it in the cloud using AWS SAM `remote invoke`.

1. From a command prompt, invoke the function. Amend the `--stack-name` from `demo-container-images-shared` if required.

```shell
sam remote invoke --stack-name demo-container-images-shared
```

This should return a successful invoke with the result of `Get-AWSRegion`.

### AWS SAM cleanup

To delete the AWS resources created, run the following and confirm that you want to delete the resources that were created by this template.

````shell
sam delete
````

