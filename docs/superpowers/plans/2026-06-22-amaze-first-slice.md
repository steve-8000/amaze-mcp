# Amaze First Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first testable `amaze` slice: branded MCP identity, memory lifecycle tool surface, hook command skeletons, and agent protocol installation.

**Architecture:** Keep existing code graph tool names and handlers. Add memory lifecycle tools as native C handlers with deterministic JSON responses, then wire hook/instruction skeletons that force agents to recall and capture memory. Zvec storage is not linked in this slice; handlers report `backend:"manifest-stub"` so the MCP/hook protocol can be verified before native zvec integration.

**Tech Stack:** C11, yyjson, existing MCP server, existing CLI installer/hook code, Makefile.cbm tests.

---

## File Structure

- Modify `src/mcp/mcp.c`: add memory tool definitions and dispatch handlers.
- Modify `tests/test_mcp.c`: assert memory tools appear and return structured lifecycle responses.
- Modify `src/main.c`: add `hook-memory-*` CLI command routing.
- Modify `src/cli/cli.h`: declare new hook command functions and config keys.
- Modify `src/cli/cli.c`: add memory enforcement config keys, instruction text, install hook script generation, and hook command skeletons.
- Modify `tests/test_cli.c`: assert memory config keys, instruction protocol, and hook scripts are installed.
- Modify `server.json`: change server package identity/title to `amaze`.
- Add `docs/superpowers/specs/2026-06-22-amaze-native-agent-memory-design.md`: already committed design source.

## Baseline Notes

Do not use `make -f Makefile.cbm test-foundation` as the proof command for this branch. It currently links `tests/test_main.c`, which references every suite while the target links only foundation suites. Do not use plain `scripts/build.sh` as the first proof command on this machine unless libgit2 autodetection is disabled, because Homebrew libgit2 1.9.4 does not expose `git_allocator` expected by `internal/cbm/cbm.c`.

For this slice, use focused test builds and direct MCP/CLI assertions. If a production build is needed, use:

```bash
make -f Makefile.cbm cbm LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected: `build/c/codebase-memory-mcp` is produced.

---

### Task 1: MCP Memory Tool Surface

**Files:**
- Modify: `src/mcp/mcp.c`
- Modify: `tests/test_mcp.c`

- [ ] **Step 1: Write the failing tool-list test**

Add assertions to `tool_list_contains_all_tools` in `tests/test_mcp.c`:

```c
    ASSERT_NOT_NULL(strstr(json, "memory_recall"));
    ASSERT_NOT_NULL(strstr(json, "memory_search"));
    ASSERT_NOT_NULL(strstr(json, "memory_candidate"));
    ASSERT_NOT_NULL(strstr(json, "memory_validate"));
    ASSERT_NOT_NULL(strstr(json, "memory_commit"));
    ASSERT_NOT_NULL(strstr(json, "memory_feedback"));
    ASSERT_NOT_NULL(strstr(json, "memory_rebuild"));
    ASSERT_NOT_NULL(strstr(json, "memory_audit"));
