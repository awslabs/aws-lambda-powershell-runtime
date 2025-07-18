# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Unit tests for AssertionHelpers.ps1 functionality.

.DESCRIPTION
    Validates that all assertion helper functions work correctly for Lambda runtime testing.
    Tests cover positive cases, negative cases, and edge conditions for each assertion function.
#>

BeforeAll {
    # Dot-source the AssertionHelpers script
    . "$PSScriptRoot/AssertionHelpers.ps1"
    . "$PSScriptRoot/TestLambdaRuntimeServer.ps1"
}

Describe "Assert-EnvironmentVariable" {
    BeforeEach {
        # Clean up test environment variables
        [System.Environment]::SetEnvironmentVariable('TEST_VAR', $null)
        [System.Environment]::SetEnvironmentVariable('TEST_VAR_2', $null)
    }

    Context "When environment variable exists with expected value" {
        It "Should pass assertion for correct value" {
            [System.Environment]::SetEnvironmentVariable('TEST_VAR', 'expected-value')

            { Assert-EnvironmentVariable -Name 'TEST_VAR' -ExpectedValue 'expected-value' } | Should -Not -Throw
        }

        It "Should pass assertion when only checking existence" {
            [System.Environment]::SetEnvironmentVariable('TEST_VAR', 'any-value')

            { Assert-EnvironmentVariable -Name 'TEST_VAR' } | Should -Not -Throw
        }
    }

    Context "When environment variable has wrong value" {
        It "Should throw for incorrect value" {
            [System.Environment]::SetEnvironmentVariable('TEST_VAR', 'wrong-value')

            { Assert-EnvironmentVariable -Name 'TEST_VAR' -ExpectedValue 'expected-value' } | Should -Throw -ExpectedMessage "*expected: 'expected-value', but was: 'wrong-value'*"
        }
    }

    Context "When environment variable does not exist" {
        It "Should throw when variable should exist" {
            { Assert-EnvironmentVariable -Name 'NONEXISTENT_VAR' } | Should -Throw -ExpectedMessage "*should exist but was not found*"
        }

        It "Should pass when variable should not exist" {
            { Assert-EnvironmentVariable -Name 'NONEXISTENT_VAR' -ShouldExist:$false } | Should -Not -Throw
        }
    }

    Context "When testing for null/empty values" {
        It "Should pass when variable is null and should be null" {
            { Assert-EnvironmentVariable -Name 'NONEXISTENT_VAR' -ShouldBeNull } | Should -Not -Throw
        }

        It "Should pass when variable is empty and should be null" {
            [System.Environment]::SetEnvironmentVariable('TEST_VAR', '')

            { Assert-EnvironmentVariable -Name 'TEST_VAR' -ShouldBeNull } | Should -Not -Throw
        }

        It "Should throw when variable has value but should be null" {
            [System.Environment]::SetEnvironmentVariable('TEST_VAR', 'not-null')

            { Assert-EnvironmentVariable -Name 'TEST_VAR' -ShouldBeNull } | Should -Throw -ExpectedMessage "*should be null or empty, but was: 'not-null'*"
        }
    }

    Context "When testing existence flags" {
        It "Should throw when variable exists but should not exist" {
            [System.Environment]::SetEnvironmentVariable('TEST_VAR', 'exists')

            { Assert-EnvironmentVariable -Name 'TEST_VAR' -ShouldExist:$false } | Should -Throw -ExpectedMessage "*should not exist, but was set to: 'exists'*"
        }
    }
}

