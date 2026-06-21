# Amaze Native Agent Memory Design

## Goal

Build `amaze` as a single local MCP runtime that exposes the existing codebase
intelligence tools and a durable agent memory system from one Docker container
and one MCP server. Tool names stay stable. The server, package, image, and
installed protocol are branded `amaze`.

The critical quality target is not memory volume. It is freshness: the agent
must recall the latest validated information first, demote stale facts, and
rebuild memory indexes when source state changes.

## Current Context

`codebase-memory-mcp` is a C MCP server with code graph tools, a CLI installer,
agent instructions, and hooks. `zvec-memory-mcp` currently exists as a Python
sidecar prototype under `tools/zvec-memory-mcp`, and the separate `zvec`
repository has a C API in `src/include/zvec/c_api.h`.

The desired architecture removes the Python sidecar. Zvec is used as a native
vector and metadata store only. It does not embed text and does not run a model.
The existing codebase semantic engine owns tokenization, vector generation, and
freshness-aware ranking.

## Product Shape

`amaze` consists of four coordinated surfaces:

- MCP tools: code graph tools plus memory lifecycle tools.
- Hook commands: session start, before tool, after tool, and finalize commands.
- Installed protocol files: `AGENTS.md`, Claude/Codex/Gemini instructions, and
  hook configuration.
- Local stores: SQLite graph cache and zvec-backed memory collections.

The agent must not rely on voluntary tool use alone. `amaze install` configures
MCP, hooks, and instructions together so the runtime protocol is repeatedly
injected and enforced.

## MCP Tool Surface

Existing code tools keep their names:

- `index_repository`
- `index_status`
- `list_projects`
- `delete_project`
- `search_graph`
- `search_code`
- `query_graph`
- `trace_path`
- `get_code_snippet`
- `get_graph_schema`
- `get_architecture`
- `detect_changes`
- `manage_adr`
- `ingest_traces`

Memory tools are native and lifecycle-aware:

- `memory_recall`: return current project/session/user memory and stale warnings.
- `memory_search`: explicit semantic/freshness-aware memory search.
- `memory_candidate`: record a pending memory candidate from user text, tool
  output, hook observation, or agent conclusion.
- `memory_validate`: validate pending candidates against source metadata,
  hashes, freshness policy, and conflict rules.
- `memory_commit`: promote validated candidates into durable memory.
- `memory_get`: fetch one memory item.
- `memory_list`: inspect pending, committed, stale, rejected, and expired items.
- `memory_delete`: explicit deletion by id or safe filtered dry run.
- `memory_feedback`: mark recalled memory as useful, wrong, stale, or ignored.
- `memory_compact`: deterministic pruning, supersede marking, and low-rank
  cleanup.
- `memory_rebuild`: rebuild manifests, vectors, and zvec collections.
- `memory_audit`: report conflicts, stale records, source hash mismatches, and
  rebuild requirements.
- `memory_stats`: report store layout, counts, vector version, and freshness
  health.

## Memory Lifecycle

Memory is not inserted directly into durable recall by default. It moves through
a lifecycle:

```text
Observe -> Candidate -> Validate -> Commit -> Rebuild -> Recall -> Feedback
```

States:

- `pending`: observed but not trusted.
- `validated`: eligible to commit.
- `committed`: durable and recallable.
- `stale`: source changed or TTL expired; demoted until revalidated.
- `superseded`: replaced by a newer memory.
- `rejected`: explicitly not durable.
- `deleted`: tombstoned or removed.

Important discoveries from hooks and tool output become `pending` candidates.
Validated records are committed. Rebuild refreshes the vector index and
metadata. Recall returns only committed memory by default, with stale warnings
included when useful.

## Freshness Model

Every memory item carries:

- `created_at`
- `updated_at`
- `last_seen_at`
- `last_verified_at`
- `valid_until`
- `source`
- `source_ref`
- `source_hash`
- `evidence_refs`
- `confidence`
- `importance`
- `freshness_policy`
- `staleness_score`
- `vector_version`
- `schema_version`

Freshness policies:

- User preference: long-lived; newer explicit user instruction supersedes older.
- Architecture decision: long-lived; may be superseded by newer decision or ADR.
- Code summary: stale when indexed graph generation, file hash, or git diff
  changes.
- Test/build result: short TTL; stale quickly.
- External fact: must carry fetch timestamp and source; stale by TTL.
- Hook observation: pending by default; low confidence until validated.

Ranking combines semantic similarity with freshness:

```text
rank =
  semantic_score
  + lexical_score
  + confidence
  + importance
  + recency_boost
  + access_boost
  - staleness_penalty
  - contradiction_penalty
```

The freshest validated memory wins over older high-similarity memory unless the
older item is explicitly marked durable and still valid.

## Native Storage Architecture

`amaze` adds a native memory module:

```text
src/memory/
  memory.h
  memory.c
  memory_embed.c
  memory_store_zvec.c
  memory_freshness.c
  memory_manifest.c
```