```

- [ ] **Step 2: Write the failing memory call test**

Add a test near the existing MCP tool call tests:

```c
TEST(tool_memory_recall_stub) {
    cbm_mcp_server_t *srv = cbm_mcp_server_new(NULL);
    ASSERT_NOT_NULL(srv);

    char *resp = cbm_mcp_server_handle(
        srv,
        "{\"jsonrpc\":\"2.0\",\"id\":501,\"method\":\"tools/call\","
        "\"params\":{\"name\":\"memory_recall\","
        "\"arguments\":{\"project_key\":\"amaze\",\"query\":\"startup\"}}}");

    ASSERT_NOT_NULL(resp);
    ASSERT_NOT_NULL(strstr(resp, "\"id\":501"));
    ASSERT_NOT_NULL(strstr(resp, "\"memory_recall\""));
    ASSERT_NOT_NULL(strstr(resp, "\"backend\""));
    ASSERT_NOT_NULL(strstr(resp, "\"manifest-stub\""));
    ASSERT_NOT_NULL(strstr(resp, "\"freshness\""));

    free(resp);
    cbm_mcp_server_free(srv);
    PASS();
}
```

Add `RUN_TEST(tool_memory_recall_stub);` next to the other MCP tool tests in `suite_mcp`.

- [ ] **Step 3: Run the targeted test and verify RED**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected before implementation: test binary builds or reaches test execution, then fails because `memory_recall` is not in `tools/list` or returns `unknown tool`.

- [ ] **Step 4: Add memory tool definitions**

In `src/mcp/mcp.c`, append these tool definitions before `ingest_traces` or after it in `TOOLS[]`:

```c
    {"memory_recall",
     "Recall fresh validated agent memory for the current user, project, session, and task. "
     "Returns stale warnings when recalled memory requires verification.",
     "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},"
     "\"project_key\":{\"type\":\"string\"},\"project_path\":{\"type\":\"string\"},"
     "\"scope\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"array\",\"items\":{\"type\":\"string\"}}]},"
     "\"topk\":{\"type\":\"integer\",\"default\":10},\"include_stale\":{\"type\":\"boolean\","
     "\"default\":false}},\"required\":[]}"},
    {"memory_search",
     "Search durable agent memory with semantic, lexical, confidence, and freshness ranking.",
     "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},"
     "\"project_key\":{\"type\":\"string\"},\"project_path\":{\"type\":\"string\"},"
     "\"kind\":{\"oneOf\":[{\"type\":\"string\"},{\"type\":\"array\",\"items\":{\"type\":\"string\"}}]},"
     "\"topk\":{\"type\":\"integer\",\"default\":10},\"include_stale\":{\"type\":\"boolean\","
     "\"default\":false}},\"required\":[\"query\"]}"},
    {"memory_candidate",
     "Record a pending memory candidate. Candidates are not durable until validated and committed.",
     "{\"type\":\"object\",\"properties\":{\"text\":{\"type\":\"string\"},"
     "\"scope\":{\"type\":\"string\"},\"project_key\":{\"type\":\"string\"},"
     "\"project_path\":{\"type\":\"string\"},\"kind\":{\"type\":\"string\"},"
     "\"source\":{\"type\":\"string\"},\"source_ref\":{\"type\":\"string\"},"
     "\"confidence\":{\"type\":\"number\"},\"importance\":{\"type\":\"number\"}},"
     "\"required\":[\"text\"]}"},
    {"memory_validate",
     "Validate pending memory candidates against source hashes, freshness policy, duplicate checks, and conflicts.",
     "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},"
     "\"project_key\":{\"type\":\"string\"},\"dry_run\":{\"type\":\"boolean\",\"default\":true}},"
     "\"required\":[]}"},
    {"memory_commit",
     "Promote validated memory candidates into durable recallable memory.",
     "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},"
     "\"project_key\":{\"type\":\"string\"},\"dry_run\":{\"type\":\"boolean\",\"default\":false}},"
     "\"required\":[]}"},
    {"memory_feedback",
     "Report whether recalled memory was useful, stale, wrong, or ignored so ranking can adapt.",
     "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"string\"},"
     "\"outcome\":{\"type\":\"string\",\"enum\":[\"used\",\"ignored\",\"stale\",\"wrong\"]},"
     "\"note\":{\"type\":\"string\"}},\"required\":[\"id\",\"outcome\"]}"},
    {"memory_rebuild",
     "Rebuild memory manifests, vectors, and zvec collections when schema, vector version, or source state changes.",
     "{\"type\":\"object\",\"properties\":{\"project_key\":{\"type\":\"string\"},"
     "\"scope\":{\"type\":\"string\"},\"dry_run\":{\"type\":\"boolean\",\"default\":true}},"
     "\"required\":[]}"},
    {"memory_audit",
     "Audit memory freshness, source hash mismatches, conflicts, stale items, and rebuild requirements.",
     "{\"type\":\"object\",\"properties\":{\"project_key\":{\"type\":\"string\"},"
     "\"include_items\":{\"type\":\"boolean\",\"default\":false}},\"required\":[]}"},
