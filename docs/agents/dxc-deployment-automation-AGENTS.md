# dxc-deployment-automation — Agent instructions (workspace copy)

**Source repo:** `dxc-deployment-automation`. This copy lives in the workspace so agent/rules/IDE metadata are not tracked in sub-repositories.

---

# Instructions for dxc-deployment-automation PowerShell Repository

## Overview
This repository contains PowerShell modules and automation scripts for managing Optimizely DXC (Digital Experience Cloud) deployments on Azure. The codebase includes internal modules, Azure Automation runbooks, and build/release automation.

## Component-Specific Documentation
For detailed module-specific and area-specific guidance, refer to the AGENTS.md files in the following directories:

- **InternalModules/EpiDeploy/EpiWebApp/AGENTS.md** - Azure Web App management module
- **InternalModules/EpiDeploy/AzureAPI/AGENTS.md** - Azure REST API operations module
- **ScriptRunbooks/AGENTS.md** - Azure Automation runbooks
- **BuildScripts/AGENTS.md** - CI/CD and build automation scripts

These component-specific files contain:
- Module/area overview and purpose
- Detailed implementation patterns
- Common pitfalls and debugging tips
- Testing strategies
- Examples and best practices

## Repository Structure

- **InternalModules/** - PowerShell modules organized by functionality
  - **EpiDeploy/** - Main deployment automation modules (20+ submodules)
  - **CloudFlareModule/** - CloudFlare integration
  - **DataDog/** - DataDog monitoring integration
  - **PaasPortal/** - Portal operations
  - **SendGrid/** - Email services
  - **Turnstile/** - Turnstile integration
  - **UserManagement/** - User management operations

- **ScriptRunbooks/** - Azure Automation runbooks for DXC operations
- **BuildScripts/** - CI/CD scripts for testing, deployment, and release management
- **AutomationAccount Setup/** - Scripts for provisioning automation accounts
- **Tests/** - Integration and end-to-end tests

## File Locations

- **Module structure:**
  - Each module has its own folder under `InternalModules/`
  - Public functions: `*/Public/*.ps1` within each module
  - Private helpers: `*/Private/*.ps1` within each module
  - Module manifest: `*.psm1` (auto-loads Public and Private functions)

## Testing

- **Unit tests:**
  - Located in `*/Tests/Unit/`
  - Named after the function under test (e.g., `Get-EpiWebAppConfig.Unit.Tests.ps1` for `Get-EpiWebAppConfig.ps1`)
  - The module under test is always imported in tests using its `.psm1` file
  - To run all tests, use `BuildScripts/Invoke-PesterTest.ps1` or run Pester in the relevant `Tests/` directory

- **Testing workflow:**
  - When adding or modifying a function, always add or update the corresponding test file
  - Run tests after making changes to ensure everything works as expected
  - Use Pester 5.x for all tests
  - Mock external dependencies (Azure APIs, file system operations)

## Code Style

- **Indentation:** Use 4 spaces for indentation
- **Function naming:**
  - Public functions: `Verb-Noun` (e.g., `Get-EpiWebAppConfig`)
  - Private functions: `VerbNoun` (e.g., `InvokeApiRequest`)
- **Case conventions:**
  - Function names: PascalCase
  - Type accelerators: PascalCase (e.g., `[PSCustomObject]`, `[String]`)
  - Variable names: camelCase (e.g., `$webAppName`, `$resourceGroupName`)
- **Avoid aliases:** Use full cmdlet names (e.g., `Get-ChildItem` instead of `gci`)
- **Bracket placement:** Always place statements after a closing bracket on a new line:
  ```powershell
  if ($true) {
      # ...
  }
  else {
      # ...
  }
  ```

## Documentation

- **Comment-based help:** Add comment-based help for all public functions
- **Function structure:**
  - Use `[CmdletBinding()]` and `param()` blocks for all functions
  - Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, and `.EXAMPLE` sections
  - Document all parameters with descriptions

## Messaging and Logging

- **Standard messaging:**
  - `Write-Verbose` - Operational details
  - `Write-Warning` - Non-critical warnings
  - `Write-Error` - Error messages

- **Structured logging in runbooks:**
  - Use `Write-EPiLogLine` for structured logging, especially in runbooks and automation scripts
  - Example:
    ```powershell
    $loggingActivity = "Set-DXCFailoverActivationAlert"
    Write-EPiLogline -Activity $loggingActivity -LogLine "Connecting to Azure ..."
    Write-EPiLogline -Activity $loggingActivity -LogType ERROR -LogLine "Failed to remove action group. The error was $($_.Exception.Message)." -Terminate
    ```

## Error Handling

- **Use try/catch:** For error handling when interacting with external systems
- **Retry logic:** When calling external APIs or services, for operations that can be safely retried, implement retry logic:
  ```powershell
  $container = Invoke-EpiCommandWithRetry -ScriptBlock {
      New-AzStorageContainer -Context $storageContainerInfo.StorageContext -Name $ContainerName -Permission 'Off' -ErrorAction 'Stop'
  } -FailureMessage "Failed to create new container called '$ContainerName' in storage account '$StorageAccountName'"
  ```

## API Calls

- **Helper functions:** Use helper functions in the module's `Private/` folder
  - `InvokeApiRequest` - Execute API requests
  - `GetApiRequestSplattingHash` - Build request parameters
  - See `InternalModules/EpiDeploy/AzureAPI/AGENTS.md` for detailed API patterns

## Example Reference Files

- **Cmdlet:** `InternalModules/EpiDeploy/EpiWebApp/Public/Get-EpiWebAppConfig.ps1`
- **Test:** `InternalModules/EpiDeploy/EpiWebApp/Tests/Unit/Get-EpiWebAppConfig.Unit.Tests.ps1`
- These provide a good reference for function structure, parameter handling, and test mocking

## Updating Documentation

When you discover new information that would be helpful for future development work:

- **Update existing AGENTS.md files** when you learn implementation details, debugging insights, or architectural patterns specific to that component
- **Create new AGENTS.md files** in relevant module directories when working with areas that don't yet have documentation
- **Add valuable insights** such as:
  - Common pitfalls and solutions
  - Debugging techniques and diagnostic commands
  - Dependency relationships between modules
  - Implementation patterns and best practices
  - Performance considerations
  - Security considerations

This helps build a comprehensive knowledge base for the codebase over time.
