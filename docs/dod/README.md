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

## API Scenario Tests

En plus des tests unitaires, un scénario de test complet exerce l’API contre un serveur déjà démarré (localhost). Il valide l’enchaînement des endpoints (health, documentation, switches, VMs) et génère un rapport.

### Prérequis

- Le serveur API doit être démarré (voir [End-User Testing](#end-user-testing) pour le lancer).
- Hyper-V disponible sur la machine où tourne le serveur.
- PowerShell 7 (requis pour les appels HTTP du script).

### Exécution

```powershell
.\tests\run-api-tests.ps1
```

Options possibles :

```powershell
.\tests\run-api-tests.ps1 -BaseUrl 'http://localhost:8080' -VmDiskPath 'C:\ProgramData\hvo-api-test'
```

Le script demande une confirmation que le serveur est démarré, vérifie `GET /health`, puis enchaîne :

1. **Phase 1** : health, OpenAPI (documentation).
2. **Phase 2** : CRUD des switches (liste, création, lecture, mise à jour, suppression).
3. **Phase 3** : scénario VM (liste, création, lecture, démarrage, arrêt, adaptateurs réseau, mise à jour, suppression).

Les ressources créées utilisent le préfixe `hvo-test-{type}-<YYYYMMDDHHmm>` et sont supprimées en fin de run lorsque les tests réussissent.

### Rapport et échecs

Un rapport est généré dans `tests/reports/api-test-report-<YYYYMMDDHHmm>.txt`. En cas d’échec, le rapport contient :

- La liste des tests en échec (endpoint, code HTTP, réponse).
- Une section **Remise en condition initiale Hyper-V** avec les commandes PowerShell pour supprimer les ressources de test restantes (VMs et switches dont le nom commence par `hvo-test-`).

### Quand les exécuter

- Après une modification des routes ou du comportement de l’API (switches, VMs, health, documentation).
- Avant une release ou une validation de feature, en complément des tests unitaires et des tests manuels via Swagger.

## OpenAPI Documentation

Static OpenAPI specification files must be generated and kept up to date in the `docs/` directory.

### Generation Script

The OpenAPI specification can be automatically generated using the provided script :

```powershell
src/scripts/generate-openapi.ps1
```

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
- **API scenario tests** : `.\tests\run-api-tests.ps1` a été exécuté avec succès (recommandé après toute modification des routes ou du comportement de l’API)