```

- [ ] **Step 5: Add deterministic memory stub handler**

Add a helper near the tool dispatch section in `src/mcp/mcp.c`:

```c
static char *handle_memory_stub(const char *tool_name, const char *args_json) {
    yyjson_doc *args_doc = args_json ? yyjson_read(args_json, strlen(args_json), 0) : NULL;
    yyjson_val *args_root = args_doc ? yyjson_doc_get_root(args_doc) : NULL;
    const char *project_key = NULL;
    yyjson_val *pk = args_root ? yyjson_obj_get(args_root, "project_key") : NULL;
    if (pk && yyjson_is_str(pk)) {
        project_key = yyjson_get_str(pk);
    }

    yyjson_mut_doc *doc = yyjson_mut_doc_new(NULL);
    yyjson_mut_val *root = yyjson_mut_obj(doc);
    yyjson_mut_doc_set_root(doc, root);
    yyjson_mut_obj_add_str(doc, root, "tool", tool_name ? tool_name : "memory");
    yyjson_mut_obj_add_str(doc, root, "backend", "manifest-stub");
    yyjson_mut_obj_add_str(doc, root, "status", "not_configured");
    yyjson_mut_obj_add_str(doc, root, "project_key", project_key ? project_key : "");
    yyjson_mut_obj_add_str(doc, root, "freshness", "unknown");
    yyjson_mut_obj_add_str(doc, root, "next", "wire native memory manifest and zvec adapter");

    char *json = yy_doc_to_str(doc);
    yyjson_mut_doc_free(doc);
    if (args_doc) {
        yyjson_doc_free(args_doc);
    }
    char *result = cbm_mcp_text_result(json ? json : "{}", false);
    free(json);
    return result;
}
```

In `cbm_mcp_handle_tool`, before the unknown-tool branch, add:

```c
    if (strncmp(tool_name, "memory_", strlen("memory_")) == 0) {
        return handle_memory_stub(tool_name, args_json);
    }
```

- [ ] **Step 6: Run targeted tests and verify GREEN**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected: the MCP memory tool-list and memory recall tests pass. If the full test target is too slow, compile and run the existing full test binary once and record where it stops; do not claim global pass unless it completes.

- [ ] **Step 7: Commit**

```bash
git add src/mcp/mcp.c tests/test_mcp.c
git commit -m "feat: expose amaze memory lifecycle tools"
```

---

### Task 2: Amaze Server Identity

**Files:**
- Modify: `src/mcp/mcp.c`
- Modify: `server.json`
- Modify: `tests/test_mcp.c`

- [ ] **Step 1: Write failing initialize identity test**

In `tests/test_mcp.c`, update or add an initialize response test:

```c
TEST(initialize_reports_amaze_server_info) {
    char *resp = cbm_mcp_initialize_response("{}");
    ASSERT_NOT_NULL(resp);
    ASSERT_NOT_NULL(strstr(resp, "\"serverInfo\""));
    ASSERT_NOT_NULL(strstr(resp, "\"name\":\"amaze\""));
    free(resp);
    PASS();
}
```

Add `RUN_TEST(initialize_reports_amaze_server_info);` in `suite_mcp`.

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected before implementation: initialize response still reports `codebase-memory-mcp`.

- [ ] **Step 3: Change initialize response server name**

In `src/mcp/mcp.c`, find `cbm_mcp_initialize_response` and change the server info name from `codebase-memory-mcp` to `amaze`. Keep version unchanged.

- [ ] **Step 4: Change registry metadata**

Edit `server.json`:

```json
{
  "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
  "name": "io.github.DeusData/amaze",
  "title": "Amaze",
  "description": "Freshness-aware local code graph and durable agent memory runtime.",
  "repository": {
    "url": "https://github.com/DeusData/codebase-memory-mcp",
    "source": "github"
  },
  "websiteUrl": "https://deusdata.github.io/codebase-memory-mcp/",
  "version": "0.8.1",
  "packages": [
    {
      "registryType": "npm",
      "identifier": "amaze",
      "version": "0.8.1",
      "runtimeHint": "npx",
      "transport": {
        "type": "stdio"
      }
    },
    {
      "registryType": "pypi",
      "identifier": "amaze",
      "version": "0.8.1",
      "runtimeHint": "uvx",
      "transport": {
        "type": "stdio"
      }
    }
  ]
}
```

- [ ] **Step 5: Run test and verify GREEN**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected: initialize identity test passes.

- [ ] **Step 6: Commit**

```bash
git add src/mcp/mcp.c server.json tests/test_mcp.c
git commit -m "feat: report amaze server identity"
```

---

### Task 3: Memory Hook Command Skeletons

**Files:**
- Modify: `src/main.c`
- Modify: `src/cli/cli.h`
- Modify: `src/cli/cli.c`
- Modify: `tests/test_cli.c`

- [ ] **Step 1: Write failing CLI hook tests**

Add tests to `tests/test_cli.c`:

```c
TEST(cli_memory_hook_session_start_outputs_protocol) {
    int rc = cbm_cmd_hook_memory_session_start();
    ASSERT_EQ(rc, 0);
    PASS();
}

