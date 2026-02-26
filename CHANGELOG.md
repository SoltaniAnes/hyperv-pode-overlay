# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Breaking change — Resource identification by Id (GUID)

- **Resources identified by Id:** All list and detail responses now include an **id** field (GUID). Targeting resources (detail, update, delete, actions) is done only via **:id** in the path.
- **Name-based routes removed:** Routes using **:name** to target a VM or switch have been removed (e.g. `GET /vms/:name`, `PUT /vms/:name`, `DELETE /vms/:name`, `POST /vms/:name/start`, etc.).
- **Discovery by name:** Use **GET /vms/by-name/:name** and **GET /switches/by-name/:name** to look up resources by name. The response is always an array (200), possibly empty.
- **Creation (POST /vms, POST /switches):** Each call creates a **new** resource and returns **201 Created** with **id**. There is no longer a 200 “already exists” response; names may be duplicated; the stable identifier is **id**.
- **Network adapters:** Adapter lists include **id** per adapter. Removing an adapter is done via **DELETE /vms/:id/network-adapters/:adapterId**.

See [docs/api-reference.md](docs/api-reference.md) for the full endpoint reference.