Describe "Assert-ApiCall" {
    BeforeAll {
        $script:TestServer = Start-TestLambdaRuntimeServer -Port 9010
        Start-Sleep -Milliseconds 500
    }

    AfterAll {
        if ($script:TestServer) {
            Stop-TestLambdaRuntimeServer -Server $script:TestServer
        }
    }

    BeforeEach {
        Reset-TestServer -Server $script:TestServer
    }

    Context "When API calls are made correctly" {
        It "Should pass assertion for correct GET request" {
            # Make the API call
            Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Assert the call was made
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" } | Should -Not -Throw
        }

        It "Should pass assertion for correct POST request" {
            # Make the API call
            try {
                Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/test-123/response" -Method POST -Body "test response" -TimeoutSec 3
            } catch {
                # Expected - server returns 202
            }

            # Assert the call was made
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-123/response" -Method "POST" } | Should -Not -Throw
        }

        It "Should pass assertion with correct call count" {
            # Make multiple calls
            Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue
            Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Assert correct count
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" -ExpectedCallCount 2 } | Should -Not -Throw
        }

        It "Should pass assertion when checking request body content" {
            $testBody = "test response content"

            # Make the API call
            try {
                Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/test-456/response" -Method POST -Body $testBody -TimeoutSec 3
            } catch {
                # Expected - server returns 202
            }

            # Assert body content
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-456/response" -Method "POST" -ShouldContainBody "response content" } | Should -Not -Throw
        }
    }

    Context "When API calls are incorrect" {
        It "Should throw when expected call was not made" {
            { Assert-ApiCall -Server $script:TestServer -Path "/nonexistent/path" -Method "GET" } | Should -Throw -ExpectedMessage "*Expected 1 GET request(s) to '/nonexistent/path', but found 0*"
        }

        It "Should throw when call count is wrong" {
            # Make one call
            Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Expect two calls
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "GET" -ExpectedCallCount 2 } | Should -Throw -ExpectedMessage "*Expected 2 GET request(s)*but found 1*"
        }

        It "Should throw when method is wrong" {
            # Make GET call
            Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Expect POST call
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -Method "POST" } | Should -Throw -ExpectedMessage "*Expected 1 POST request(s)*but found 0*"
        }

        It "Should throw when body content is wrong" {
            $testBody = "wrong content"

            # Make the API call
            try {
                Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/test-789/response" -Method POST -Body $testBody -TimeoutSec 3
            } catch {
                # Expected - server returns 202
            }

            # Assert wrong body content
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/test-789/response" -Method "POST" -ShouldContainBody "expected content" } | Should -Throw -ExpectedMessage "*Expected request body to contain 'expected content'*"
        }
    }

    Context "When checking that calls should not be made" {
        It "Should pass when call was correctly not made" {
            { Assert-ApiCall -Server $script:TestServer -Path "/should/not/be/called" -ShouldNotBeCalled } | Should -Not -Throw
        }

        It "Should throw when call was made but should not have been" {
            # Make the call
            Invoke-RestMethod -Uri "http://localhost:9010/2018-06-01/runtime/invocation/next" -Method GET -TimeoutSec 3 -ErrorAction SilentlyContinue

            # Assert it should not have been called
            { Assert-ApiCall -Server $script:TestServer -Path "/2018-06-01/runtime/invocation/next" -ShouldNotBeCalled } | Should -Throw -ExpectedMessage "*should not have been called, but was called 1 times*"
        }
    }
}