TEST(cli_config_lists_memory_enforcement) {
    char tmpdir[256];
    snprintf(tmpdir, sizeof(tmpdir), "/tmp/cli-memory-config-XXXXXX");
    if (!cbm_mkdtemp(tmpdir))
        FAIL("cbm_mkdtemp failed");

    setenv("CBM_CACHE_DIR", tmpdir, 1);
    char *argv[] = {"list"};
    int rc = cbm_cmd_config(1, argv);
    ASSERT_EQ(rc, 0);

    unsetenv("CBM_CACHE_DIR");
    test_rmdir_r(tmpdir);
    PASS();
}
```

The first test only verifies callable skeleton behavior. The second test should be strengthened after stdout capture helpers are available.

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected before implementation: compile fails because `cbm_cmd_hook_memory_session_start` is undeclared.

- [ ] **Step 3: Declare config keys and hook commands**

In `src/cli/cli.h`, add:

```c
#define CBM_CONFIG_MEMORY_ENFORCEMENT "memory_enforcement"
#define CBM_CONFIG_MEMORY_RECALL_TOPK "memory_recall_topk"

int cbm_cmd_hook_memory_session_start(void);
int cbm_cmd_hook_memory_before_tool(void);
int cbm_cmd_hook_memory_after_tool(void);
int cbm_cmd_hook_memory_finalize(void);
```

- [ ] **Step 4: Implement hook skeletons**

In `src/cli/cli.c`, add:

```c
static int emit_memory_hook_context(const char *event_name) {
    printf("AMAZE MEMORY PROTOCOL [%s]\\n", event_name);
    printf("- Run memory_recall before planning or editing.\\n");
    printf("- Verify stale memory against current code or source before relying on it.\\n");
    printf("- Store durable findings with memory_candidate, then validate and commit.\\n");
    printf("- Use code graph tools before broad grep or file-by-file exploration.\\n");
    return 0;
}

int cbm_cmd_hook_memory_session_start(void) {
    return emit_memory_hook_context("session-start");
}

int cbm_cmd_hook_memory_before_tool(void) {
    return emit_memory_hook_context("before-tool");
}

int cbm_cmd_hook_memory_after_tool(void) {
    return emit_memory_hook_context("after-tool");
}

int cbm_cmd_hook_memory_finalize(void) {
    return emit_memory_hook_context("finalize");
}
```

- [ ] **Step 5: Route CLI commands**

In `src/main.c`, add command branches where other subcommands are routed:

```c
    if (strcmp(argv[1], "hook-memory-session-start") == 0) {
        return cbm_cmd_hook_memory_session_start();
    }
    if (strcmp(argv[1], "hook-memory-before-tool") == 0) {
        return cbm_cmd_hook_memory_before_tool();
    }
    if (strcmp(argv[1], "hook-memory-after-tool") == 0) {
        return cbm_cmd_hook_memory_after_tool();
    }
    if (strcmp(argv[1], "hook-memory-finalize") == 0) {
        return cbm_cmd_hook_memory_finalize();
    }
```

- [ ] **Step 6: Add config keys to config list output**

In `cbm_cmd_config`, add defaults:

```c
        printf("  %-25s  default=%-10s  %s\n", CBM_CONFIG_MEMORY_ENFORCEMENT, "strict",
               "Memory hook enforcement: off, advisory, strict, or blocking");
        printf("  %-25s  default=%-10s  %s\n", CBM_CONFIG_MEMORY_RECALL_TOPK, "10",
               "Default number of memories returned by session recall");
```

And list values:

```c
        printf("  %-25s = %-10s\n", CBM_CONFIG_MEMORY_ENFORCEMENT,
               cbm_config_get(cfg, CBM_CONFIG_MEMORY_ENFORCEMENT, "strict"));
        printf("  %-25s = %-10s\n", CBM_CONFIG_MEMORY_RECALL_TOPK,
               cbm_config_get(cfg, CBM_CONFIG_MEMORY_RECALL_TOPK, "10"));
