# State machine domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [graph.md](../graph/graph.md), [julia.md](../julia/julia.md)

`ProjecturedFSM` holds extended state machines: named states with entry code, transitions on events, timers or conditions, and variables, with all code as embedded Julia documents. A component prints as a notation, draws as a live diagram, and generates a complete Julia module. This document says how the three work, which contract the generated code keeps with a runtime that the embedder supplies, and what the domain leaves out.

<img width="396" alt="State machine example" src="../../../asset/image/example/fsm.png">

## How it works

### The documents

| Document | What it holds |
| --- | --- |
| `FsmComponent` | the unit of code generation: `variables`, `timers`, `events`, `machines`, `usings`, `helpers`, and `supertype` |
| `FsmMachine` | `name`, the `initial` state, `states`, and the `on_unhandled` policy, `:error` or `:ignore` |
| `FsmState` | `name`, `entry` code, and the outgoing `transitions` in priority order |
| `FsmTransition` | `trigger`, `guard`, `action`, `target` |
| `FsmVariable` | `name`, `type`, `default`: a variable of the extended state |
| `FsmTimer`, `FsmEvent` | `name`: a timer handle of the host, a symbolic event |

Each piece of code is a `JuliaDocument` subtree: an entry, a guard, an action, the type and default of a variable, and each item of `usings` and `helpers`. No code is stored as a string. The notation edits it as Julia, and the generator puts it into the output unchanged.

`trigger`, `target` and `initial` hold their referent **by identity**, as `GraphEdge` holds its vertices. So a rename of a state or an event changes every place that shows it. `supertype` is source text that the domain never reads: the generated host struct subtypes it, for a host system that needs a bound of its own.

| Transition | Means |
| --- | --- |
| `trigger = event, target = S` | an event transition to `S` |
| `trigger = timer, target = S` | a timeout transition to `S` |
| `trigger = nothing` | a **condition-only** transition, tested on each dispatch and on each pass of re-evaluation |
| `target = nothing` | a **stay**: consume the trigger and run the action; no change of state, no entry |
| `target = nothing`, `action = nothing` | an **ignore**: consume the trigger and do nothing |
| `target` is the containing state | a real self-transition: the entry runs again |

The transitions of a state are tried in document order, and the first with a matching trigger and a true guard fires. Two guarded transitions on one event give a target that depends on the guard.

### The notation

`FsmToSyntax()` is the main edit surface. It copies the dispatch table of `JuliaToSyntax()` and adds the rules of this domain, so the embedded code prints through the same recursion, as in the formula domain. The toggle example prints as:

```
component Toggle
  variable blinks::Int = 0
  timer blink_timer
  event PRESSED
  machine Toggle initial OFF
    state OFF
      on PRESSED -> ON
    state ON
      entry / m.blinks = m.blinks + 1
      on PRESSED stay / m.blinks = m.blinks + 1
      on timeout(blink_timer) when m.blinks > 3 -> OFF
```

A transition line is `[on EVENT | on timeout(TIMER)] [when GUARD] (-> TARGET | stay | ignore) [/ ACTION]`. The action comes last because it is the one part that can have many lines: a block action prints as indented lines below its transition. A machine with `on_unhandled = :ignore` prints `ignoring unhandled` after its initial state.

The trigger, the target and the initial state print as a leaf that reads the name of the referent. The rule never recurses into the referent, because a target printed in full would contain its own transitions, and a self-loop would not end. These names and the keywords are text that the projection adds. The template names a caret on them by the rule's own introduced step, which holds the path of the part in the rule's output, and the forward map gives that path back.

