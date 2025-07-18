# Contributing Guidelines

Thank you for your interest in contributing to our project. Whether it's a bug report, new feature, correction, or additional
documentation, we greatly value feedback and contributions from our community.

Please read through this document before submitting any issues or pull requests to ensure we have all the necessary
information to effectively respond to your bug report or contribution.

## Reporting Bugs/Feature Requests

We welcome you to use the GitHub issue tracker to report bugs or suggest features.

When filing an issue, please check existing open, or recently closed, issues to make sure somebody else hasn't already
reported the issue. Please try to include as much information as you can. Details like these are incredibly useful:

*   A reproducible test case or series of steps
*   The version of our code being used
*   Any modifications you've made relevant to the bug
*   Anything unusual about your environment or deployment

## Contributing via Pull Requests

Contributions via pull requests are much appreciated. Before sending us a pull request, please ensure that:

1.  You are working against the latest source on the *main* branch.
2.  You check existing open, and recently merged, pull requests to make sure someone else hasn't addressed the problem already.
3.  You open an issue to discuss any significant work - we would hate for your time to be wasted.

### Complete Contribution Workflow

#### Step 1: Fork and Setup

1.  **Fork the repository** on GitHub
2.  **Clone your fork** locally:

   ```bash
   git clone https://github.com/YOUR-USERNAME/aws-lambda-powershell-runtime.git
   cd aws-lambda-powershell-runtime
   ```

3.  **Enable GitHub Actions** in your fork:
   *   Go to the "Actions" tab in your fork
   *   Click "I understand my workflows, go ahead and enable them"

#### Step 2: Create Your Branch

Use our standard branch naming conventions to enable automated testing:

```bash
# For new features
git checkout -b feature/your-feature-name

# For bug fixes
git checkout -b fix/issue-description

# For maintenance tasks
git checkout -b chore/maintenance-task
```

#### Step 3: Make Your Changes

*   Focus on the specific change you are contributing
*   Avoid reformatting unrelated code
*   Follow existing code style and conventions

#### Step 4: Test Your Changes

We provide two testing options:

##### Option A: Automated Testing in Your Fork (Recommended)

Push your changes to test automatically:

```bash
git add .
git commit -m "Add new feature with tests"
git push origin feature/your-feature-name
```

This triggers the same comprehensive test suite as the main repository:
*   ✅ **Build Tests**: Validates PowerShell runtime builds correctly
*   ✅ **Unit Tests**: Runs all tests with coverage reporting
*   ✅ **Security Analysis**: PSScriptAnalyzer scans for issues
*   ✅ **Dependency Review**: Checks for vulnerable dependencies

View results in your fork's Actions tab, fix any issues, and push again.

##### Option B: Local Testing

Run tests locally before pushing:

```bash
cd powershell-runtime

# Run build tests
pwsh -NoProfile -Command "& './tests/Invoke-Tests.ps1' -TestType Build"

# Run unit tests
pwsh -NoProfile -Command "& './tests/Invoke-Tests.ps1' -TestType Unit"

# Run security analysis matching CI pipeline
# (See .github/workflows/test.yml for exact configuration)
Invoke-ScriptAnalyzer -Path ./source -Recurse -ExcludeRule 'PSAvoidUsingWriteHost','PSUseSingularNouns'
```

#### Step 5: Submit Your Pull Request

1.  **Ensure tests pass** in your fork
2.  **Create a pull request** from your branch to our main branch
3.  **Fill out the PR template** with details about your changes
4.  **Stay engaged** in the review process and address feedback

### Understanding Test Results

#### When Tests Pass ✅

```
✅ Build Tests: All build tests passed
✅ Unit Tests: 281+ tests passed, 87%+ coverage
✅ Security Analysis: No critical issues found
✅ Dependency Review: No vulnerable dependencies
```

#### When Tests Fail ❌

```
❌ Build Tests: 2 tests failed
❌ Unit Tests: 5 tests failed, coverage below threshold
⚠️  Security Analysis: 3 style issues found
```

Click on failed workflow runs for detailed error messages, security annotations, and coverage reports.

### Troubleshooting

**Actions not running?**
*   Ensure Actions are enabled in your fork
*   Use proper branch naming (`feature/*`, `fix/*`, `chore/*`)
*   Don't push directly to `main` branch

**Tests fail in GitHub but pass locally?**
*   Check workflow logs for specific errors
*   Verify PowerShell version compatibility
*   Ensure all dependencies are properly specified

**Need help?**
*   Check existing issues for similar problems
*   Ask questions in GitHub issues with specific error messages
*   Reference workflow logs when requesting assistance

GitHub provides additional documentation on [forking a repository](https://help.github.com/articles/fork-a-repo/) and [creating a pull request](https://help.github.com/articles/creating-a-pull-request/).

## Finding contributions to work on

Looking at the existing issues is a great way to find something to contribute on. As our projects, by default, use the default GitHub issue labels (enhancement/bug/duplicate/help wanted/invalid/question/wontfix), looking at any 'help wanted' issues is a great place to start.

## Code of Conduct

This project has adopted the [Amazon Open Source Code of Conduct](https://aws.github.io/code-of-conduct).
For more information see the [Code of Conduct FAQ](https://aws.github.io/code-of-conduct-faq) or contact
<opensource-codeofconduct@amazon.com> with any additional questions or comments.

## Security issue notifications

If you discover a potential security issue in this project we ask that you notify AWS/Amazon Security via our [vulnerability reporting page](http://aws.amazon.com/security/vulnerability-reporting/). Please do **not** create a public github issue.

## Licensing

See the [LICENSE](LICENSE) file for our project's licensing. We will ask you to confirm the licensing of your contribution.
