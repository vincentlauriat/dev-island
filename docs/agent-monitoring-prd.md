# PRD — Agent Monitoring for Dev Island

**Status**: Draft
**Author**: derived from an analysis of [`patoles/agent-flow`](https://github.com/patoles/agent-flow) (Apache-2.0) against the current Dev Island codebase
**Date**: 2026-07-29

---

## 1. Summary

Dev Island today answers **"what is my agent doing *right now*, and does it need me?"**
It does not answer **"what did my agent *do*, in what order, and what did it cost?"**

Every hook payload Dev Island receives is folded into a single mutable
`AgentSession` and the previous value is discarded. There is no retained
history: no `history`, `timeline`, `toolCalls`, `SessionTrace` or `RingBuffer`
symbol exists anywhere under `Sources/`. The moment a `PostToolUse` arrives, the
previous `currentTool` is gone.

(The one recorder in the tree, `HarnessArtifactRecorder.swift`, captures window
screenshots and accessibility trees once per harness launch. It is test
tooling, not an event log, and has nothing to reuse here.)

This PRD proposes adding a **retained, inspectable execution record** —
per session, per agent, per tool call — surfaced in a dedicated window, while
keeping the notch overlay exactly as it is.

The reference implementation for the *model* (not the code, not the branding)
is Agent Flow, which solves the same problem for VS Code with a node-graph
canvas. Its transport layer is redundant with ours; its **event→graph reducer**
and **subagent correlation** are the parts worth taking.

---

## 2. What Dev Island already has

This section exists to prevent rebuilding what is already shipped. Verified
against the source, not the README.

| Capability | Where | Notes |
|---|---|---|
| Claude hook registration | `ClaudeHookInstaller.swift:49-63` | Dev Island registers a **strict superset** of Agent Flow's hook set. Agent Flow registers 9 (`hooks-config.ts:81-91`); Dev Island registers those 9 plus `UserPromptSubmit`, `StopFailure`, `PermissionRequest`, `PermissionDenied`, `PreCompact` |
| Transport | `BridgeServer.swift` + `DevIslandHooks` CLI | Unix domain socket, newline-delimited JSON. Lower latency and more robust than Agent Flow's loopback HTTP server |
| Pure reducer | `SessionState.apply(_:)` | Already the single source of truth for session mutation — the right place to hang a history model off |
| Current tool | `ClaudeSessionMetadata.currentTool` / `.currentToolInputPreview` (`ClaudeHooks.swift:254-255`) | Captured, displayed, then overwritten |
| Tool call ID | `ClaudeHookPayload.toolUseID` (`ClaudeHooks.swift:351`) | Decoded but unused — exact start/end matching is available for free |
| Model ID | `ClaudeSessionMetadata.model` | Captured |
| Live subagents | `ClaudeSessionMetadata.activeSubagents: [ClaudeSubagentInfo]` | `SubagentStart` adds, `SubagentStop` removes, stale ones GC'd (`BridgeServer.swift:2092-2151`). **Correlation is already solved** — Agent Flow has to infer it from `.meta.json` sidecars |
| Agent task description | `pendingAgentDescriptions` cache | `PreToolUse` for the `Agent` tool caches `description` for the next `SubagentStart` |
| Todo / task tracking | `ClaudeTaskInfo`, `updateTask(from:)` | `TaskCreate` / `TaskUpdate` parsed from tool input |
| Permission round-trip | `PermissionRequested` → island → `BridgeResponse` | Agent Flow can only *observe* permission prompts; it cannot answer them |
| Multi-agent breadth | `AgentTool` enum, 10 agents | Agent Flow supports 2 (Claude, Codex) |
| Session discovery | `ClaudeTranscriptDiscovery`, `ActiveAgentProcessDiscovery` | JSONL scan + `ps`/`lsof` reconciliation |
| Usage tracking | `ClaudeUsage.swift`, `CodexUsage.swift` | Account-level quota, not per-session context accounting |

**Conclusion: the ingestion layer is done.** No new hooks, no new transport, no
new installer work is required for the core of this feature.

---

## 3. The gap

What Agent Flow has that Dev Island does not, ranked by value:

| # | Gap | Evidence in Agent Flow |
|---|---|---|
| **G1** | **Retained event history.** Nothing survives the next event. | `SimulationState` holds `agents`, `toolCalls`, `edges`, `timelineEntries`, `conversations`, `fileAttention` as accumulating collections |
| **G2** | **Agent graph.** Orchestrator + subagents as nodes, parent→child edges, tool calls as satellite nodes. | `web/lib/agent-types.ts` — `Agent`, `ToolCallNode`, `Edge` |
| **G3** | **Per-agent timeline (Gantt).** Typed blocks: `thinking` / `tool_call` / `idle` / `complete`, each with start and end. | `TimelineEntry` / `TimelineBlock`, built by `pushTimelineBlock()` |
| **G4** | **Context accounting.** Token usage split by origin: system prompt, user messages, tool results, reasoning, subagent results — plus estimated $ cost per model family. | `ContextBreakdown`, `MODEL_FAMILY_CONTEXT`, `MODEL_FAMILY_COST` |
| **G5** | **File attention.** Which files were read/edited, how many times, by which agents, at what token cost. | `FileAttention` |
| **G6** | **Transcript / message feed.** Assistant text and thinking blocks, retained and scrollable. Dev Island keeps only `lastAssistantMessage`. | `transcript-parser.ts` emits `message` events with `role: assistant \| thinking \| user` |
| **G7** | **Structured tool arguments.** Per-tool summarizers producing readable one-liners, plus rich payloads (Edit diffs, todo lists, commands) for detail views. | `tool-summarizer.ts` — `summarizeInput()`, `extractInputData()` |
| **G8** | **Session replay / seek.** Scrub back through a completed session. | Control bar + `snap-visual-state.ts` |

G6 is the only gap that needs an ingestion change — thinking blocks and
assistant text are not in hook payloads and must come from the JSONL transcript.
Everything else is derivable from data Dev Island already receives and throws
away.

---

## 4. Users and jobs

Same user as the rest of Dev Island: a macOS developer running one or more
terminal coding agents. Three new jobs:

1. **Post-mortem** — "the agent took 12 minutes and produced garbage; where did
   it go wrong?" → timeline + tool sequence.
2. **Cost/context awareness** — "why is this session already at 60% context?" →
   context breakdown showing tool results dominate.
3. **Fan-out comprehension** — "I dispatched 5 subagents; which are still
   running and what is each one doing?" → agent graph.

Explicitly **not** a job: watching a pretty animation. The node graph is a
means, not the product.

---

## 5. Surface decision

Dev Island's surface is the notch. A pan/zoom node graph does not fit in a
notch. The split:

| Surface | Content | Change |
|---|---|---|
| **Notch overlay** | Unchanged: session count, phase, permission prompts, jump-back. | None |
| **Expanded island panel** | Add a per-session compact strip: last N tool calls, subagent count, context gauge. | Additive |
| **New window — "Session Monitor"** | Graph + timeline + transcript + file attention + context breakdown. Opened from a session row, from the menu bar, or by keyboard shortcut. | New |

**Naming**: "Agent Flow" and its logos are trademarked (`agent-flow/TRADEMARK.md`).
Do not reuse the name, the logo, or the visual identity. Working title:
**Session Monitor**.

---

## 6. Requirements

### 6.1 Must have (P0)

| ID | Requirement |
|---|---|
| R1 | Retain per-session execution history: every tool call with name, summarized arguments, result summary, start time, end time, error state. |
| R2 | History is bounded — a configurable per-session ring buffer (default 2 000 tool calls) with an explicit "older entries dropped" marker. Idle memory must stay flat over an all-day session. |
| R3 | Model the session as a graph: one main agent node plus one node per subagent, edges parent→child, sourced from the `SubagentStart` / `SubagentStop` correlation Dev Island already performs. |
| R4 | Per-agent timeline with typed blocks (`thinking`, `toolCall`, `waitingPermission`, `idle`, `complete`), each with a start and an end timestamp. |
| R5 | A "Session Monitor" window showing, for the selected session: the agent graph, the timeline, and a scrollable tool-call list. Selecting a tool call shows its full arguments and result. |
| R6 | Per-tool argument summarization for all Claude tools (Bash, Read, Edit, Write, Glob, Grep, Task/Agent, TodoWrite, WebSearch, WebFetch, AskUserQuestion, Skill, NotebookEdit) and Codex tools (`exec_command`, `apply_patch`, `update_plan`, `write_stdin`). |
| R7 | History survives the session ending — a completed session stays inspectable until dismissed or until the app restarts. |
| R8 | Fail-open is preserved: any failure in the monitoring path must not delay or block a hook response. |

### 6.2 Should have (P1)

| ID | Requirement |
|---|---|
| R9 | Context breakdown per agent: tokens attributed to system prompt / user messages / tool results / reasoning / subagent results, against the model's context window. |
| R10 | Estimated cost per session, derived from the model family. |
| R11 | File attention view: files touched, read/edit counts, owning agents, token cost. |
| R12 | Transcript feed: assistant messages and thinking blocks, read from the JSONL transcript (`ClaudeSessionMetadata.transcriptPath` is already captured). |
| R13 | Compact activity strip in the expanded island panel. |

### 6.3 Could have (P2)

| ID | Requirement |
|---|---|
| R14 | Replay: scrub a completed session's timeline. |
| R15 | Export a session's history as JSONL. |
| R16 | Codex parity, via `CodexSessionTracking` rather than hooks — Codex's managed hook set is intentionally low-noise, so tool-level detail and its authoritative token counts must come from the rollout stream. See architecture §3.3. |

### 6.4 Non-goals

- No node-graph rendering in the notch.
- No telemetry, no upload, no account. History stays in memory (and optionally
  on disk under `~/Library/Application Support/DevIsland/`), never leaves the
  machine.
- No new hook events, no new agent integrations, no changes to the installers.
- No port of Agent Flow's rendering stack (Canvas 2D, bloom shaders, audio
  engine). Those are re-implemented natively or dropped.