```

- [ ] **Step 7: Run tests and verify GREEN**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected: hook command declarations and config tests pass.

- [ ] **Step 8: Commit**

```bash
git add src/main.c src/cli/cli.h src/cli/cli.c tests/test_cli.c
git commit -m "feat: add amaze memory hook commands"
```

---

### Task 4: Agent Protocol Instructions

**Files:**
- Modify: `src/cli/cli.c`
- Modify: `tests/test_cli.c`

- [ ] **Step 1: Write failing instruction test**

In `tests/test_cli.c`, add:

```c
TEST(cli_agent_instructions_include_amaze_memory_protocol) {
    const char *instructions = cbm_get_agent_instructions();
    ASSERT_NOT_NULL(instructions);
    ASSERT_NOT_NULL(strstr(instructions, "Amaze Memory Protocol"));
    ASSERT_NOT_NULL(strstr(instructions, "memory_recall"));
    ASSERT_NOT_NULL(strstr(instructions, "memory_candidate"));
    ASSERT_NOT_NULL(strstr(instructions, "memory_validate"));
    ASSERT_NOT_NULL(strstr(instructions, "memory_commit"));
    ASSERT_NOT_NULL(strstr(instructions, "search_graph"));
    PASS();
}
```

Add `RUN_TEST(cli_agent_instructions_include_amaze_memory_protocol);` in `suite_cli`.

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected before implementation: instruction text does not include the new memory protocol heading.

- [ ] **Step 3: Update instruction text**

Find `cbm_get_agent_instructions` in `src/cli/cli.c` and add this section inside the generated markdown:

```text
## Amaze Memory Protocol

- Start each session by using injected amaze context from hooks.
- Before planning or editing, use memory_recall for current project context.
- If recalled memory is stale, verify it against code, source hash, tool output, or user input before relying on it.
- Store durable discoveries with memory_candidate. Do not commit speculative facts directly.
- Promote only validated candidates with memory_validate and memory_commit.
- Use memory_feedback when recalled memory was useful, stale, wrong, or ignored.

## Amaze Code Protocol

- Use search_graph, get_code_snippet, trace_path, query_graph, and search_code before broad raw grep or file-by-file exploration.
- Run index_repository when the current project is missing or stale.
- Use trace_path and detect_changes before modifying shared handlers or high-risk functions.
```

- [ ] **Step 4: Run test and verify GREEN**

Run:

```bash
make -f Makefile.cbm test LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected: instruction protocol test passes.

- [ ] **Step 5: Commit**

```bash
git add src/cli/cli.c tests/test_cli.c
git commit -m "docs: install amaze agent protocol"
```

---

### Task 5: Build Smoke And CLI Probe

**Files:**
- No source changes expected unless verification exposes a defect in this slice.

- [ ] **Step 1: Build production binary with libgit2 disabled**

Run:

```bash
make -f Makefile.cbm cbm LIBGIT2_LIBS= LIBGIT2_FLAGS=
```

Expected: `build/c/codebase-memory-mcp` exists.

- [ ] **Step 2: Probe MCP tools/list**

Run:

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}\n' | build/c/codebase-memory-mcp > /tmp/amaze-mcp.out
```

Expected: `/tmp/amaze-mcp.out` contains `"name":"amaze"` and `"memory_recall"`.

- [ ] **Step 3: Probe memory tool call**

Run:

```bash
printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}\n{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"memory_recall","arguments":{"project_key":"amaze","query":"startup"}}}\n' | build/c/codebase-memory-mcp > /tmp/amaze-memory.out
```

Expected: `/tmp/amaze-memory.out` contains `"id":3`, `memory_recall`, and `manifest-stub`.

- [ ] **Step 4: Probe hook command**

Run:

```bash
build/c/codebase-memory-mcp hook-memory-session-start > /tmp/amaze-hook.out
```

Expected: `/tmp/amaze-hook.out` contains `AMAZE MEMORY PROTOCOL` and `memory_recall`.

- [ ] **Step 5: Record verification status**

If all commands pass, report the exact commands and observed matching strings. If any command fails, record the failing command, exit code, and first relevant error line.

---

## Self-Review

Spec coverage:

- Native zvec storage is intentionally not implemented in this first slice; the plan creates a stable adapter-ready protocol and marks the backend as `manifest-stub`.
- Freshness is represented in tool schemas, stub responses, instructions, and hooks; concrete freshness ranking is a later slice.
- Hook and AGENTS protocol are included so agents can be guided before storage is complete.

Placeholder scan:

- No incomplete markers or unbounded deferred-work instructions are used. Deferred native zvec work is explicitly scoped out of this slice.

Type consistency:

- Memory tool names match the design doc.
- Hook command names use the `hook-memory-*` convention consistently.
- Config keys use existing `CBM_CONFIG_*` naming for compatibility while surfaced behavior is branded `amaze`.
