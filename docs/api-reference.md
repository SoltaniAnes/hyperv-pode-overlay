# Hyper-V API Overlay — REST Reference

Base URL:
http://<host>:8080

This API exposes a clean, idempotent, Terraform-compatible interface for managing:
- Hyper-V Virtual Machines
- Hyper-V Virtual Switches

All responses are JSON.

---------------------------------------
VM ENDPOINTS
---------------------------------------

GET /vms
List all VMs.

Response 200:
[
  {
    "Name": "vm1",
    "State": "Running",
    "CPUUsage": 1,
    "MemoryAssigned": 2147483648,
    "Uptime": "00:05:12"
  }
]

---------------------------------------

GET /vms/:name
Get details about a single VM.

Response 200:
{
  "Name": "vm1",
  "State": "Off",
  "CPUUsage": 0,
  "MemoryAssigned": 0,
  "Uptime": "00:00:00"
}

Response 404:
{ "error": "VM not found" }

---------------------------------------

POST /vms
Create a virtual machine.

This operation is **idempotent**.

Request body:
{
  "name": "vm1",
  "memoryMB": 2048,
  "vcpu": 2,
  "diskPath": "D:/HyperV",
  "diskGB": 20,
  "switchName": "LAN",
  "isoPath": "D:/ISOs/AlmaLinux.iso"
}

Responses:

If the VM was created:
201 Created
{ "created": "vm1" }

If the VM already exists:
200 OK
{ "exists": "vm1" }

If JSON is invalid:
400 Bad Request
{ "error": "Invalid JSON" }

If Hyper-V operation fails:
500 Internal Server Error
{ "error": "Failed to create VM", "detail": "Hyper-V message..." }

---------------------------------------

DELETE /vms/:name
Delete a VM.  
Operation is **idempotent**.

Response 200:
{ "deleted": "vm1" }

Response 404:
{ "error": "VM not found" }

Response 500:
{
  "error": "Failed to delete VM",
  "detail": "Hyper-V exception message"
}

---------------------------------------

POST /vms/:name/start
Start a virtual machine.

This operation is **idempotent**.

Response 200:
{ "started": "vm1" }

Response 404:
{ "error": "VM not found" }

Response 500:
{
  "error": "Failed to start VM",
  "detail": "Hyper-V exception message"
}

---------------------------------------

POST /vms/:name/stop
Stop a virtual machine.

This operation is **idempotent**.

The `force` parameter can be provided either as a query parameter or in the request body:
- Query parameter: `POST /vms/:name/stop?force=true`
- Request body: `{ "force": true }`

If `force` is not provided or is `false`, the VM will be gracefully shut down.
If `force` is `true`, the VM will be forcefully stopped.

**Note:** When `force` is `false` or not provided, the shutdown integration service must be available and enabled on the VM. If it is not, a 422 error will be returned.

Response 200:
{ "stopped": "vm1" }

Response 404:
{ "error": "VM not found" }

Response 409:
{ "error": "VM is already stopped" }

Response 422:
{
  "error": "Shutdown integration service not available or not enabled",
  "detail": "Le service d'intégration d'arrêt (Shutdown) n'est pas disponible pour la VM 'vm1'. Utilisez le paramètre 'force' pour un arrêt forcé."
}

Response 500:
{
  "error": "Failed to stop VM",
  "detail": "Hyper-V exception message"
}

---------------------------------------

POST /vms/:name/restart
Restart a virtual machine.

This operation is **idempotent**.

The `force` parameter can be provided either as a query parameter or in the request body:
- Query parameter: `POST /vms/:name/restart?force=true`
- Request body: `{ "force": true }`

If `force` is not provided or is `false`, the VM will be gracefully restarted.
If `force` is `true`, the VM will be forcefully restarted.

**Note:** When `force` is `false` or not provided, the shutdown integration service must be available and enabled on the VM. If it is not, a 422 error will be returned.

If the VM is already stopped, it will be started (idempotent behavior).

Response 200:
{ "restarted": "vm1" }

Response 404:
{ "error": "VM not found" }

Response 422:
{
  "error": "Shutdown integration service not available or not enabled",
  "detail": "Le service d'intégration d'arrêt (Shutdown) n'est pas disponible pour la VM 'vm1'. Utilisez le paramètre 'force' pour un redémarrage forcé."
}

Response 500:
{
  "error": "Failed to restart VM",
  "detail": "Hyper-V exception message"
}

---------------------------------------
SWITCH ENDPOINTS
---------------------------------------

GET /switches
List all virtual switches.

Response 200:
[
  { "Name": "LAN", "SwitchType": "Internal", "Notes": "" }
]

---------------------------------------

GET /switches/:name
Get a specific virtual switch.

Response 200:
{
  "Name": "LAN",
  "SwitchType": "Internal",
  "Notes": ""
}

Response 404:
{ "error": "Switch not found" }

---------------------------------------

POST /switches
Create a virtual switch.  
Operation is **idempotent**.

Valid request bodies:

Internal:
{ "name": "LAN", "type": "Internal" }

Private:
{ "name": "BACKEND", "type": "Private" }

External:
{
  "name": "WAN",
  "type": "External",
  "netAdapterName": "Ethernet"
}

Responses:

If the switch was created:
201 Created
{ "created": "LAN" }

If it already exists:
200 OK
{ "exists": "LAN" }

If JSON is invalid:
400 Bad Request
{ "error": "Invalid JSON" }

If Hyper-V fails:
500 Internal Server Error
{ "error": "Failed to create switch", "detail": "Hyper-V message" }

---------------------------------------

PUT /switches/:name
Update an existing virtual switch.

Only the "notes" field can be updated.
All other properties (name, type, netAdapterName) are immutable in Hyper-V and require switch recreation.
Operation is idempotent.

Valid request body:
{
"notes": "Terraform-managed switch"
}

If no updatable fields are provided, the request is accepted but no changes are applied.

Responses:

200 OK — Switch updated
{
"updated": "LAN",
"notes": "Terraform-managed switch"
}

200 OK — No change (notes already identical)
{
"updated": "LAN",
"notes": "Terraform-managed switch"
}

404 Not Found
{
"error": "Switch not found"
}

400 Bad Request
{
"error": "Invalid JSON"
}

500 Internal Server Error
{
"error": "Failed to update switch",
"detail": "Hyper-V message"
}

Notes:

Only "notes" is updatable because Hyper-V does not support modifying type or network adapter after switch creation.

Immutable fields should be handled by clients (e.g., Terraform marks them with ForceNew).

---------------------------------------

DELETE /switches/:name
Delete a virtual switch.  
Operation is **idempotent**.

Response 200:
{ "deleted": "LAN" }

Response 404:
{ "error": "Switch not found" }

---------------------------------------
ERROR MODEL
---------------------------------------

All errors follow the same structure:

{
  "error": "Human-readable message",
  "detail": "Optional technical message"
}

---------------------------------------
IDEMPOTENCY RULES
---------------------------------------

POST /vms        = idempotent (existing VM → 200 OK)
DELETE /vms      = idempotent (missing VM → 404)
POST /vms/:name/start = idempotent (already running VM → 200 OK)
POST /vms/:name/stop = idempotent (already running VM → 200 OK)
POST /vms/:name/restart = idempotent (stopped VM → starts, running VM → restarts)

POST /switches   = idempotent (existing switch → 200 OK)
DELETE /switches = idempotent (missing switch → 404)

---------------------------------------

This API is Terraform-provider-safe and suitable for automated infrastructure provisioning.
