# PowerShell Lambda Runtime Tests

This directory contains unit tests and integration tests for the AWS Lambda PowerShell runtime using Pester as the testing framework.

## Test Coverage

The test suite validates:

*   **HTTP API interactions** with a mocked Lambda Runtime API via TestLambdaRuntimeServer
*   **Module loading and function export** validation for the main runtime module (`pwsh-runtime.psm1`)
*   **Build process validation** for the build script (`build-PwshRuntimeLayer.ps1`)
*   **Environment variable management** and Lambda context object creation
*   **Handler detection logic** for Script, Function, and Module handler types
*   **Response formatting and encoding** including JSON serialization and UTF-8 handling
*   **Integration tests** with real AWS Lambda functions (manual execution only, not included in CI)

## Directory Structure

```text
tests/
├── unit/                    # Unit tests (automated in CI)
│   ├── Private/            # Private runtime function tests
│   ├── Module/             # Runtime module tests
│   └── Build/              # Build script tests
├── integration/            # Integration tests (manual execution only)
│   ├── Lambda-Integration.Tests.ps1    # Integration test suite
│   └── infrastructure/     # Test infrastructure (CloudFormation)
├── helpers/                # Test utilities and helpers
├── Invoke-Tests.ps1        # Test runner script
├── PesterSettings.psd1     # Pester configuration
└── README.md              # This file
```

## Test Categories

### Unit Tests (Automated)

Unit tests validate individual functions and components in isolation and run automatically in CI:

*   **Private Function Tests**: Test all private runtime functions including handler detection, API calls, response handling, and environment setup
*   **Module Tests**: Test the main runtime module interface and public functions
*   **Build Tests**: Test build scripts and deployment processes

### Integration Tests (Manual Only)

Integration tests validate end-to-end functionality with real AWS infrastructure:

*   **Purpose**: Test runtime with actual Lambda functions in AWS
*   **Execution**: Manual only - not included in CI/CD pipelines
*   **Infrastructure**: Requires deployed CloudFormation stacks
*   **Handler Types**: Tests Script, Function, and Module handlers
*   **Use Cases**: Pre-release validation, troubleshooting, development verification

### Helper Utilities

Test utilities and helpers support the test suite:

*   **TestLambdaRuntimeServer**: HTTP server for Lambda Runtime API simulation
*   **TestUtilities**: Environment management and test setup functions
*   **AssertionHelpers**: Custom assertions for runtime-specific validations

## Running Tests

### Prerequisites

**All Tests:**

*   **PowerShell 7.0 or later** (see main README for installation)
*   Pester 5.7.1 or later (automatically installed if missing)

**Integration Tests Only:**

*   AWS SAM CLI installed and configured
*   AWS credentials configured with appropriate permissions
*   CloudFormation permissions for stack operations
*   Lambda execution permissions

### Automated Tests (CI)

```powershell
cd powershell-runtime/tests/

# Run all automated tests (unit and build)
pwsh -NoProfile -Command "& './Invoke-Tests.ps1'"

# Run only unit tests
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestType Unit"

# Run only build tests
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestType Build"

# Run tests against built module (validation testing)
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestBuiltModule"

# Run with code coverage analysis
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -Coverage"

# Run in CI mode with validation
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -CI"
```

### Integration Tests (Manual Only)

Integration tests require manual execution and AWS infrastructure setup:

```powershell
# Basic integration test execution
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestType Integration"

# Integration tests with specific stack and region
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestType Integration -StackName 'my-test-stack' -Region 'us-east-1' -ProfileName 'dev'"
```

### Additional Test Options

```powershell
# Run specific test files
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -Path './unit/Private/Get-Handler.Tests.ps1'"

# Run with detailed Pester output for debugging
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -DetailedOutput"

# Run with specific output format
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -OutputFormat NUnitXml"
```

### Available Parameters

The `Invoke-Tests.ps1` script supports the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `TestType` | String | 'All' | Test category: 'All', 'Unit', 'Build', 'Integration' |
| `Path` | String[] | - | Specific test files or directories to run |
| `TestBuiltModule` | Switch | False | Test against built module instead of source files |
| `CI` | Switch | False | Enable CI mode with enhanced validation and cleanup |
| `Coverage` | Switch | False | Enable code coverage analysis with JaCoCo output |
| `OutputFormat` | String | 'Console' | Test result format: 'Console', 'NUnitXml', 'JUnitXml' |
| `DetailedOutput` | Switch | False | Enable detailed Pester output for debugging |
| `StackName` | String | 'powershell-runtime-integration-test-infrastructure' | CloudFormation stack name (integration tests only) |
| `Region` | String | 'us-east-1' | AWS region (integration tests only) |
| `ProfileName` | String | - | AWS profile name (integration tests only) |

### Test Execution Modes

#### Automated vs Manual Testing

*   **Automated Tests (CI)**: Unit and Build tests run automatically in CI/CD
*   **Manual Tests**: Integration tests require manual execution with AWS setup
*   **CI Mode**: Automatically excludes integration tests and enables built module testing

