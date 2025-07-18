# PowerShell Runtime Integration Test Infrastructure

This directory contains AWS SAM template and function code for PowerShell Lambda Runtime integration tests.

## Directory Structure

```text
infrastructure/
├── function/                   # Lambda function code and utilities
│   ├── Get-LambdaContextInfo.ps1         # Lambda context utility function
│   ├── Makefile                          # Build configuration
│   ├── test-function-handler.ps1         # Function handler test
│   ├── test-script-handler.ps1           # Script handler test
│   ├── test-failing-script-handler.ps1   # Failing script handler test
│   └── modules/                          # PowerShell modules
│       └── test-module-handler/          # Module handler test module
│           └── 1.0.0/
│               ├── test-module-handler.psd1
│               └── test-module-handler.psm1
├── template.yml                # CloudFormation template
└── README.md                   # This file
```

## Infrastructure Components

The template creates AWS resources for integration testing, such as Lambda functions and associated resources.

## Prerequisites

*   **AWS SAM CLI** installed and configured
*   **AWS credentials** configured with appropriate permissions
*   **PowerShell 7.0 or later** (see main README for installation)

## Deployment

### Build Resources

```bash
sam build
```

### Deploy Stack

```bash
sam deploy
```

### Deploy with Existing Runtime Layer

```bash
sam deploy --parameter-overrides PowerShellRuntimeLayerArn=arn:aws:lambda:us-east-1:123456789012:layer:powershell-runtime:1
```

### Clean Up

```bash
sam delete
```

## Test Functions

The infrastructure includes four Lambda functions testing each PowerShell handler type:

| Handler Type | Function Name | Handler | Purpose |
|--------------|---------------|---------|---------|
| Script | `ScriptHandlerFunction` | `test-script-handler.ps1` | Direct PowerShell script execution |
| Function | `FunctionHandlerFunction` | `test-function-handler.ps1::Invoke-TestFunction` | PowerShell function execution within a script |
| Module | `ModuleHandlerFunction` | `Module::test-module-handler::Invoke-TestModuleHandler` | PowerShell module function execution |
| Failing Script | `ScriptHandlerFailingFunction` | `test-failing-script-handler.ps1` | Error handling and failure scenarios |
