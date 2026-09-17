# The `fsm` domain — extended state machines

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

A state machine as a first-class document: named states with entry actions,
guarded event- and condition-driven transitions, first-class timers, extended
state variables, and embedded Julia code. The slice exists to express real
protocol machines — Ethernet CSMA MAC, PLCA (control + data), TCP — well enough
that a component projects to complete, runnable Julia code.

Slice: `source/fsm/`. Design plan and its research grounding:
`plan/pending/state-machine-domain.md`.

## Document types

| Type | Holds |
| --- | --- |
| `FsmComponent` | the unit of code generation: `variables`, `timers`, `events`, `machines`, `usings`, `helpers` |
| `FsmMachine` | `name`, `initial` state, `states`, `on_unhandled` policy |
| `FsmState` | `name`, `entry` code, outgoing `transitions` in priority order |
| `FsmTransition` | `trigger`, `guard`, `action`, `target` |
| `FsmVariable` | `name`, `type`, `default` — an extended-state variable |
| `FsmTimer` | `name` — becomes a timer handle on the generated host struct |
| `FsmEvent` | `name` — a symbolic event declaration |

Embedded code (`entry`, `guard`, `action`, a variable's `type`/`default`, and
every item of `helpers`/`usings`) is a `JuliaDocument` subtree — real structured
Julia, edited natively and spliced verbatim into generated code. Nothing is
stored as an opaque source string.

`trigger`, `target` and `initial` hold their referent **by identity** (the
`GraphEdge.source/target` model), so renaming a state or event never dangles a
reference. Known limitation: `copy_document` has no alias table, so the paste
path re-resolves these by name within the pasted subtree.

## Transition vocabulary

| Written as | Means |
| --- | --- |
| `trigger = event, target = S` | event transition to `S` |
| `trigger = timer, target = S` | timeout transition to `S` |
| `trigger = nothing` | **condition-only** — re-checked on every dispatch and on re-evaluation passes |
| `target = nothing` | **stay** — consume the trigger, run the action, no state change, no entry re-run |
| `target = nothing`, `action = nothing` | **ignore** — consume silently |
| `target === the containing state` | true self-transition — entry re-runs |

Transitions are tried in document order; the first whose trigger matches and
whose guard passes wins. Two guarded transitions on the same event is how a
guard-dependent *target* is expressed (TCP's `state->active ? CLOSED : LISTEN`).

## Execution semantics (the contract)

This is what the code generator emits and what the runtime support module
(`Fsm.jl`, which an embedder supplies) upholds. It is a faithful
distillation of INET's `FSMA.h` engine, which all three reference machines are
built on.

One dispatch is `dispatch!(ctx, host, machine, event, payload)`; `event` may be
`nothing`, which is a pure re-evaluation run — how condition-only machines are
driven.

1. **Event pass.** Candidates are the current state's transitions in document
   order: those triggered by this event, plus every condition-only transition.
   The first whose guard passes wins. Stays and ignores consume the event
   without a state change.
2. **Landing and re-evaluation.** A winning transition runs its action, then
   moves to the target and runs the target's `entry` (with `prev` and `ev`
   bound). Then re-evaluation passes run, in which only condition-only
   transitions of the landed state are candidates — the event is spent (in FSMA
   an event transition can never fire on a re-evaluation pass). Repeat until no
   transition fires. An iteration cap (default 32) throws on a runaway cascade.
   A **stay** is followed by re-evaluation passes exactly like a winning
   transition — a deliberate, uniform simplification of FSMA's partial
   fall-through after a stay; no target machine mixes stays with condition-only
   transitions in one state, so nothing depends on the difference.
3. **Unhandled.** If the pass was an event pass and nothing consumed the event,
   apply `machine.on_unhandled`: `:error` throws naming state and event
   (the exhaustiveness check CSMA MAC and PLCA data rely on), `:ignore` returns
   (TCP, where unlisted pairs are legal).
4. **Deferred drain.** Each machine owns a deferred queue; actions push onto it
   with `fsm_defer!` (calls that leave the machine: a sibling machine's
   dispatch, a PHY/MAC interface call). At the end of the dispatch the queue is
   **snapshot-drained** — copy, clear, then run — as FSMA's
   `executeDelayedActions` does. A drained closure may synchronously re-enter
   `dispatch!` on this or a sibling machine, which drains that machine's own
   fresh queue. A single shared queue drained live would let a nested dispatch
   steal a sibling's pending injection (PLCA's `COMMIT_TO`). Re-entrancy rule:
   dispatching a machine that is currently inside its own cascade is an error
   (FSMA's `busy` assert); it is legal again during that machine's drain.
5. **Recording.** Every state change bumps `transition_count`, records
   `last_transition`, updates `state`, and calls the optional `on_transition`
   hook (statistics emit; also what the live diagram view reads).
6. **Startup.** The initial state's `entry` does *not* run when the machine is
   constructed — faithful to FSMA, where a state installed outside a dispatch
   never runs its entry (PLCA's `DS_IDLE` entry has side effects that would
   inject a spurious cross-machine dispatch at t=0). The host kicks the machine
   explicitly with an event-less dispatch.

**Timers are usable two ways**, and both occur in the reference machines:

- as a **timeout trigger** on a transition (CSMA MAC, PLCA data);
- as a **pollable guard predicate** `is_scheduled(m.t)` — PLCA control's five
  timers appear in no trigger at all; its transitions poll expiry in guards, and
  an expiry merely re-runs the machine event-lessly, possibly firing much later
  when another condition (`!CRS`) also becomes true.

Codegen's expiry routing follows from this: for each timer, the generated
schedule callback dispatches a timeout event to every machine that names the
timer as a trigger, **and** an event-less re-evaluation poke to the component's
condition-only machines — mirroring INET's `handleSelfMessage`, which runs the
control FSM on every self-message and event-dispatches only the data timers.

**Bindings in embedded code**: `ctx` (the schedule context), `m` (the generated
host struct — every variable and timer is one of its fields), `payload` (the
event payload, `nothing` for timers and conditions), and in `entry`
additionally `prev` and `ev`. Guards are side-effect-free by convention (not
enforced), apart from the sanctioned `is_scheduled` reads.

## What is not modeled

Event *classification* — turning a raw packet or segment into a symbolic event —
is deliberately outside the machine. TCP shows why: the classifier is stateful,
may swallow input, and may escalate or downgrade the event it produces. It is
plain Julia among the component's `helpers`, which is exactly what keeps the
transition table small and diagram-shaped.

Also out, by design: exit actions, hierarchical/composite states, and orthogonal
regions. None of the three reference machines needs them (CSMA models
receive-while-transmitting concurrency with per-state stays; TCP has entry
actions only).