Describe "Assert-JsonResponse" {
    Context "When JSON is valid and has expected properties" {
        It "Should pass for valid JSON" {
            $json = '{"test": "value", "number": 42}'

            { Assert-JsonResponse -JsonString $json } | Should -Not -Throw
        }

        It "Should pass when property exists" {
            $json = '{"statusCode": 200, "body": "success"}'

            { Assert-JsonResponse -JsonString $json -ShouldHaveProperty "statusCode" } | Should -Not -Throw
        }

        It "Should pass when property has expected value" {
            $json = '{"statusCode": 200, "body": "success"}'

            { Assert-JsonResponse -JsonString $json -ShouldHaveProperty "body" -PropertyValue "success" } | Should -Not -Throw
        }

        It "Should pass when JSON contains expected value" {
            $json = '{"message": "Hello World", "status": "ok"}'

            { Assert-JsonResponse -JsonString $json -ShouldContainValue "Hello World" } | Should -Not -Throw
        }

        It "Should handle complex nested JSON" {
            $json = '{"Records": [{"eventName": "s3:ObjectCreated:Put", "s3": {"bucket": {"name": "test-bucket"}}}]}'

            { Assert-JsonResponse -JsonString $json -ShouldHaveProperty "Records" } | Should -Not -Throw
            { Assert-JsonResponse -JsonString $json -ShouldContainValue "test-bucket" } | Should -Not -Throw
        }
    }

    Context "When JSON is invalid or missing properties" {
        It "Should throw for invalid JSON" {
            $invalidJson = '{"invalid": json}'

            { Assert-JsonResponse -JsonString $invalidJson } | Should -Throw -ExpectedMessage "*Expected valid JSON, but parsing failed*"
        }

        It "Should pass when JSON is expected to be invalid" {
            $invalidJson = '{"invalid": json}'

            { Assert-JsonResponse -JsonString $invalidJson -ShouldNotBeValidJson } | Should -Not -Throw
        }

        It "Should throw when expected property is missing" {
            $json = '{"statusCode": 200}'

            { Assert-JsonResponse -JsonString $json -ShouldHaveProperty "body" } | Should -Throw -ExpectedMessage "*should have property 'body'*"
        }

        It "Should throw when property has wrong value" {
            $json = '{"statusCode": 404, "body": "error"}'

            { Assert-JsonResponse -JsonString $json -ShouldHaveProperty "statusCode" -PropertyValue "200" } | Should -Throw -ExpectedMessage "*expected: '200', but was: '404'*"
        }

        It "Should throw when JSON does not contain expected value" {
            $json = '{"message": "Goodbye World"}'

            { Assert-JsonResponse -JsonString $json -ShouldContainValue "Hello World" } | Should -Throw -ExpectedMessage "*should contain value 'Hello World'*"
        }

        It "Should throw when valid JSON is expected to be invalid" {
            $validJson = '{"valid": "json"}'

            { Assert-JsonResponse -JsonString $validJson -ShouldNotBeValidJson } | Should -Throw -ExpectedMessage "*Expected invalid JSON, but parsing succeeded*"
        }
    }

    Context "When testing edge cases" {
        It "Should handle empty JSON object" {
            $json = '{}'

            { Assert-JsonResponse -JsonString $json } | Should -Not -Throw
        }

        It "Should handle JSON arrays" {
            $json = '[{"item": 1}, {"item": 2}]'

            { Assert-JsonResponse -JsonString $json } | Should -Not -Throw
            { Assert-JsonResponse -JsonString $json -ShouldContainValue "item" } | Should -Not -Throw
        }

        It "Should handle JSON with null values" {
            $json = '{"value": null, "other": "test"}'

            { Assert-JsonResponse -JsonString $json -ShouldHaveProperty "value" } | Should -Not -Throw
            { Assert-JsonResponse -JsonString $json -ShouldHaveProperty "other" -PropertyValue "test" } | Should -Not -Throw
        }
    }
}

Describe "Assert-HandlerType" {
    Context "When handler is a script file" {
        It "Should detect .ps1 files as Script type" {
            { Assert-HandlerType -HandlerString "handler.ps1" -ExpectedType "Script" } | Should -Not -Throw
        }

        It "Should detect .ps1 files with path as Script type" {
            { Assert-HandlerType -HandlerString "path/to/handler.ps1" -ExpectedType "Script" } | Should -Not -Throw
        }

        It "Should throw when .ps1 file is expected to be different type" {
            { Assert-HandlerType -HandlerString "handler.ps1" -ExpectedType "Function" } | Should -Throw -ExpectedMessage "*expected type: 'Function', but detected type: 'Script'*"
        }
    }

    Context "When handler is a function reference" {
        It "Should detect module::function format as Function type" {
            { Assert-HandlerType -HandlerString "MyModule::MyFunction" -ExpectedType "Function" } | Should -Not -Throw
        }

        It "Should detect complex function names as Function type" {
            { Assert-HandlerType -HandlerString "My.Complex.Module::Get-ComplexFunction" -ExpectedType "Function" } | Should -Not -Throw
        }

        It "Should throw when function format is expected to be different type" {
            { Assert-HandlerType -HandlerString "MyModule::MyFunction" -ExpectedType "Module" } | Should -Throw -ExpectedMessage "*expected type: 'Module', but detected type: 'Function'*"
        }
    }

    Context "When handler is a module name" {
        It "Should detect simple module names as Module type" {
            { Assert-HandlerType -HandlerString "MyModule" -ExpectedType "Module" } | Should -Not -Throw
        }

        It "Should detect complex module names as Module type" {
            { Assert-HandlerType -HandlerString "My-Complex-Module" -ExpectedType "Module" } | Should -Not -Throw
        }

        It "Should throw when module format is expected to be different type" {
            { Assert-HandlerType -HandlerString "MyModule" -ExpectedType "Script" } | Should -Throw -ExpectedMessage "*expected type: 'Script', but detected type: 'Module'*"
        }
    }

    Context "When handler format is invalid" {
        It "Should throw for empty handler string" {
            { Assert-HandlerType -HandlerString "" -ExpectedType "Script" } | Should -Throw -ExpectedMessage "*Unable to determine handler type*"
        }
    }
}

