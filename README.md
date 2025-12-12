# Hyper-V API Overlay (Pode + PowerShell)

This project provides a REST API layer on top of Microsoft Hyper-V using PowerShell and Pode.  
It exposes a minimal, consistent, automation-friendly interface to manage virtual machines and virtual switches without relying on GUI tools, RDP, or PowerShell remoting.

The design goal is to treat a Hyper-V host as an infrastructure node that can be managed through HTTP, making it suitable for Terraform, CI/CD pipelines, and cloud-native automation systems.

---

## Purpose

Hyper-V offers powerful virtualization capabilities but lacks a simple, stateless, HTTP-based API.  
This project fills that gap by providing:

- A lightweight REST API with predictable behavior  
- Full JSON request/response support  
- Idempotent create/delete semantics  
- A structured codebase with services, routes, and utilities separated  
- A foundation for a dedicated Terraform provider  

The Hyper-V host becomes manageable like any other infrastructure backend.

---

## Features

- REST API for VMs and virtual switches  
- Idempotent VM and switch creation  
- Safe and predictable deletion behavior  
- JSON error model with optional technical detail  
- Modular PowerShell code structure  
- Zero external dependencies beyond PowerShell, Pode, and Hyper-V  
- OpenAPI 3.0 specification with interactive documentation viewers  

---

## Architecture

```text
hyperv-api/
  ├── src/
  │   ├── server.ps1                 # Pode server entrypoint
  │   ├── config.ps1                 # API configuration (port, bind address)
  │   ├── utils.ps1                  # JSON parsing, error handling, shared helpers
  │   ├── modules/                   # PowerShell modules (business logic)
  │   │   ├── HvoVm/
  │   │   │   ├── HvoVm.psd1         # VM module manifest
  │   │   │   └── HvoVm.psm1         # VM lifecycle logic (New-HvoVm, Remove-HvoVm…)
  │   │   └── HvoSwitch/
  │   │       ├── HvoSwitch.psd1     # Switch module manifest
  │   │       └── HvoSwitch.psm1     # Switch management logic
  │   ├── routes/                    # HTTP route definitions
  │   │   ├── common.ps1             # /health and meta routes
  │   │   ├── vms.ps1                # VM routes (create/list/delete)
  │   │   ├── switches.ps1           # Switch routes (create/list/delete)
  │   │   └── openapi.ps1            # OpenAPI documentation routes
  │   └── scripts/                   # Utility scripts
  │       ├── check-requirement.ps1  # Script to check and install prerequisites (Pode)
  │       └── generate-openapi.ps1  # Script to generate static OpenAPI files
  ├── docs/
  │   ├── api-reference.md           # API reference documentation
  │   ├── openapi.md                 # OpenAPI implementation and usage guide
  │   ├── openapi.json               # OpenAPI specification (JSON)
  │   └── openapi.yaml               # OpenAPI specification (YAML)
  └── README.md
```

The project follows a route/service separation model:

- Routes handle HTTP and JSON
- Services contain Hyper-V logic
- Utilities provide shared helpers
- The server file bootstraps Pode

---

## VM Capabilities

- Create VM with CPU, memory, disk, switch, and optional ISO
- Delete VM and associated VHDs
- List all VMs
- Retrieve a single VM
- Idempotent creation: existing VMs return a 200 instead of re-creating

---

## Switch Capabilities

- Create internal, private, or external virtual switches
- Delete switches
- List all switches
- Retrieve a single switch
- Idempotent creation identical to VM semantics

---

## Running the API

PowerShell 7 is recommended.

From the Hyper-V host:

```powershell
cd hyperv-api/src
pwsh .\server.ps1
```

The server binds to the address and port defined in `config.ps1`.

---

## Example Requests

Health:

```bash
curl http://<host>:8080/health
```

Create a switch:

```bash
curl -X POST http://<host>:8080/switches \
  -H "Content-Type: application/json" \
  -d '{"name":"LAN","type":"Internal"}'
```

Create a VM:

```bash
curl -X POST http://<host>:8080/vms \
  -H "Content-Type: application/json" \
  -d '{
    "name":"vm1",
    "memoryMB":2048,
    "vcpu":2,
    "diskPath":"D:/HyperV",
    "diskGB":20,
    "switchName":"LAN",
    "isoPath":"D:/ISOs/AlmaLinux.iso"
  }'
```

Delete a VM:

```bash
curl -X DELETE http://<host>:8080/vms/vm1
```

---

## Error Model

All error responses follow this structure:

```json
{
  "error": "Message",
  "detail": "Optional technical context"
}
```

This format allows scripts, Terraform, or automation tools to reliably interpret failures.

---

## OpenAPI Documentation

The API includes full OpenAPI 3.0 specification support with interactive documentation viewers.

### Interactive Documentation

When the server is running, you can access:

- **Swagger UI**: `http://<host>:8080/docs/swagger` - Interactive API explorer with request testing
- **ReDoc**: `http://<host>:8080/docs/redoc` - Clean, responsive API documentation viewer

### OpenAPI Endpoints

- **JSON Specification**: `http://<host>:8080/openapi.json` - Get the OpenAPI spec in JSON format
- **YAML Specification**: `http://<host>:8080/openapi.yaml` - Get the OpenAPI spec in YAML format

### Static Documentation Files

Static OpenAPI specification files are available in the `docs/` directory:

- `docs/openapi.json` - JSON format
- `docs/openapi.yaml` - YAML format

These files can be generated using the provided script:

```powershell
cd src/scripts
.\generate-openapi.ps1
```

For detailed information on OpenAPI implementation and usage, see [docs/openapi.md](docs/openapi.md).

---

## Long-Term Goals

- Official Terraform provider  
- ~~VM lifecycle actions (start, stop, reboot)~~
- VM cloning and templating  
- Network adapter attach/detach  
- Volume attach/detach  
- Cloud-init or unattend injection  
- Persistent audit logs  
- Authentication support  
- Multi-host cluster support  

---
