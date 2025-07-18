# PowerShell Lambda Runtime Tests

This directory contains unit tests for the AWS Lambda PowerShell runtime using Pester as the testing framework.

## Test Coverage Details

The test suite provides validation of:

*   ✅ **HTTP API interactions** with a mocked Lambda Runtime API via TestLambdaRuntimeServer
*   ✅ **Module loading and function export** validation for the main runtime module (`pwsh-runtime.psm1`)
*   ✅ **Build process validation** for the build script (`build-PwshRuntimeLayer.ps1`)
*   ✅ **Environment variable management** and Lambda context object creation
*   ✅ **Handler detection logic** for Script, Function, and Module handler types
*   ✅ **Response formatting and encoding** including JSON serialization and UTF-8 handling
*   ⏳ **Integration tests** are planned for future implementation

## Directory Structure

```text
tests/
├── unit/                    # Unit tests
│   ├── Private/            # Private runtime function tests
│   ├── Module/             # Runtime module tests
│   └── Build/              # Build script tests
├── helpers/                # Test utilities and helpers
├── fixtures/               # Test data and mock objects
├── Invoke-Tests.ps1        # Test runner script
└── README.md              # This file
```

## Test Categories

### Unit Tests

Unit tests validate individual functions and components in isolation:

*   **Private Function Tests**: Test all private runtime functions including handler detection, API calls, response handling, and environment setup
*   **Module Tests**: Test the main runtime module interface and public functions
*   **Build Tests**: Test build scripts and deployment processes

### Helper Utilities

Test utilities and helpers support the test suite:

*   **TestLambdaRuntimeServer**: HTTP server for Lambda Runtime API simulation
*   **TestUtilities**: Environment management and test setup functions
*   **AssertionHelpers**: Custom assertions for runtime-specific validations

## Running Tests

### Prerequisites

*   **PowerShell 7.0 or later** (see main README for installation)
*   Pester 5.7.1 or later (automatically installed if missing)

### Basic Usage

```powershell
cd powershell-runtime/tests/

# Run all tests (default: source file testing for fast development)
pwsh -NoProfile -Command "& './Invoke-Tests.ps1'"

# Run only unit tests
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestType Unit"

# Run only build tests
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestType Build"

# Run tests against built module (validation testing)
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -TestBuiltModule"

# Run with code coverage analysis
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -Coverage"

# Run with code coverage against built module
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -Coverage -TestBuiltModule"

# Run in CI mode with full validation
pwsh -NoProfile -Command "& './Invoke-Tests.ps1' -CI"

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
| `TestType` | String | 'All' | Test category to run: 'All', 'Unit', 'Build' |
| `Path` | String[] | - | Specific test files or directories to run |
| `TestBuiltModule` | Switch | False | Test against built module instead of source files |
| `CI` | Switch | False | Enable CI mode with enhanced validation and cleanup |
| `Coverage` | Switch | False | Enable code coverage analysis with JaCoCo output |
| `OutputFormat` | String | 'Console' | Test result format: 'Console', 'NUnitXml', 'JUnitXml' |
| `DetailedOutput` | Switch | False | Enable detailed Pester output for debugging |

### Test Types and Execution Modes

#### Test Categories

*   **Unit Tests**: Test individual functions and components in isolation using the TestLambdaRuntimeServer for HTTP API calls
*   **Build Tests**: Test build scripts and deployment processes including PowerShell runtime download and module merging
*   **Helper Tests**: Test the testing infrastructure itself (test utilities, assertion helpers, test server)

#### Execution Modes

The test runner supports two execution modes:

*   **Source Mode (Default)**: Tests source files directly for fast development iteration
    *   Uses individual source files from `source/modules/`
    *   Faster execution, ideal for development
    *   Coverage analysis includes source files
    *   Command: `./Invoke-Tests.ps1`

*   **Built Module Mode**: Tests the built/merged module for validation
    *   Uses the built module from `layers/runtimeLayer/modules/pwsh-runtime.psm1`
    *   Slower execution, validates final deployment artifact
    *   Coverage analysis includes the built module
    *   Command: `./Invoke-Tests.ps1 -TestBuiltModule`
    *   Automatically builds the module if needed

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

### Test Structure

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

For HTTP API testing, use `TestLambdaRuntimeServer` instead of mocking .NET types. See existing test files for complete patterns.

### Testing Approach

**Key Testing Principles:**

*   **Use TestLambdaRuntimeServer**: All HTTP-based tests use the test server instead of mocking .NET types

**Available Helper Functions:**

*   `TestLambdaRuntimeServer.ps1` - HTTP server for Lambda Runtime API testing
*   `TestUtilities.ps1` - Test setup, module loading, event generation
*   `AssertionHelpers.ps1` - Custom assertions for runtime-specific validations

## Coverage Requirements

*   **Target**: 80% minimum code coverage
*   **Scope**: Runtime functions, modules, and build scripts

## Troubleshooting

### Common Issues

1.  **Pester not found**: The test runner will automatically install Pester 5.7.1+
1.  **Module import errors**: Ensure the runtime module exists at `source/modules/pwsh-runtime.psm1`
1.  **Test server issues**: Check that port 9001 is available or specify a different port
1.  **Coverage issues**: Ensure the module is built before running coverage tests
1.  **HTTP timeout errors**: Increase timeout settings in test configuration

## Test Coverage

Tests cover runtime functions, HTTP API interactions, environment management, response handling, logging, build processes, and module loading.

## Contributing

When adding new tests:

1.  **Follow the established directory structure** - Unit tests in `unit/`, helpers in `helpers/`
1.  **Use the TestLambdaRuntimeServer** - Make real HTTP calls instead of mocking .NET types
1.  **Include scenarios** - Test success paths, error handling, and edge cases
1.  **Proper test isolation** - Use `BeforeAll`/`AfterAll` for setup/cleanup
1.  **Descriptive test names** - Clearly describe what is being tested
1.  **Update documentation** - Update this README when adding new test categories
1.  **Follow established patterns** - Reference existing test files for structure and conventions