Describe "Assert-FileExists" {
    BeforeAll {
        # Create temporary test directory
        $script:TestDir = Join-Path ([System.IO.Path]::GetTempPath()) "assertion-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $script:TestDir -Force | Out-Null

        # Create test files
        $script:TestFile = Join-Path $script:TestDir "test-file.txt"
        $script:TestSubDir = Join-Path $script:TestDir "sub-directory"

        "Test file content with function keyword" | Out-File -FilePath $script:TestFile -Encoding UTF8
        New-Item -ItemType Directory -Path $script:TestSubDir -Force | Out-Null
    }

    AfterAll {
        # Clean up test directory
        if (Test-Path $script:TestDir) {
            Remove-Item -Path $script:TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "When checking file existence" {
        It "Should pass when file exists and should exist" {
            { Assert-FileExists -Path $script:TestFile } | Should -Not -Throw
        }

        It "Should pass when file does not exist and should not exist" {
            $nonExistentFile = Join-Path $script:TestDir "nonexistent.txt"

            { Assert-FileExists -Path $nonExistentFile -ShouldNotExist } | Should -Not -Throw
        }

        It "Should throw when file should exist but does not" {
            $nonExistentFile = Join-Path $script:TestDir "missing.txt"

            { Assert-FileExists -Path $nonExistentFile } | Should -Throw -ExpectedMessage "*should exist but was not found*"
        }

        It "Should throw when file should not exist but does" {
            { Assert-FileExists -Path $script:TestFile -ShouldNotExist } | Should -Throw -ExpectedMessage "*should not exist but was found*"
        }
    }

    Context "When checking file vs directory" {
        It "Should pass when path is file and should be file" {
            { Assert-FileExists -Path $script:TestFile -ShouldBeFile } | Should -Not -Throw
        }

        It "Should pass when path is directory and should be directory" {
            { Assert-FileExists -Path $script:TestSubDir -ShouldBeDirectory } | Should -Not -Throw
        }

        It "Should throw when file is expected to be directory" {
            { Assert-FileExists -Path $script:TestFile -ShouldBeDirectory } | Should -Throw -ExpectedMessage "*should be a directory but is a file*"
        }

        It "Should throw when directory is expected to be file" {
            { Assert-FileExists -Path $script:TestSubDir -ShouldBeFile } | Should -Throw -ExpectedMessage "*should be a file but is a directory*"
        }
    }

    Context "When checking file properties" {
        It "Should pass when file meets minimum size requirement" {
            { Assert-FileExists -Path $script:TestFile -MinimumSize 10 } | Should -Not -Throw
        }

        It "Should throw when file is smaller than minimum size" {
            { Assert-FileExists -Path $script:TestFile -MinimumSize 10000 } | Should -Throw -ExpectedMessage "*should be at least 10000 bytes*"
        }

        It "Should pass when file has expected extension" {
            { Assert-FileExists -Path $script:TestFile -ShouldHaveExtension ".txt" } | Should -Not -Throw
        }

        It "Should throw when file has wrong extension" {
            { Assert-FileExists -Path $script:TestFile -ShouldHaveExtension ".ps1" } | Should -Throw -ExpectedMessage "*should have extension '.ps1', but has '.txt'*"
        }

        It "Should pass when file contains expected text" {
            { Assert-FileExists -Path $script:TestFile -ShouldContainText "function" } | Should -Not -Throw
        }

        It "Should throw when file does not contain expected text" {
            { Assert-FileExists -Path $script:TestFile -ShouldContainText "nonexistent" } | Should -Throw -ExpectedMessage "*should contain text 'nonexistent'*"
        }
    }

    Context "When combining multiple assertions" {
        It "Should pass when all conditions are met" {
            { Assert-FileExists -Path $script:TestFile -ShouldBeFile -MinimumSize 10 -ShouldHaveExtension ".txt" -ShouldContainText "Test" } | Should -Not -Throw
        }

        It "Should not check content for directories" {
            { Assert-FileExists -Path $script:TestSubDir -ShouldBeDirectory -ShouldContainText "anything" } | Should -Not -Throw
        }
    }

    Context "When handling edge cases" {
        It "Should handle files that cannot be read" {
            # Create a test file and then try to make it unreadable (this may not work on all systems)
            $unreadableFile = Join-Path $script:TestDir "unreadable.txt"
            "content" | Out-File -FilePath $unreadableFile

            # The assertion should still work for existence checks
            { Assert-FileExists -Path $unreadableFile -ShouldBeFile } | Should -Not -Throw
        }
    }
}