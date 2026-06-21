# Amaze MCP

Amaze MCP is a local, Docker-first MCP runtime that combines codebase intelligence
with an agent memory protocol.

It exposes the existing codebase graph tools unchanged and adds memory lifecycle
tools for agent workflows:

- `memory_recall`
- `memory_search`
- `memory_candidate`
- `memory_validate`
- `memory_commit`
- `memory_feedback`
- `memory_rebuild`
- `memory_audit`

The code graph engine provides the semantic/indexing layer. zvec source is
included under `third_party/zvec` for the native durable memory backend path, but
this first packaged slice intentionally returns `backend:"manifest-stub"` for
memory tools until the zvec adapter is wired.

## What Is Included

- Full Amaze MCP source.
- Full zvec source under `third_party/zvec`.
- Docker runtime files:
  - `Dockerfile`
  - `docker-compose.yml`
  - `docker-compose.runtime.yml`
  - `docker-mcp`
- Agent hook commands:
  - `hook-memory-session-start`
  - `hook-memory-before-tool`
  - `hook-memory-after-tool`
  - `hook-memory-finalize`
- Agent instruction protocol in install-generated `AGENTS.md` sections.

## Requirements

- Docker Desktop or Docker Engine with Compose v2.
- Git.
- macOS or Linux host recommended.

No OpenAI, Anthropic, Gemini, or embedding API key is required for the MCP server
itself. Your LLM client may require its own model/API setup.

## Quick Start

```sh
git clone https://github.com/steve-8000/amaze-mcp.git
cd amaze-mcp
mkdir -p ~/.cache/amaze-mcp
docker compose build
docker compose up -d
```

The graph UI proxy listens on:

```text
http://127.0.0.1:9749
```

Smoke test:

```sh
./docker-mcp hook-memory-session-start
./docker-mcp cli memory_recall '{"project_key":"amaze","query":"startup"}'
```

Expected memory output includes:

```json
{"tool":"memory_recall","backend":"manifest-stub","freshness":"unknown"}
```

## Docker Helper

Use `docker-mcp` as the MCP command for LLM clients:

```sh
/absolute/path/to/amaze-mcp/docker-mcp
```

The helper starts the Docker Compose service if needed, then forwards stdio into
the containerized MCP server.

Useful environment overrides:

```sh
cp .env.example .env
```

Important variables:

- `AMAZE_HOST_HOME`: host path mounted into the container.
- `AMAZE_HOME`: same path inside the container.
- `AMAZE_CACHE_DIR`: cache path used by the MCP runtime.
- `AMAZE_CACHE_HOST_PATH`: host bind mount for the Docker cache volume.
- `AMAZE_UI_PORT`: host UI port, default `9749`.
- `AMAZE_WORKERS`: indexing worker count.

## MCP Tools

Codebase tools keep their existing names:

- `index_repository`
- `search_graph`
- `query_graph`
- `trace_path`
- `get_code_snippet`
- `get_graph_schema`
- `get_architecture`
- `search_code`
- `list_projects`
- `delete_project`
- `index_status`
- `detect_changes`
- `manage_adr`
- `ingest_traces`

Memory lifecycle tools:

- `memory_recall`: recall fresh validated memory for the current user/project/task.
- `memory_search`: search durable memory with freshness-aware ranking.
- `memory_candidate`: stage a memory item before validation.
- `memory_validate`: check candidates for source/freshness/conflicts.
- `memory_commit`: promote validated candidates.
- `memory_feedback`: report used/ignored/stale/wrong recall outcomes.
- `memory_rebuild`: rebuild memory manifests/vectors.
- `memory_audit`: inspect stale/conflicting/rebuild-needed memory state.

## Agent Memory Protocol

Agents should follow this protocol:

1. Start every task by reading injected hook context and calling `memory_recall`.
2. Treat stale memory as untrusted until verified from source.
3. Use codebase tools such as `search_graph`, `trace_path`, and
   `get_code_snippet` to verify project facts.
4. Save durable preferences, decisions, and verified learnings with
   `memory_candidate`.
5. Promote only through `memory_validate` followed by `memory_commit`.
6. Use `memory_feedback` when recall results are stale, wrong, ignored, or useful.

## LLM Client Installation

All examples below assume the repository is cloned to:

```text
/Users/steve/rocky/amaze-mcp
```

Use your actual absolute path if different.

### Claude Code

Add an MCP server entry pointing to the Docker helper.

Example `~/.claude/.mcp.json`:

```json
{
  "mcpServers": {
    "amaze": {
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
    }
  }
}
```

Recommended project or user instruction file:

```md
# Amaze Memory Protocol

Use the `amaze` MCP server before code exploration. Start each task with
`memory_recall`, verify stale facts with `search_graph`, `trace_path`, or
`get_code_snippet`, then store verified durable learnings through
`memory_candidate`, `memory_validate`, and `memory_commit`.
```

Optional hook command for session-start capable setups:

```sh
/Users/steve/rocky/amaze-mcp/docker-mcp hook-memory-session-start
```

### Codex CLI

Add this to `~/.codex/config.toml`:

```toml
[mcp_servers.amaze]
command = "/Users/steve/rocky/amaze-mcp/docker-mcp"
```

Recommended `~/.codex/AGENTS.md`:

```md
# Amaze

Use MCP server `amaze` for codebase discovery and agent memory.

- Call `memory_recall` before planning.
- Use `search_graph`, `trace_path`, and `get_code_snippet` before grep/read for code facts.
- Store durable verified facts with `memory_candidate`, `memory_validate`, and `memory_commit`.
- Treat stale memory as untrusted until revalidated.
```

### Cursor

Create or edit `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "amaze": {
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
    }
  }
}
```

Restart Cursor after editing.

### Windsurf

Windsurf uses the same MCP shape as Cursor in many setups. Add:

```json
{
  "mcpServers": {
    "amaze": {
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
    }
  }
}
```

Place it in the Windsurf MCP config location used by your installation, then
restart Windsurf.

### VS Code MCP

Example `~/Library/Application Support/Code/User/mcp.json` on macOS:

```json
{
  "servers": {
    "amaze": {
      "type": "stdio",
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
    }
  }
}
```

Restart VS Code after editing.

### Zed

Example Zed `settings.json`:

```json
{
  "context_servers": {
    "amaze": {
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp",
      "args": []
    }
  }
}
```

### Gemini CLI

Example MCP config:

```json
{
  "mcpServers": {
    "amaze": {
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
    }
  }
}
```

Recommended Gemini instruction:

```md
Use the `amaze` MCP server for codebase and memory work. Call `memory_recall`
first, verify stale facts through code graph tools, and commit only validated
memory.
```

### OpenCode

Example `~/.config/opencode/opencode.json`:

```json
{
  "mcp": {
    "amaze": {
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
    }
  }
}
```

Recommended `~/.config/opencode/AGENTS.md`:

```md
Use MCP server `amaze` before code exploration. Prefer `search_graph`,
`trace_path`, and `get_code_snippet` for code facts. Use `memory_recall` at task
start and store verified durable facts through the memory lifecycle tools.
```

### Aider

If your Aider setup supports MCP servers, configure a stdio server:

```json
{
  "mcpServers": {
    "amaze": {
      "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
    }
  }
}
```

Add this to your project instructions:

```md
Use Amaze MCP for code search and durable memory. Recall memory first, verify
facts from source, and commit only validated memory.
```

### Generic MCP Client

Use this stdio server definition:

```json
{
  "name": "amaze",
  "transport": {
    "type": "stdio",
    "command": "/Users/steve/rocky/amaze-mcp/docker-mcp"
  }
}
```

## Manual MCP Probe

```sh
printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
  | ./docker-mcp
```

Expected:

- `serverInfo.name` is `amaze`.
- `tools/list` contains `search_graph`.
- `tools/list` contains `memory_recall`.

## Index A Project

```sh
./docker-mcp cli index_repository '{"repo_path":"/Users/steve/path/to/project","mode":"full"}'
```

Then query:

```sh
./docker-mcp cli search_graph '{"project":"project-name","query":"authentication handler","limit":10}'
```

## Rebuild From Source Without Docker

```sh
make -f Makefile.cbm cbm LIBGIT2_LIBS= LIBGIT2_FLAGS=
./build/c/codebase-memory-mcp --version
```

The empty `LIBGIT2_*` variables avoid Homebrew libgit2 header mismatches on some
macOS machines.

## Current Limitations

- Durable zvec-backed memory is not wired in this slice.
- Memory lifecycle tools are exposed and hook-ready, but return
  `backend:"manifest-stub"`.
- The Docker image includes the Amaze MCP binary and source build path; zvec
  source is included in the repository for the next native memory integration.

## Repository

```text
https://github.com/steve-8000/amaze-mcp
```

## License

See `LICENSE` and `THIRD_PARTY.md`.
