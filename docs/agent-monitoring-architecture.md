# Architecture — Agent Monitoring

Companion to [`agent-monitoring-prd.md`](agent-monitoring-prd.md).

Part 1 documents how [Agent Flow](https://github.com/patoles/agent-flow)
(Apache-2.0, © Simon Patole) works, because that is the mechanism being
recovered. Part 2 maps it onto Dev Island. Part 3 is the implementation plan.

---

# Part 1 — How Agent Flow works

## 1.1 Shape

Three deployment targets over one shared core:

| Target | Entry | Transport to UI |
|---|---|---|
| VS Code extension | `extension/src/extension.ts` | `postMessage` to a webview |
| Standalone web app (`npx agent-flow-app`) | `app/src/server.ts` | SSE via `scripts/relay.ts` |
| Dev server (`pnpm run dev`) | Next.js + relay | SSE |

All three feed the same React app (`web/`), which holds all state client-side.
There is no database and no server-side state — the relay is a dumb fan-out.

## 1.2 Ingestion: two redundant sources

Agent Flow deliberately runs **two** ingestion paths for Claude Code
simultaneously, and dedupes downstream:

### Source A — hook server (`extension/src/hook-server.ts`)

A loopback HTTP server. Hooks registered in `~/.claude/settings.json`
(`hooks-config.ts:81-91`) POST their JSON payload to it:

```
SessionStart, PreToolUse, PostToolUse, PostToolUseFailure,
SubagentStart, SubagentStop, Notification, Stop, SessionEnd
```

It always replies `200` with an **empty body** — returning even `{}` makes
Claude Code attempt schema parsing. This is the low-latency path: an event
appears the instant the tool starts.

### Source B — transcript tailing (`session-watcher.ts`, `transcript-parser.ts`)

Watches `~/.claude/projects/**/*.jsonl` with `fs.watch` plus a 3 s poll
fallback, reading only bytes past the last known offset (`fs-utils.ts`).
Subagent transcripts live in a `subagents/` subdirectory, discovered by a
directory watcher (`subagent-watcher.ts`).

The transcript carries what hooks do not: **thinking blocks**, **assistant
text**, model IDs, and token-bearing tool results.

### Deduplication

The two sources race. Reconciliation happens in three places:

- `WatchedSession.seenToolUseIds: Set<string>` — the transcript's
  `tool_use.id` is the dedup key.
- `spawnedSubagents: Set<string>` — prevents a subagent being spawned twice
  (once by the hook, once by the file watcher).
- A 3-second window in the reducer: `handleToolCallStart()` drops a
  `tool_call_start` if a running call for the same `agent + tool` began within
  `TOOL_DEDUP_WINDOW_S` (`handle-tool-events.ts:28-34`).

Note that `SubagentStart` deliberately does **not** emit a spawn from the hook
server (`hook-server.ts:257-270`) — it only records the `agent_id → name`
mapping. The transcript parser owns naming, because it can read the `Task`
tool's `description`, which is what the user actually recognises.

### Codex

A separate path: `codex-runtime.ts` tails `~/.codex/sessions/**/rollout-*.jsonl`
and parses it in `codex-rollout-parser.ts`. Codex's rollout stream carries
**authoritative token counts**, so no estimation is needed there.

## 1.3 The event protocol (verbatim)

From `extension/src/protocol.ts:10-29`. This is the contract; everything
downstream is a function of it.

```ts
export type AgentEventType =
  | 'agent_spawn'
  | 'agent_complete'
  | 'agent_idle'
  | 'message'
  | 'context_update'
  | 'model_detected'
  | 'tool_call_start'
  | 'tool_call_end'
  | 'subagent_dispatch'
  | 'subagent_return'
  | 'permission_requested'
  | 'error'

export interface AgentEvent {
  time: number            // seconds elapsed since session start
  type: AgentEventType
  payload: Record<string, unknown>
  sessionId?: string
}
```

Payload shapes, as actually emitted:

| Event | Payload keys |
|---|---|
| `agent_spawn` | `name`, `isMain?`, `parent?`, `task?`, `model?`, `runtime?` |
| `agent_complete` | `name`, `sessionEnd?` |
| `agent_idle` | `name` |
| `model_detected` | `agent`, `model` |
| `tool_call_start` | `agent`, `tool`, `args`, `preview?`, `inputData?` |
| `tool_call_end` | `agent`, `tool`, `result`, `tokenCost?`, `isError?`, `errorMessage?`, `discovery?` |
| `subagent_dispatch` | `parent`, `child`, `task` |
| `subagent_return` | `parent`, `child`, `summary` |
| `message` | `agent`, `role` (`assistant`\|`thinking`\|`user`), `content` |
| `context_update` | `agent`, `breakdown` |
| `permission_requested` | `agent`, `message`, `title` |

Two invariants worth transcribing:

1. **Agent identity is the agent *name*, not an ID.** `state.agents` is keyed
   by name throughout (`handle-agent-events.ts:26`). This is why naming is
   contentious and why the hook server defers to the transcript parser.
2. **Spawning a subagent is always two events.** `emitSubagentSpawn()`
   (`protocol.ts:125-142`) emits `subagent_dispatch` (the flying particle) *then*
   `agent_spawn` (the node). Never one without the other.

## 1.4 The reducer

`web/hooks/simulation/process-event.ts` is a pure-ish reducer:
`(SimulationEvent, SimulationState) → SimulationState`. Collections are copied
shallowly, handlers mutate the copy, and unchanged maps are returned by
reference to avoid downstream React re-renders (`mapsEqual`).

State it accumulates:

```
agents          Map<name, Agent>
toolCalls       Map<id, ToolCallNode>
edges           Edge[]                    // parent-child | tool
particles       Particle[]                // transient animation only
discoveries     Discovery[]
fileAttention   Map<path, FileAttention>
timelineEntries Map<agentName, TimelineEntry>
conversations   Map<agentName, ConversationMessage[]>
```

Notable handler behaviour:

- **`agent_spawn` on an existing agent reactivates it** rather than replacing —
  accumulated stats survive a session resuming after an idle gap.
- **Sibling placement** uses the largest angular gap between existing children
  (`handle-agent-events.ts:44-72`); the first child gets a hash-derived angle so
  layout is deterministic across runs.
- **`agent_complete` cascades to children** and force-closes their running tool
  calls (`:131-148`). Without this, an orphaned subagent spins forever.
- **`tool_call_end` matches by `agent + tool + state === 'running'`**, not by
  ID. Combined with the 3 s dedup window this is how the two ingestion sources
  are reconciled — imprecise, but it means the model never needs a tool-call ID
  from the hook payload.
- **Timeline blocks are a closing sequence**: `pushTimelineBlock()` closes the
  previous open block at the current time before appending the new one. A
  timeline is therefore always gapless.

## 1.5 Derived accounting

- **Token estimation** (`token-estimator.ts`): `ceil(length / 4)`, then a
  per-tool multiplier — `Read` ×1, `Grep`/`Glob` ×`GREP_TOKEN_MULTIPLIER`,
  everything else ×`DEFAULT_TOKEN_MULTIPLIER`. An approximation, clearly.
- **Context breakdown** is accumulated in the *watcher*, not the reducer
  (`WatchedSession.contextBreakdown`), and pushed as `context_update`. Each
  transcript block adds to one of five buckets: `systemPrompt`, `userMessages`,
  `toolResults`, `reasoning`, `subagentResults`.
- **Context window size and cost rate** are resolved by regex against the model
  ID (`canvas-constants.ts:8-29, 186-192`), with a `1_000_000` fallback.
- **File attention** is updated in `handle-tool-events.ts` for `Read`/`Edit`/
  `Write` only, keyed on `inputData.file_path`.

## 1.6 Tool summarization

`tool-summarizer.ts` has two functions worth porting wholesale:

- `summarizeInput(toolName, input) → String` — one readable line per tool.
  `Bash` → the command; `Read` → last two path segments; `TodoWrite` → active
  item plus `(done/total)`; `WebFetch` → host + truncated path. Falls back to
  truncated JSON.
- `extractInputData(toolName, input) → Record?` — the structured payload the
  detail view renders (Edit old/new strings, todo arrays, Bash command +
  description).

Both handle Claude *and* Codex tool names in the same switch.

## 1.7 Rendering (documented for completeness — not being ported)

Immediate-mode Canvas 2D at 60 fps: `draw-agents`, `draw-tool-calls`,
`draw-edges`, `draw-particles`, `bloom-renderer`, plus a `render-cache` and a
`use-canvas-camera` pan/zoom. Force-directed layout syncs on graph change.
There is also an audio engine mapping events to sounds.

None of this survives a native port. It is listed so nobody budgets it as one.

---

# Part 2 — Mapping onto Dev Island

## 2.1 What is already equivalent

| Agent Flow | Dev Island | Verdict |
|---|---|---|
| `hook-server.ts` (loopback HTTP) | `BridgeServer` + `DevIslandHooks` CLI (Unix socket) | Dev Island's is better. **Do not port.** |
| `hooks-config.ts` hook registration | `ClaudeHookInstaller.swift:49-63` | Dev Island registers a **superset** — Agent Flow's 9 events plus `UserPromptSubmit`, `StopFailure`, `PermissionRequest`, `PermissionDenied`, `PreCompact`. **Nothing to add.** `PreCompact` is a bonus Agent Flow lacks: it marks where the context window was compacted, which the timeline should render as a divider. |
| `session-watcher.ts` JSONL discovery | `ClaudeTranscriptDiscovery`, `SessionDiscoveryCoordinator` | Present. Extend, don't replace. |
| `subagent-watcher.ts` `.meta.json` name resolution | `SubagentStart`/`SubagentStop` + `pendingAgentDescriptions` (`BridgeServer.swift:678-686, 916-947`) | **Dev Island's is strictly better** — it gets `agent_id` and the `Agent` tool's `description` directly, no sidecar inference, no dedup race. |
| `permission_requested` event | `PermissionRequested` + round-trip response | Dev Island can *answer*; Agent Flow only observes. |
| `processEvent()` reducer | `SessionState.apply(_:)` | Same role. Extend it. |
| Session tabs | `SessionState.sessions` | Present. |
| Codex rollout parsing | `CodexSessionTracking.swift`, `CodexAppServer.swift` | Present. |

**The entire left column above is already solved.** The port is the state model
and the views, nothing else.

## 2.2 The one structural change

Today, `BridgeServer.handleClaudeHook` receives `PreToolUse` with the full
`toolInput`, stores it in `pendingClaudeToolContexts` **keyed by permission
correlation key**, uses it to build a permission prompt, and drops it. The
`PostToolUse` result is never retained at all.

The change is to add a second, parallel consumer of the same payload:

```
DevIslandHooks CLI
        │ Unix socket
        ▼
   BridgeServer.handleClaudeHook(payload)
        │
        ├──► send(.response(...))          ← unchanged, FIRST, fail-open preserved
        │
        ├──► emit(AgentEvent...)           ← unchanged, existing island behaviour
        │
        └──► SessionRecorder.record(payload)   ← NEW
                    │
                    ▼
             SessionTrace (per session, bounded)
                    │
                    ▼
             Session Monitor window
```

`SessionRecorder` is additive and isolated. If it throws, the hook response has
already been sent.

## 2.3 New model (DevIslandCore)

Swift equivalents of the Agent Flow view model, adapted to Dev Island's
conventions (`Equatable, Codable, Sendable`, value types, reducer-owned
mutation).

```swift
// SessionTrace.swift — one per AgentSession, owned alongside it

public struct SessionTrace: Equatable, Codable, Sendable {
    public var sessionID: String
    public var startedAt: Date
    public var agents: [String: TracedAgent]      // keyed by agent name, per Agent Flow
    public var toolCalls: RingBuffer<TracedToolCall>
    public var edges: [TraceEdge]
    public var fileAttention: [String: FileAttention]
    public var messages: RingBuffer<TracedMessage>
    public var droppedToolCallCount: Int          // explicit "older entries dropped"
}

public struct TracedAgent: Equatable, Codable, Sendable {
    public var name: String
    public var parentName: String?
    public var isMain: Bool
    public var tool: AgentTool                    // reuse the existing enum
    public var model: String?
    public var state: TracedAgentState
    public var task: String?                      // the Agent tool's `description`
    public var spawnedAt: Date
    public var completedAt: Date?
    public var toolCallCount: Int
    public var contextBreakdown: ContextBreakdown
    public var timeline: [TimelineBlock]
}

public enum TracedAgentState: String, Codable, Sendable {
    case idle, thinking, toolCalling, waitingPermission, complete, error
}

public struct TracedToolCall: Equatable, Codable, Sendable, Identifiable {
    public var id: String                         // Claude's tool_use_id — see 2.4
    public var agentName: String
    public var toolName: String
    public var argsSummary: String                // summarizeInput() equivalent
    public var inputData: JSONValue?              // extractInputData() equivalent
    public var resultSummary: String?
    public var estimatedTokenCost: Int?
    public var state: ToolCallState               // running | complete | error
    public var errorMessage: String?
    public var startedAt: Date
    public var completedAt: Date?
}

public struct TimelineBlock: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var kind: Kind                         // thinking | toolCall | waitingPermission | idle | complete
    public var label: String
    public var startedAt: Date
    public var endedAt: Date?
}

public struct ContextBreakdown: Equatable, Codable, Sendable {
    public var systemPrompt: Int
    public var userMessages: Int
    public var toolResults: Int
    public var reasoning: Int
    public var subagentResults: Int
    public var total: Int { systemPrompt + userMessages + toolResults + reasoning + subagentResults }
}
```

Deliberate divergences from Agent Flow:

- **`Date`, not elapsed seconds.** Agent Flow's `time: number` is
  seconds-since-session-start because its canvas animates against a clock. Dev
  Island already timestamps every event with `Date`; keep that and compute
  elapsed at render time.
- **No `x`, `y`, `vx`, `vy`, `opacity`, `scale` in the model.** Agent Flow
  stores layout in the domain model. Keep layout in the view layer.
- **No `Particle`, no `Discovery`.** Particles are pure animation. Discoveries
  are a presentation of file-tool results already covered by `fileAttention`.
- **`RingBuffer` is explicit in the type.** Bounding is a model-level guarantee
  (PRD R2), not a UI concern.

## 2.4 Tool call identity — a correction available to us

Agent Flow matches `tool_call_end` to `tool_call_start` by
`agent + tool + running`, with a 3-second dedup window, because its hook path
and transcript path race and neither reliably carries an ID.

Dev Island has no such race — there is one ingestion path — and
`ClaudeHookPayload` already decodes `tool_use_id` (`ClaudeHooks.swift:351,395`).
**Key `TracedToolCall` by `toolUseID` and match exactly.** This removes the
dedup window, the "first running call wins" heuristic, and the class of bugs
where two concurrent `Read` calls get their results swapped.

Fallback when `toolUseID` is absent (older CLIs, some forks): synthesize
`"\(sessionID):\(toolName):\(sequenceNumber)"` and match by agent+tool as Agent
Flow does — but log it, because it means degraded fidelity.

## 2.5 Reducer placement

`SessionTrace` must not live *inside* `AgentSession` — `AgentSession` is copied
on every mutation and diffed by the island views. Embedding a 2 000-entry buffer
in it would make every notch redraw copy and compare the whole history.

It must not live inside `SessionState` either, for the same reason one level up:
`SessionState` is `Equatable`, so a `tracesByID` stored property would make
`SessionState ==` walk every trace on every comparison — exactly the cost this
section exists to avoid.

Instead, traces live in a **separate store owned by `AppModel`**, alongside
`SessionState` rather than inside it:

```swift
@MainActor @Observable
final class SessionTraceStore {
    private(set) var tracesByID: [String: SessionTrace] = [:]

    func apply(_ event: AgentEvent) { … }         // same events SessionState sees
    func trace(for sessionID: String) -> SessionTrace? { tracesByID[sessionID] }
    func drop(sessionID: String) { tracesByID[sessionID] = nil }
}
```

`AppModel` fans each `AgentEvent` to both `SessionState.apply(_:)` and
`SessionTraceStore.apply(_:)`. The notch path observes `SessionState` only and
its `Equatable` cost is unchanged. The Session Monitor observes the store, and
reads exactly one trace — the selected session's.

If a future refactor does fold traces into `SessionState`, `==` must be
hand-written to exclude them. Do not rely on the synthesized conformance.

Same goal as Agent Flow's `mapsEqual` reference-stability trick, reached by
ownership separation instead.

## 2.6 New event cases

Extend the existing `AgentEvent` enum rather than inventing a second one:

```swift
case toolCallStarted(ToolCallStarted)    // sessionID, toolUseID, agentName, toolName, input, timestamp
case toolCallEnded(ToolCallEnded)        // sessionID, toolUseID, resultSummary, tokenCost, isError, timestamp
case agentSpawned(AgentSpawned)          // sessionID, agentName, parentName, task, model, timestamp
case agentCompleted(AgentCompleted)      // sessionID, agentName, timestamp
case messageObserved(MessageObserved)    // sessionID, agentName, role, content, timestamp  (P4)
case contextUpdated(ContextUpdated)      // sessionID, agentName, breakdown, timestamp      (P3)
```

`agentSpawned` / `agentCompleted` are emitted from the *existing*
`subagentStart` / `subagentStop` handlers (`BridgeServer.swift:916-947`), which
already resolve names and maintain `activeSubagents`. This is a two-line
addition per handler, not new logic.

Note the enum is `Codable` and crosses the socket — adding cases is a wire
format change. `docs/architecture.md` already mandates versioning the event
schema; honour it.

## 2.7 Porting the summarizers

`tool-summarizer.ts` (`summarizeInput`, `extractInputData`) and
`token-estimator.ts` port almost literally into a Swift `ToolSummarizer` enum
with static methods. They are pure functions over a JSON value, they have no
dependencies, and Dev Island already has a `JSONValue` type in the hook decode
path (`case let .object(obj) = payload.toolInput`).

This is the single largest chunk of directly reusable logic. It is also the
chunk that most needs an attribution header — see §3.4.

## 2.8 The view layer

| Agent Flow | Dev Island equivalent | Approach |
|---|---|---|
| Canvas 2D + force layout | SwiftUI `Canvas` inside `TimelineView(.animation)` | Sessions have a handful of agents (a `Task` fan-out of 20 is extreme). Force-directed layout with ~20 nodes is trivial on the main thread. Only escalate to `MTKView` if profiling says so. |
| `timeline-panel.tsx` | SwiftUI `Canvas` or stacked `GeometryReader` rows | Gantt bars; straightforward. |
| `message-feed-panel.tsx`, `session-transcript-panel.tsx` | `List` + `LazyVStack` | Native virtualization; drop `use-virtual-list.ts`. |
| `file-attention-panel.tsx` | `Table` | macOS `Table` sorts for free. |
| `tool-detail-popup.tsx`, `tool-content-renderer.tsx` | `Inspector` pane | Renders `inputData` per tool kind. |
| `control-bar.tsx`, glass cards, bloom, audio | — | Drop. Use Dev Island's existing `IslandTypography` / appearance system. |

**Rendering must stop when the window closes.** `TimelineView(.animation)` keeps
ticking as long as the view exists; gate it on window visibility (PRD success
criterion).

## 2.9 Data flow, end state

```
Claude Code / Codex / …
        │ hook payload (stdin)
        ▼
DevIslandHooks CLI ──── Unix socket ────► BridgeServer
                                              │
                          ┌───────────────────┼───────────────────┐
                          ▼                   ▼                   ▼
                   send(.response)     emit(AgentEvent)    SessionRecorder
                   (fail-open, first)         │                   │
                                              ▼                   ▼
                                     SessionState.apply(_:) ──────┘
                                              │
                              ┌───────────────┴───────────────┐
                              ▼                               ▼
                        sessionsByID                     tracesByID
                              │                               │
                              ▼                               ▼
                     Notch / island panel            Session Monitor window
                        (unchanged)                          (new)

     ~/.claude/projects/**/*.jsonl ──► TranscriptTailer ──► messageObserved   (P4)
                                                             contextUpdated
```

---

# Part 3 — Implementation plan

## 3.1 Slices

Each slice is one feature branch and one PR, per `AGENTS.md`.

| # | Branch | Content | Verification |
|---|---|---|---|
| 1 | `feat/session-trace-model` | `SessionTrace`, `TracedAgent`, `TracedToolCall`, `TimelineBlock`, `ContextBreakdown`, `RingBuffer`. Pure types + unit tests. No wiring. | Unit tests on the reducer and the ring buffer's drop accounting |
| 2 | `feat/tool-summarizer` | Port `summarizeInput` / `extractInputData` / `estimateTokenCost` to Swift. | Table-driven tests over recorded payloads for every supported tool |
| 3 | `feat/session-recorder` | New `AgentEvent` cases; emit from `preToolUse`/`postToolUse`/`postToolUseFailure`/`subagentStart`/`subagentStop`; `SessionState.tracesByID`. | Harness run (`scripts/harness.sh smoke`) asserting a trace is built from a scripted session |
| 4 | `feat/session-monitor-window` | The window: agent graph, timeline, tool list, detail inspector, session picker. | Manual verification against `Dev Island Dev.app` with a real session |
| 5 | `feat/context-accounting` | Context breakdown, cost estimate, file attention, island activity strip. | Unit tests + manual |
| 6 | `feat/transcript-tailer` | Tail `ClaudeSessionMetadata.transcriptPath`; emit `messageObserved` / `contextUpdated`. | Unit tests over a captured JSONL fixture |

Slices 1–4 deliver PRD phases P1–P2. Slice 5 is P3, slice 6 is P4.

## 3.2 Rejected alternatives

- **Embed Agent Flow's webview in a `WKWebView`.** Fast to ship; wrong product.
  It would put an Electron-shaped hole in an app whose stated principle is
  "native macOS, not a web wrapper" (`docs/product.md`), and it would ship
  someone else's trademarked UI.
- **Run `npx agent-flow-app` as a helper process and link to it.** No
  integration with Dev Island's session identity, permission round-trip, or
  jump-back — and it registers a *second* set of hooks that would collide with
  Dev Island's in `~/.claude/settings.json`.
- **Store the trace inside `AgentSession`.** Rejected in §2.5 — makes every notch
  redraw copy the history.
- **Reuse Agent Flow's `agent + tool` matching.** Rejected in §2.4 — we have
  `tool_use_id` and no ingestion race, so exact matching is strictly available.

## 3.3 Compatibility notes

- **Hook set is unchanged.** No installer migration, no re-prompt for users.
- **Wire format changes** (new `AgentEvent` cases). An older `DevIslandHooks`
  binary against a newer app is fine — it only sends payloads. A newer CLI
  against an older app is not a supported combination and already is not today.
- **Non-Claude agents**: `subagentStart`/`subagentStop` and `tool_use_id` are
  Claude-family concepts. Gemini, OpenCode and Cursor will produce a
  single-agent trace with tool calls where their payloads allow, and an empty
  graph otherwise. Degrade, don't gate.
- **Codex specifically**: its managed hook set is deliberately low-noise —
  `SessionStart`, `UserPromptSubmit`, `Stop` by default, with `PreToolUse` /
  `PostToolUse` parseable but not installed (`docs/product.md`, and `AGENTS.md`:
  "keep managed Codex CLI hooks low-noise"). A Codex trace built from hooks
  alone is therefore near-empty, and widening the hook set is explicitly out of
  bounds. Codex tool-level tracing must come from the rollout stream instead —
  `Sources/DevIslandCore/CodexSessionTracking.swift` already tails it, and it
  carries authoritative token counts rather than estimates. **PRD R16 is a
  `CodexSessionTracking` extension, not a hook change.**

## 3.4 Licensing and attribution

- Agent Flow is **Apache-2.0**; Dev Island is **GPL-3.0**. Apache-2.0 code may
  be incorporated into a GPL-3.0 work (one-way compatible); the combined work
  remains GPL-3.0.
- Any Swift file whose logic is a translation of an Agent Flow source file must
  carry a header naming the origin file and its licence — at minimum the
  `ToolSummarizer` port (§2.7) and the reducer semantics in §1.4.
- Apache-2.0 §4 requires retaining the `NOTICE` content if present, and §6
  grants **no trademark rights**. "Agent Flow" and its logos are trademarked
  (`agent-flow/TRADEMARK.md`). Use "Session Monitor" or another Dev Island name;
  do not reuse the visual identity.

## 3.5 Open items carried from the PRD

1. Persistence across app restart — assumed out of scope for v1.
2. Standalone window vs. sheet — assumed standalone window.
3. One window with a session picker vs. one window per session — assumed one
   window with a picker.

---

## References

- Agent Flow: `~/DevApps/AgentsTools/agent-flow` — protocol `extension/src/protocol.ts`,
  view model `web/lib/agent-types.ts`, reducer `web/hooks/simulation/`,
  summarizers `extension/src/tool-summarizer.ts`
- Dev Island: `docs/architecture.md`, `docs/hooks.md`, `docs/product.md`
- `Sources/DevIslandCore/BridgeServer.swift`, `SessionState.swift`,
  `ClaudeHooks.swift`, `ClaudeHookInstaller.swift`