Responsibilities:

- `memory.c`: lifecycle API and MCP-facing orchestration.
- `memory_embed.c`: wrap `src/semantic` tokenization/vector generation for
  arbitrary memory text.
- `memory_store_zvec.c`: thin adapter over zvec C API.
- `memory_freshness.c`: TTL, source hash, graph generation, and rank policies.
- `memory_manifest.c`: JSON manifest and rebuild bookkeeping.

Zvec collections are scope-based:

```text
~/.cache/amaze/
  graph/
    <project>.db
  memory/
    common/
    projects/<project-key>/
    sessions/
    artifacts/
```

The initial implementation may use deterministic JSON manifest persistence for
metadata and zvec for vector lookup. The adapter boundary keeps the lifecycle
stable if zvec schema details change.

## Hook Protocol

Existing code search augmentation remains non-blocking. Memory hooks are a
separate protocol with configurable enforcement:

```text
memory_enforcement = off | advisory | strict | blocking
```

Default: `strict`.

Hook commands:

- `amaze hook-session-start`
  - Runs `memory_recall`.
  - Checks graph and memory freshness.
  - Injects project protocol and stale warnings.

- `amaze hook-before-tool`
  - For code search tools, augments with graph context.
  - For edit/write tools, verifies recent memory recall happened.
  - For bash/test tools, recalls prior build/test failures and decisions.

- `amaze hook-after-tool`
  - Captures important tool outcomes as `memory_candidate`.
  - Updates freshness signals for source files and test/build outputs.

- `amaze hook-session-finalize`
  - Validates pending candidates.
  - Commits eligible memory.
  - Triggers rebuild when vector/schema/source state requires it.

`blocking` mode is only enabled for agent hook systems that reliably support
tool denial without breaking required read-before-edit behavior. Unsupported
agents fall back to `strict` instructions and injected context.

## Installed Agent Protocol

`amaze install` writes or updates agent instruction files. The instructions are
procedural, not promotional:

```text
1. On session start, read injected amaze context.
2. Before planning or editing, use memory_recall for current project context.
3. For code exploration, use search_graph/get_code_snippet/trace_path before
   raw grep or broad file reads.
4. Use memory_candidate for new durable facts; do not commit speculation.
5. If memory is stale, verify against current code, source hash, or user input.
6. At completion, validate and commit durable decisions or findings.
```

Agent-specific installs:

- Codex: MCP config, `AGENTS.md`, SessionStart hook, and future before/after
  tool hook support where available.
- Claude Code: MCP config, instruction section, PreToolUse code augment hook,
  SessionStart memory recall hook, optional strict memory hook.
- Gemini/Antigravity: MCP config, settings hooks, and instruction files.

## Naming And Compatibility

New names:

- Binary: `amaze`
- MCP server key: `amaze`
- Container: `amaze`
- Image: `amaze:local`
- Cache env: `AMAZE_CACHE_DIR`
- Memory env: `AMAZE_MEMORY_DIR`

Compatibility:

- Existing tool names remain unchanged.
- Existing `codebase-memory-mcp` command may remain as a wrapper during
  transition.
- Existing `CBM_*` env vars are read as fallback and documented as deprecated.

## Build Strategy

Phase 1 keeps zvec native integration behind an adapter and feature flag while
building the lifecycle API and hooks. Phase 2 links the zvec C API into the
production Docker image. Phase 3 makes native zvec mandatory for `amaze`
release builds.

This avoids hiding failures behind a Python fallback. If native zvec is not
available in a mandatory build, memory tools report an explicit runtime error
and `memory_audit` surfaces the missing backend.

## Verification Strategy

Focused tests:

- MCP `tools/list` includes existing code tools and memory lifecycle tools.
- `memory_candidate -> memory_validate -> memory_commit -> memory_recall`
  works in a temp memory store.
- stale source hash demotes memory in recall ranking.
- `memory_rebuild` regenerates vectors and manifest metadata.
- hook commands emit valid hook payloads and obey enforcement mode.
- install tests verify MCP config, hooks, and instruction protocol insertion.

Baseline note: at the start of this branch, `make -f Makefile.cbm
test-foundation` fails because the target links `tests/test_main.c`, whose
runner references all suites while the target links only foundation suites.
`scripts/build.sh` also fails on this machine with Homebrew libgit2 headers that
do not expose `git_allocator`. These are pre-existing baseline issues and are
not part of the first memory implementation slice.

## First Implementation Slice

The first slice should not attempt full zvec linking. It should establish the
runtime protocol safely:

1. Rename surfaced server identity to `amaze` while keeping tool names stable.
2. Add native memory lifecycle tool definitions and deterministic stub handlers.
3. Add memory instruction text and hook command skeletons.
4. Add tests proving agents can see and call the new protocol.

The second slice replaces deterministic stubs with manifest-backed memory. The
third slice links zvec and activates vector search.