`,` on a machine inserts a state, and `,` on a state inserts a transition. The Insert key and the insertion buffer come from `@domain Fsm`; see [domain-anatomy.md](../../../design/domain-anatomy.md#the-placeholder-and-the-insertion).

### The diagram

```
FsmMachine ──FsmToFsmDiagram──▶ FsmDiagram ──FsmDiagramToGraph──▶ GraphGraph ──the graph stages──▶ GraphicsCanvas
```

`FsmToFsmDiagram` wraps the machine in an `FsmDiagram` with three live cells: `live_state`, the 1-based index of the current state, `live_transition`, the 1-based index of the last transition in the flat order of `get_fsm_transitions`, and `transition_count`. `0` means none. The diagram is presentation state and is never saved. The stage builds it once and keeps its identity, so a driver can write the same three cells for a whole run.

`FsmDiagramToGraph` builds a `GraphGraph`: one vertex for each state, with the `FsmState` itself as content, and one directed edge for each transition that has a target, with the `FsmTransition` itself as label. A stay has no edge. The two highlights of the graph are computed cells that turn `live_state` and `live_transition` into the vertex and the edge. The graph stages then draw everything; see [graph.md](../graph/graph.md#the-highlight). A new live state repaints the ring and runs no layout.

The labels use compact rules: `FsmStateToSyntaxLabel` prints the name of a state, and `FsmTransitionToSyntaxLabel` prints the trigger, the guard and the action. `FsmToSyntaxLabel` builds the table of the two, with the full notation as its fallback. A click on a box selects the real state.

### The generated code

`generate_component(component)` returns a `JuliaDocument`, `generate_component_text` returns the source, and `export_component` writes a file. For a component `Foo` the module `FooFsm` holds:

- the `usings` of the component;
- a constant for each state of each machine, such as `MAC_S_IDLE`, and a tuple of state names for each machine. **The state values are 0-based document order.** They go into recorded statistics and are compared with a reference implementation, so the numbers are part of the contract;
- a constant for each event, from 1, and one for each timer after them. `0` means no event;
- the host struct `FooState`: one `Fsm` for each machine, one `TimerHandle` for each timer, one field for each variable; and a constructor with no arguments that fills in the initial states and the declared defaults;
- one dispatch function for each machine, `<machine>_dispatch!(ctx, m, event::Int32, payload)`, in straight-line branches;
- one expiry function for each timer, `expire_<timer>!(ctx, m)`;
- the `helpers`, unchanged.

The generated code and the actions in it call names that the domain does not define: `Fsm`, `TimerHandle`, `FSM_CASCADE_LIMIT`, `fsm_state`, `fsm_enter!`, `fsm_leave!`, `fsm_goto!`, `fsm_defer!`, `fsm_drain!`, `fsm_cascade_error` and `fsm_unhandled_error`. The embedder supplies a runtime module that defines them. `test/domain/fsm/projection/FsmToJuliaCodeTest.jl` holds a small stand-in, `ProbeRuntime`, and runs generated code against it.

### The execution contract

The generated dispatch and the runtime together keep this contract. It follows the C++ `FSMA` engine that the three reference machines, Ethernet CSMA MAC, PLCA and TCP, are built on.

1. **Event pass.** The candidates are the transitions of the current state, in order: the ones triggered by this event, and every condition-only one. The first with a true guard fires. A stay or an ignore consumes the event without a change of state.
2. **Landing and re-evaluation.** A transition that fires runs its action, then calls `fsm_goto!` with the new state and the flat index of the transition, then runs the entry of the target with `prev` and `ev` bound. Then passes of re-evaluation run, with only the condition-only transitions of the new state as candidates, because the event is spent. They repeat until nothing fires. More than `FSM_CASCADE_LIMIT` passes is an error. A stay is followed by passes of re-evaluation in the same way.
3. **Unhandled.** If an event pass consumed nothing, `:error` calls `fsm_unhandled_error`, which throws and names the state and the event, and `:ignore` returns. CSMA MAC and PLCA data use `:error` as an exhaustiveness check; in TCP an unlisted pair is legal.
4. **Deferred drain.** An action pushes a call that leaves the machine, such as a dispatch to a sibling machine, with `fsm_defer!`. At the end of the dispatch `fsm_drain!` copies the queue, clears it and runs the copy. So a drained call can dispatch this machine or a sibling again and does not take a pending call of the sibling. A dispatch into a machine that is inside its own cascade is an error; it is legal again during the drain.
5. **Recording.** `fsm_goto!` receives the flat index of the transition. The runtime counts the transitions, records the last one and can call an `on_transition` hook. The same flat index is `FsmDiagram.live_transition`.
6. **Startup.** The entry of the initial state does not run when the host is built. The host starts a machine with a dispatch of event `0`. In `FSMA` a state set outside a dispatch runs no entry, and the entry of PLCA `DS_IDLE` would otherwise send a false dispatch at time zero.

Embedded code sees `ctx`, the schedule context, `m`, the host struct, and `payload`, which is `nothing` for timers and conditions. An entry also sees `prev` and `ev`. A guard must have no side effects, except a call of `is_scheduled`; nothing checks this.

A timer works in two ways, and the reference machines use both: as a timeout trigger, and as a guard that polls `is_scheduled(m.t)`. So `expire_<timer>!` dispatches the timeout event to each machine that has the timer as a trigger, and a dispatch of event `0` to each other machine that has condition-only transitions.

### The theme

`FsmTheme` holds the text of a keyword, a name, a reference and the chrome, and the name of a state and the trigger of a transition in a diagram. Each value has the default that the slice draws with no
appearance. A projection holds its styles as fields, and no theme; nothing in it scales or asks whether a theme is scaled. `FsmToSyntax(; theme, julia_theme, syntax_theme)` and `FsmToSyntaxLabel(; theme, julia_theme, syntax_theme)` give each projection the style of its role with `get_fsm_style`, from `theme`, a `FsmTheme` scaled or not, or the
default styles for `nothing`. The Julia code of a guard or an action takes `julia_theme`. The FSM has no view in this repository's application, so a builder that has the themes passes them.

## How it fits

`ProjecturedFSM` depends on `ProjecturedJulia`, because the code is Julia documents, and on `ProjecturedGraph`, because the diagram is a graph. It also depends on the kernel and the platform. No package depends on it. `process` is its complement; see [process.md](../process/process.md).

It has no `__init__` and registers nothing: no natural row, no file type, no parser. A caller builds the notation chain or the diagram chain.

## Design decisions

- **The code is Julia documents, not strings.** What the author sees in the notation is exactly what runs, with no parse and no rewrite between them. See [plan/done/state-machine-domain.md](../../../../plan/done/state-machine-domain.md).
- **The generator is a function, not a projection.** The component is the source and the `.jl` file is output; a hand-edited file does not go back into the machine. The output is a document, so the editor can show it through the Julia chain.
- **The diagram reuses the graph domain.** The domain adds a stage that builds a `GraphGraph` and two label rules, and no code that draws. See [plan/done/state-machine-domain.md](../../../../plan/done/state-machine-domain.md).
- **The live position is on the diagram, and it bypasses the layout.** A running machine is not part of the machine, and a layout for each transition would cost too much.
- **The deferred queue drains a copy.** A live drain of one shared queue lets a nested dispatch take the pending call of a sibling, as PLCA `COMMIT_TO` shows. This follows `executeDelayedActions` of `FSMA`.
- **A stay is followed by re-evaluation, as a transition is.** This is simpler than the partial fall-through of `FSMA`, and no reference machine mixes stays with condition-only transitions in one state.
- **The classification of events stays outside the machine.** The TCP classifier keeps state, can drop input and can change the event it makes, so it is plain Julia among `helpers`. The transition table stays small and shaped like a diagram.

## Usage

```julia
pressed = FsmEvent("PRESSED")
off, on = FsmState("OFF"), FsmState("ON"; entry = parse_julia("m.blinks = m.blinks + 1"))
push!(off.transitions, FsmTransition(trigger = pressed, target = on))
push!(on.transitions, FsmTransition(trigger = pressed, target = off))
component = FsmComponent("Toggle";
    variables = [FsmVariable("blinks"; type = parse_julia("Int"), default = parse_julia("0"))],
    events = [pressed], machines = [FsmMachine("Toggle"; initial = off, states = [off, on])])
print(generate_component_text(component))
```

- Examples: `fsm`, the TCP connection machine; `fsm_toggle`; and `fsm_diagram`, the toggle machine as a diagram, in `example/domain/fsm/`. `make_fsm_diagram_projection_example(; engine)` builds the diagram chain. The atomic catalog has an entry for each of the seven content types.
- Test: `test_fsm()` runs the layering guard, `test_fsm_document()`, `test_fsm_diagram()`, `test_fsm_to_julia_code()` and `test_fsm_to_syntax()`.

## Limits

- No gesture sets `trigger`, `target` or `initial`, and no reader turns a typed name into a referent. `find_state`, `find_event` and `find_timer` resolve a name, but no code calls them. A caller sets the references in code.
- No code in this repository writes the live fields of `FsmDiagram` apart from the tests. A simulation that runs the generated code must write them.
- A self-loop draws as a line of zero length and does not show, and an edge is not clickable. Both come from [graph.md](../graph/graph.md#limits).
- Not modeled: exit actions, hierarchical states and orthogonal regions. None of the three reference machines needs them.