- No reuse of the "Agent Flow" name or branding.

---

## 7. Phasing

| Phase | Scope | Delta |
|---|---|---|
| **P1 — Record** | R1, R2, R6, R8. Capture and retain tool calls in a bounded per-session buffer. No new UI beyond a debug list. | Core model + `BridgeServer` capture point |
| **P2 — Show** | R3, R4, R5, R7. Session Monitor window: graph, timeline, tool list, detail pane. | New SwiftUI window |
| **P3 — Account** | R9, R10, R11, R13. Context breakdown, cost, file attention, island strip. | Estimators + panels |
| **P4 — Read** | R12, R16. Transcript tailing for thinking/assistant text; Codex authoritative tokens. | New ingestion source |
| **P5 — Replay** | R14, R15. | Optional |

Each phase ships independently and is useful on its own. P1 alone makes the
system debuggable; the rest is presentation.

---

## 8. Success criteria

- Opening Session Monitor on a running session shows the last 50 tool calls in
  correct order within 100 ms.
- A `Task` dispatch appears as a child node within one hook round-trip
  (< 50 ms after `SubagentStart`).
- Steady-state memory growth over an 8-hour session with 5 concurrent sessions
  stays under 50 MB.
- Hook response latency is unchanged versus today (measured at the
  `DevIslandHooks` CLI).
