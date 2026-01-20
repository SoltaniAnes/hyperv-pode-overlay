# Definition of Done

This document outlines the criteria that must be met for a feature or change to be considered complete and ready for production.

## Coding Guidelines

All code must follow the project's coding guidelines and standards as defined in the project documentation.

Pre-commit hooks must have passed on the code. Install the hooks using:

```bash
pre-commit install
```

## Tools Installation

Before running tests, the following tools must be installed.

### Pester

Pester is the PowerShell testing framework used for unit tests and code coverage.

**Installation:**

```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck
```

**Verify installation:**

```powershell
Get-Module -Name Pester -ListAvailable
```

Version 5.0 or higher is required.

### Pode

Pode is the PowerShell web framework used by the API server.

**Installation:**

```powershell
Install-Module -Name Pode -Force
```

**Verify installation:**

```powershell
Get-Module -Name Pode -ListAvailable
```

### Pre-commit

Pre-commit is a tool for managing Git pre-commit hooks.

**Installation:**

```bash
pip install pre-commit
```

**Configure hooks:**

```bash
pre-commit install
```

## Unit Testing

### Automated Unit Tests

Automated unit tests must be implemented with code coverage reporting.

#### Code Coverage Generation

Code coverage reports are generated using the test execution script.

**Usage:**

```powershell
.\tests\run-tests.ps1 -All -Coverage
```

This command will:

- Execute all unit tests
- Generate a coverage report
- Save the report to `coverage.xml`

#### Coverage Analysis

Analyze code coverage by component using the coverage analysis script:

```powershell
.\tests\analyze-coverage.ps1
```

This script provides a breakdown of coverage by items, helping identify areas that need additional test coverage.

## OpenAPI Documentation

Static OpenAPI specification files must be generated and kept up to date in the `docs/` directory.

### Generation Script

The OpenAPI specification can be automatically generated using the provided script located at `src/scripts/generate-openapi.ps1`.

**What the script does:**

1. Checks if the server is running
2. Starts a temporary server if needed
3. Retrieves the OpenAPI specification from the running server
4. Saves both JSON and YAML formats to `docs/`

**Usage:**

```powershell
.\src\scripts\generate-openapi.ps1
```

The generated files will be saved in the `docs/` directory for version control and documentation purposes.

## End-User Testing

Before considering a feature complete, end-user tests must be performed manually to validate the expected behavior.

### Starting the Server

The server must be started locally to allow manual testing.

**Prerequisites:**

- PowerShell with Hyper-V modules installed
- Administrator privileges to interact with Hyper-V

**Start:**

```powershell
.\src\server.ps1
```

The server starts by default on `http://127.0.0.1:8080`.

### Testing Procedure

1. **Start the server** using the command above
2. **Access the Swagger interface**: open `http://127.0.0.1:8080/docs/swagger` in a browser
3. **Test the developed feature**: use the Swagger interface to execute the endpoints affected by your changes
4. **Verify results**: validate that the results returned by the API match expectations
5. **Confirm with Hyper-V**: use the Hyper-V administration interface or PowerShell commands to verify that actions were correctly applied

### Verification Checklist

- HTTP return codes are correct (200, 201, 400, 404, etc.)
- Returned data conforms to the OpenAPI schema
- Changes are properly reflected in Hyper-V
- Error cases are handled correctly