#### Source vs Built Module Testing

The test runner supports two execution modes:

*   **Source Mode (Default)**: Tests source files directly for development iteration
    *   Uses individual source files from `source/modules/`
    *   Execution for development
    *   Coverage analysis includes source files
    *   Command: `./Invoke-Tests.ps1`

*   **Built Module Mode**: Tests the built/merged module for validation
    *   Uses the built module from `layers/runtimeLayer/modules/pwsh-runtime.psm1`
    *   Validates deployment artifact
    *   Coverage analysis includes the built module
    *   Command: `./Invoke-Tests.ps1 -TestBuiltModule`
    *   Builds the module if needed

## Integration Test Infrastructure Setup

Integration tests require a 3-step manual deployment process:

### Step 1: Deploy PowerShell Runtime

```bash
cd powershell-runtime/
sam build
sam deploy
```

### Step 2: Deploy Integration Test Infrastructure

```bash
cd powershell-runtime/tests/integration/infrastructure/
sam build
sam deploy --parameter-overrides PowerShellRuntimeLayerArn=<RUNTIME_LAYER_ARN_FROM_STEP_1>
```

### Step 3: Execute Integration Tests

```powershell
cd powershell-runtime/tests/
pwsh -NoProfile -c "./Invoke-Tests.ps1 -TestType Integration -StackName powershell-runtime-integration-test-infrastructure -Region us-west-2 -ProfileName default"
```

## Test Configuration

Test settings are configured in:

*   `../test-requirements.psd1` - Module dependencies, test requirements, and coverage settings
*   `PesterSettings.psd1` - Pester-specific configuration including output formats and mock settings

### Key Configuration Settings

**Coverage Requirements:**

*   Minimum code coverage: 80%
*   Coverage includes the built runtime module and build scripts
*   JaCoCo format output for CI/CD integration

## Writing Tests

### Test File Naming Convention

*   Unit tests: `<ComponentName>.Tests.ps1`
*   Integration tests: `<ComponentName>-Integration.Tests.ps1`

### Test Pattern Example

```powershell
Describe "Get-Handler" {
    BeforeAll {
        # Import test utilities
        . "$PSScriptRoot/../../helpers/TestUtilities.ps1"
        Initialize-TestEnvironment
    }

    Context "When handler type is Script" {
        It "Should detect script handler with .ps1 extension" {
            $env:_HANDLER = "handler.ps1"
            $result = pwsh-runtime\Get-Handler
            $result.handlerType | Should -Be 'Script'
        }
    }
}
```

For HTTP API testing, use `TestLambdaRuntimeServer` instead of mocking .NET types. See existing test files for patterns.

### Testing Approach

**Key Testing Principles:**

*   **Use TestLambdaRuntimeServer**: All HTTP-based tests use the test server instead of mocking .NET types
*   **Test Isolation**: Use proper setup and cleanup in test containers
*   **Real Infrastructure**: Integration tests use actual AWS Lambda functions

**Available Helper Functions:**

*   `TestLambdaRuntimeServer.ps1` - HTTP server for Lambda Runtime API testing
*   `TestUtilities.ps1` - Test setup, module loading, event generation
*   `AssertionHelpers.ps1` - Custom assertions for runtime-specific validations

## Coverage Requirements

*   **Target**: 80% minimum code coverage
*   **Scope**: Runtime functions, modules, and build scripts
*   **Exclusions**: Integration tests do not contribute to coverage metrics

## Troubleshooting

### Common Issues

**All Tests:**

1.  **Pester not found**: The test runner will automatically install Pester 5.7.1+
1.  **Module import errors**: Ensure the runtime module exists at `source/modules/pwsh-runtime.psm1`
1.  **Test server issues**: Check that port 9001 is available or specify a different port
1.  **Coverage issues**: Ensure the module is built before running coverage tests

**Integration Tests Only:**

1.  **Stack not found**: Verify CloudFormation stack exists and you have access permissions
1.  **AWS credential errors**: Ensure AWS credentials are configured and valid
1.  **Region mismatch**: Verify the specified region matches your stack deployment
1.  **Profile not found**: Check that the specified AWS profile exists and is configured
1.  **Lambda timeout errors**: Integration tests may take longer due to cold starts

## Contributing

When adding new tests:

1.  **Follow the established directory structure** - Unit tests in `unit/`, integration tests in `integration/`
1.  **Use the TestLambdaRuntimeServer** - Make real HTTP calls instead of mocking .NET types
1.  **Include scenarios** - Test success paths, error handling, and edge cases
1.  **Proper test isolation** - Use `BeforeAll`/`AfterAll` for setup/cleanup
1.  **Descriptive test names** - Clearly describe what is being tested
1.  **Update documentation** - Update this README when adding new test categories
1.  **Follow established patterns** - Reference existing test files for structure and conventions
1.  **Integration test considerations** - Ensure integration tests clean up AWS resources and handle failures gracefully
