# Amaze MCP Deployment

This folder is a self-contained source distribution for Amaze MCP.

It contains:
- the full codebase-memory MCP source with the Amaze server identity and memory lifecycle tools
- the full zvec source under `third_party/zvec`
- Dockerfile, compose files, and the `docker-mcp` helper

## Build

```sh
cd ~/rocky/amaze-mcp
docker compose build
```

## Run Background Runtime

```sh
cd ~/rocky/amaze-mcp
docker compose up -d
```

The UI proxy is exposed on:

```text
http://127.0.0.1:9749
```

## Run As MCP Stdio Helper

Use the helper from an MCP client config:

```sh
~/rocky/amaze-mcp/docker-mcp
```

Example direct probes:

```sh
~/rocky/amaze-mcp/docker-mcp hook-memory-session-start
~/rocky/amaze-mcp/docker-mcp cli memory_recall '{"project_key":"amaze","query":"startup"}'
```

## Environment

Copy `.env.example` to `.env` if you need to override paths, ports, or user IDs.

Important variables:
- `AMAZE_CACHE_DIR`: cache path inside the mounted home
- `AMAZE_CACHE_HOST_PATH`: host bind mount for the Docker volume
- `AMAZE_HOST_HOME`: host home or workspace root to mount
- `AMAZE_HOME`: path inside the container
- `AMAZE_UI_PORT`: host UI port
- `AMAZE_WORKERS`: indexing worker count

## Current Memory Backend

The MCP memory lifecycle tools are exposed and hook-enforced, but the durable zvec-backed store is
not wired yet. Memory tool responses intentionally report `backend:"manifest-stub"` in this slice.
