# Hyper-V API Overlay — REST Reference

Base URL:
http://<host>:8080

This API exposes a Terraform-compatible interface for managing:
- Hyper-V Virtual Machines
- Hyper-V Virtual Switches

All responses are JSON.

**Identification by Id:** Resources (VMs, switches, network adapters) are identified by a stable **Id** (GUID). All list and detail responses include an `Id` field. Use **GET /vms/:id** or **GET /switches/:id** to target a resource by Id. Use **GET /vms/by-name/:name** or **GET /switches/by-name/:name** to discover resources by name (returns an array, possibly empty). The path parameter **:name** for targeting has been removed; use **:id** for all operations (get, update, delete, actions).

---------------------------------------
VM ENDPOINTS
---------------------------------------

GET /vms
List all VMs.

Response 200:
[
  {
    "Id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "Name": "vm1",
    "State": "Running",
    "CPUUsage": 1,
    "MemoryAssigned": 2147483648,
    "Uptime": "00:05:12"
  }
]

---------------------------------------

GET /vms/:id
Get details about a single VM by its GUID.

Response 200:
{
  "Id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
  "Name": "vm1",
  "State": "Off",
  "CPUUsage": 0,
  "MemoryAssigned": 0,
  "Uptime": "00:00:00"
}

Response 404:
{ "error": "VM not found" }

---------------------------------------

GET /vms/by-name/:name
Get all VMs whose name matches. Returns an array (0, 1 or more elements). Always 200.

Response 200:
[
  {
    "Id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "Name": "vm1",
    "State": "Running",
    "CPUUsage": 0,
    "MemoryAssigned": 2147483648,
    "Uptime": "00:01:00"
  }
]

---------------------------------------

POST /vms
Create a virtual machine. Each call creates a **new** resource and returns 201 with **id**. Names may be duplicated; the truth is in the Id.

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

201 Created
{ "created": "vm1", "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }

400 Bad Request
{ "error": "Invalid JSON" }

500 Internal Server Error
{ "error": "Failed to create VM", "detail": "Hyper-V message..." }

---------------------------------------

PUT /vms/:id
Update a VM (memory, vCPU, switch, ISO). VM must be stopped.

Response 200 (updated):
{ "updated": true, "name": "vm1", "id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee" }

Response 200 (unchanged):
{ "unchanged": true, "name": "vm1", "id": "..." }

Response 404:
{ "error": "VM not found" }

Response 409:
{ "error": "VM must be Off to update", "State": "Running" }

---------------------------------------

DELETE /vms/:id
Delete a VM by Id.

Response 200:
{ "deleted": "<id>", "id": "<id>" }

Response 404:
{ "error": "VM not found" }

---------------------------------------

POST /vms/:id/start
Start a virtual machine by Id.

Response 200:
{ "started": "vm1" }

Response 404:
{ "error": "VM not found" }

---------------------------------------

POST /vms/:id/stop
Stop a virtual machine by Id.

The `force` parameter can be provided as query `?force=true` or in the request body `{ "force": true }`. When `force` is false or omitted, the shutdown integration service must be available and enabled; otherwise use force or a 422 is returned.

Response 200:
{ "stopped": "vm1" }

Response 404:
{ "error": "VM not found" }

Response 409:
{ "error": "VM is already stopped" }

Response 422:
{ "error": "Shutdown integration service not available or not enabled", "detail": "..." }

---------------------------------------

POST /vms/:id/restart
Restart a virtual machine by Id. Same `force` behavior as stop.

Response 200:
{ "restarted": "vm1" }

Response 404:
{ "error": "VM not found" }

---------------------------------------

POST /vms/:id/suspend
Suspend (pause) a virtual machine by Id.

Response 200:
{ "suspended": "vm1" }

Response 404:
{ "error": "VM not found" }

Response 409:
{ "error": "VM is already suspended" }

---------------------------------------

POST /vms/:id/resume
Resume a suspended virtual machine by Id.

Response 200:
{ "resumed": "vm1" }

Response 404:
{ "error": "VM not found" }

Response 409:
{ "error": "VM is already running" }

---------------------------------------

GET /vms/:id/network-adapters
List network adapters of a VM by Id. Each adapter includes an **Id** (GUID or InstanceId).

Response 200:
[
  {
    "Id": "ffffffff-0000-0000-0000-000000000001",
    "Name": "Network Adapter",
    "SwitchName": "LAN",
    "Type": "Synthetic",
    "MacAddress": "00155D012345",
    "Status": "Ok"
  }
]

Response 404:
{ "error": "VM not found" }

---------------------------------------

POST /vms/:id/network-adapters
Add a network adapter to a VM by Id.

Request body:
{ "switchName": "LAN" }

Response 201:
{ "created": "Network Adapter", "id": "<adapter-guid>" }

Response 404:
{ "error": "VM not found" }

---------------------------------------

DELETE /vms/:id/network-adapters/:adapterId
Remove a network adapter from a VM by VM Id and adapter Id.

Response 200:
{ "deleted": "<adapterId>", "id": "<adapterId>" }

Response 404:
{ "error": "VM or network adapter not found" }

---------------------------------------
SWITCH ENDPOINTS
---------------------------------------

GET /switches
List all virtual switches.

Response 200:
[
  { "Id": "cccccccc-dddd-eeee-ffff-000000000001", "Name": "LAN", "SwitchType": "Internal", "Notes": "" }
]

---------------------------------------

GET /switches/:id
Get a specific virtual switch by Id.

Response 200:
{
  "Id": "cccccccc-dddd-eeee-ffff-000000000001",
  "Name": "LAN",
  "SwitchType": "Internal",
  "Notes": ""
}

Response 404:
{ "error": "Switch not found" }

---------------------------------------

GET /switches/by-name/:name
Get all switches whose name matches. Returns an array. Always 200.

Response 200:
[
  { "Id": "...", "Name": "LAN", "SwitchType": "Internal", "Notes": "" }
]

---------------------------------------

POST /switches
Create a virtual switch. Each call creates a **new** resource and returns 201 with **id**.

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

Response 201:
{ "created": "LAN", "id": "cccccccc-dddd-eeee-ffff-000000000001" }

Response 400:
{ "error": "Invalid JSON" }

Response 500:
{ "error": "Failed to create switch", "detail": "Hyper-V message" }

---------------------------------------

PUT /switches/:id
Update an existing virtual switch by Id (notes only).

Request body:
{ "notes": "Terraform-managed switch" }

Response 200:
{ "updated": "LAN", "id": "..." }

Response 404:
{ "error": "Switch not found" }

---------------------------------------

DELETE /switches/:id
Delete a virtual switch by Id.

Response 200:
{ "deleted": "<id>", "id": "<id>" }

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

- DELETE /vms/:id, DELETE /switches/:id: missing resource → 404.
- POST /vms/:id/start, POST /vms/:id/stop, etc.: already in target state → 200 with appropriate flag (e.g. AlreadyRunning, AlreadyStopped).
- POST /vms and POST /switches: **no longer idempotent by name**; each call creates a new resource and returns 201 with a new **id**. Use **Id** for all subsequent operations.

---------------------------------------

This API is suitable for automated infrastructure provisioning. Use **Id** (GUID) for stable identification; use **by-name** only for discovery.