- Closing the Session Monitor window drops rendering cost to zero — no timer,
  no animation loop running in the background.

---

## 9. Risks

| Risk | Mitigation |
|---|---|
| **Memory growth.** Retaining every tool result is unbounded by nature. | Ring buffer (R2). Store *summaries* by default; keep full payloads only for the N most recent calls. |
| **Hook latency.** Capture work on the socket-read path could slow the fail-open guarantee. | Capture is an append to a preallocated buffer, off the response path. Response is sent first, recording second. |
| **Token estimates are wrong.** Agent Flow's `estimateTokenCost()` is `length / 4` with per-tool multipliers — an approximation, not truth. | Label the UI "estimated". Prefer authoritative counts where available (Codex rollout, Claude status line). |
| **Scope creep into a second product.** The graph is seductive; Dev Island is a notch app. | Non-goals section. The notch is untouched; the window is opt-in. |
| **Licensing.** Agent Flow is Apache-2.0, Dev Island is GPL-3.0. | Apache-2.0 → GPL-3.0 is one-way compatible: incorporation is permitted, attribution required, and the result stays GPL-3.0. Any file whose logic is derived from Agent Flow must carry an attribution header. Trademarks are **not** licensed — no name or logo reuse. |

---

## 10. Open questions

1. **Persistence** — is in-memory-only history acceptable for v1, or must a
   session survive an app restart? (Affects P1 storage design; assumption taken:
   in-memory only for v1.)
2. **Window vs. sheet** — a standalone `NSWindow` or a large sheet off the
   settings window? (Assumption taken: standalone window, so it can sit on a
   second display.)
3. **Multi-session view** — one window per session, or one window with a session
   picker? (Assumption taken: one window, session picker in the toolbar.)

---

## 11. References

- Agent Flow source: `~/DevApps/AgentsTools/agent-flow` (Apache-2.0, © Simon Patole)
- Event protocol: `agent-flow/extension/src/protocol.ts`
- View model: `agent-flow/web/lib/agent-types.ts`
- Reducer: `agent-flow/web/hooks/simulation/`
- Companion document: [`agent-monitoring-architecture.md`](agent-monitoring-architecture.md)
