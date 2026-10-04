# Process domain

> **Kind:** design · **Status:** current · **Stands on:** [domain-anatomy.md](../../../design/domain-anatomy.md), [graph.md](../graph/graph.md), [fsm.md](../fsm/fsm.md), [julia.md](../julia/julia.md)

`ProjecturedProcess` holds an algorithm as a structured flowchart: steps, decisions, loops and jumps that nest and run to completion. A process prints as a notation, draws as a flowchart, becomes a Julia function, and runs under a debugger in the editor. This document says how the tree gives the flowchart, how realized code reports its position, and how the debugger keeps the threads apart.

## How it works

### Process or state machine

The two domains are complements:

| | `fsm` | `process` |
| --- | --- | --- |
| a node is | a **state**, where control waits | a **step**, which control passes through |
| an edge is | a transition: `trigger [guard] / action` | "next", with a label only out of a decision |
| what moves it on | an external event or a timeout | the end of the step before it |
| where the Julia is | on the edges, and in the entry of a state | in the nodes: the action, the condition |
| lifetime | long, reactive | starts, runs, ends |
| shape | a graph: any state can target any state | a tree: the graph comes from the nesting |

A process that must wait belongs inside a state machine: an `FsmState.entry` or an `FsmTransition.action` is where a process body fits.

### The documents

| Document | What it holds |
| --- | --- |
| `ProcessModel` | the unit of realization: `name`, `parameters`, `body` |
| `ProcessSequence` | `steps`; every body is one |
| `ProcessStep` | `description`, the prose, and `action`, the code; one of them can be absent, not both |
| `ProcessDecision` | `condition`, `then_branch`, `else_branch` |
| `ProcessWhile` | `condition`, `body`: a loop that tests first |
| `ProcessForeach` | `variable`, `iterable`, `body` |
| `ProcessBreak`, `ProcessContinue`, `ProcessReturn` | the three jumps; a return has an optional `value` |

The code in a process is `JuliaDocument` subtrees: an action, a condition, the variable and iterable of a loop, the parameters. `process_children` returns only the structural children, so nothing in the domain walks into the Julia.

Each node shape has a Julia counterpart with the same fields: `ProcessDecision` and `JuliaIf`, `ProcessWhile` and `JuliaWhile`, `ProcessForeach` and `JuliaFor`, `ProcessSequence` and `JuliaBlock`. So realization is a walk of one node to one node, not a translation.

**Nothing is held by identity.** The edges of the flowchart come from the nesting and are not stored, so a subtree copies as a plain tree. A body field that is `nothing` is an empty body, and `get_body_steps` reads both forms. Only `else_branch` has a different meaning for an absent branch, `nothing`, and an empty one.

### Refinement

A step with a `description` and no `action` is **unrefined**: a box that says what happens and not yet how. This is why the domain exists, and why it is not a flowchart view of Julia function bodies. `get_unrefined_nodes(model)` lists the steps with no action, the decisions and `while` loops with no condition, the `foreach` loops with no variable or iterable, and the placeholders. `is_executable(model)` is true when that list is empty. An unrefined node realizes to `error("unrefined …")`, so a process can not skip its unwritten steps without a sign.

### The position vocabulary

`process_nodes(model)` flattens the tree in document order: a node before its children, the children left to right. **The 1-based index of a node in that list is the one position vocabulary of the domain.** Realized code reports it, a breakpoint names it, and both views turn it back into a node with `find_node_at_index`; `get_node_index` goes the other way. Every node has an index, sequences and placeholders too, so a document that is being edited has the same numbers as its code. A structural edit renumbers every node after it; see the staleness below.

### The notation

`ProcessToSyntax(; session)` is the main edit surface. It copies the dispatch table of `JuliaToSyntax()`, as `FsmToSyntax` does, and has no `end`: a body is a run of indented lines.

```
process transmit(medium, payload, max_attempts)
  step "prepare" / frame = encode(payload)
  step / attempts = 0
  while true
    if carrier_free(medium)
      step / transmit!(medium, frame)
      return :sent
    if attempts >= max_attempts
      break
    step "wait a binary exponential backoff"
    step / attempts = attempts + 1
  return :failed
```

A line is `process NAME(PARAM, …)`, `step ["DESCRIPTION"] [/ ACTION]`, `if CONDITION` with an optional `else`, `while CONDITION`, `for VAR in ITERABLE`, or `break`, `continue` or `return [VALUE]`. The Julia keywords keep their Julia meaning and colour; only `process` and `step` are new. An unrefined condition, variable or iterable prints a muted `<condition>`, `<variable>` or `<iterable>` marker, so a caret has a place to go. `,` on a sequence inserts a step.

### The flowchart

```
ProcessModel ──ProcessToProcessDiagram──▶ ProcessDiagram ──ProcessDiagramToGraph──▶ GraphGraph ──the graph stages──▶ GraphicsCanvas
```

`ProcessToProcessDiagram` wraps the model in a `ProcessDiagram`, which has the `model` and a `session`. The stage builds it once and keeps its identity, so a driver can write its session for a whole run.

`ProcessDiagramToGraph` walks the tree twice: the first pass makes the vertices in document order, and the second adds the edges. Each step, decision, loop header and jump becomes a vertex whose content is the node itself, so a click on a box selects the real node; see [graph.md](../graph/graph.md#selection-and-clicks). A sequence gets no box, because the picture shows structure as edges. The start and stop ovals, `ProcessTerminal`, and the arrow captions, `ProcessEdgeLabel`, are presentation documents with no node behind them. The edges follow the usual construction for structured control flow:

| Node | Edges |
| --- | --- |
| sequence | each node to the next; the last to the successor of the sequence |
| decision | `yes` to the first node of the then branch, `no` to the else branch, or to the successor when a branch is empty or absent; **no merge vertex** |
| `while` | `yes` into the body, `no` to the successor; the end of the body goes back to the header |
| `foreach` | the same two exits, with the labels `next` and `done` |
| `break`, `continue`, `return` | to the exit of the loop, to its header, to the stop oval |

The highlights of the graph follow the session: the current node gets a ring, and the edge from the previous node to the current one is drawn again. The runtime reports only node indices, and the stage finds the edge from the pair; see [graph.md](../graph/graph.md#the-highlight).

The example names `make_deferred_layout_engine(orthogonal = true)`. With `ProjecturedAdaptagrams` loaded, libcola places the boxes and libavoid draws right-angled routes that avoid the boxes. Without it, `FruchtermanReingoldLayout` places the flowchart and draws straight lines. No engine uses the reading direction of a flowchart, so the picture does not always run from top to bottom.

### Realization

`realize_process(model; instrumentation)` returns a `JuliaFunction`, `realize_process_text` returns the source, and `export_process` writes a file. As with the state machine generator, this is a function and not a projection: the process is the source and the `.jl` file is output.

| `instrumentation` | Emits for each node | Use |
| --- | --- | --- |
| `:none` | nothing | the code to ship |
| `:position` | `process_at!(trace, i)` | the debugger |
| `:locals` | `process_at!(trace, i, (; x, y))` | the position and the variables in scope |

A probe is **one statement in statement position**, before what the node does. It never rewrites the node, so an instrumented function behaves as the plain one does; a test runs both and compares. An instrumented function has one more parameter, `trace = nothing`, so it still runs with the arguments of the process alone. `:locals` reports the parameters and the variables assigned so far, but not a variable of a loop that has ended, because Julia gives a loop its own scope. A loop has two probes: one before it, and one as the first statement of its body. The last test, which ends the loop, has no probe.

### The probe protocol

Realized code depends only on these names, so it runs outside the editor. `ProcessRuntime.jl` implements them, and an embedder can supply its own, as it supplies the runtime of the state machine domain.

1. `process_at!(trace, index)` and `process_at!(trace, index, locals)` record that the code reached node `index`.
2. `process_at!(::Nothing, …)` does nothing, so an instrumented function runs at full speed with no debugger.
3. A probe sets `previous` to the old `node`, sets `node`, counts the step, stores `locals` and calls the `on_step` hook. Then, if the mode is `:step` or `:pause`, or the node has a breakpoint, it blocks until the debugger resumes it.
4. The probe blocks the **calling task**. `start_process` runs a process on its own task. A process realized into a simulation must use `:none`, or the mode `:run` with no breakpoints, or it stops the simulation too.
5. The mode `:stop` throws `ProcessStoppedException`. The runner catches it, and no other code must.

### Debugging in the editor

The debugger has three parts, and an embedder that runs realized code in its own host uses only the first:

- **`ProcessTrace`** is plain mutable Julia, with no cells and no documents. The task of the process writes it.
- **`ProcessDebugSession`** is a document of live view state that is never saved: `status`, `node` and `previous`, the same two as documents in `current` and `previous_document`, `step_count`, `breakpoints` as nodes held by identity, `locals`, `node_count` and `command`.
- **`sync_process_debug!(session, trace, model)`** is the one bridge. In one call it sends the breakpoints and the pending `command` down to the trace, and brings the position and the status up to the session.

**Call the bridge from the refresh hook of the editor, never from a cell.** It writes document cells, and the threads stay safe without locks only because the task of the editor is the one writer of cells. A command then takes effect within one refresh.

Both views read the session. The flowchart draws the ring and the edge. The notation draws the keyword of the current node in the live colour, and the keyword of a node with a breakpoint in another colour. It changes only the style of a keyword that it prints anyway, so the live position never moves the caret of a person who types.

**Staleness.** A session records `node_count` when the code is realized. When the tree has a different count, the bridge sets `status = :stale` and clears the position, and both views draw no highlight: a wrong box that looks right is worse than none. An edit of an embedded Julia expression renumbers nothing, so the node count is enough as a stamp.

### The theme

`ProcessTheme` holds the text of a keyword, a name, an action, the chrome, the current step and a breakpoint, and the label of a terminal in a diagram. Each value has the default that the slice draws with no
appearance. A projection holds its styles as fields, and no theme; nothing in it scales or asks whether a theme is scaled. `ProcessToSyntax(; session, theme, julia_theme, syntax_theme)` and `ProcessToSyntaxLabel` give each projection the style of its role with `get_process_style`, from `theme`, a `ProcessTheme` scaled or not, or the default styles for `nothing`. The Julia code of a step takes `julia_theme`. Process has no view in this repository's application, so a builder that has the themes passes them.

## How it fits

`ProjecturedProcess` depends on the same packages as `ProjecturedFSM`: `ProjecturedJulia` for the code, `ProjecturedGraph` for the flowchart, and the kernel and the platform. The two domains do not depend on each other. No package depends on it.

It has no `__init__` and registers nothing: no natural row, no file type, no parser. A caller builds the notation chain or the flowchart chain.

## Design decisions

- **A tree, not a list of nodes and edges.** The flowchart comes from the nesting, so a copy needs no table of aliases, and the domain has no identity references. See [plan/done/process-domain.md](../../../../plan/done/process-domain.md).
- **The same fields as the Julia control flow.** Realization is then a walk from node to node. See [plan/done/process-domain.md](../../../../plan/done/process-domain.md).
- **An unrefined node realizes to an error.** A process that skipped its unwritten steps would not do what it shows.
- **A probe is one statement, never a rewrite.** The debugger must not change what the program does, and a test compares the two.
- **One bridge, from the refresh hook.** One writer of cells means no locks, at the cost of one refresh of latency.
- **Breakpoints are nodes in the session, not fields of a step.** A breakpoint is debug state, not content, and a node survives an edit that renumbers the tree.
- **Not modeled on purpose.** Waiting is the job of `fsm`. There is no fork and no join: one token runs to the end. A call of another process is a step with a Julia call, because a `ProcessCall` node would bring back identity references. See [plan/done/process-domain.md](../../../../plan/done/process-domain.md).

## Usage

```julia
model = ProcessModel("drain"; parameters = [parse_julia("queue")],
    body = ProcessSequence([
        ProcessForeach(parse_julia("item"), parse_julia("queue");
            body = ProcessSequence([ProcessStep("show it"; action = parse_julia("println(item)"))])),
    ]))
is_executable(model)                                   # true
print(realize_process_text(model; instrumentation = :position))
session = ProcessDebugSession()
handle = start_process(model, [1, 2]; mode = :step, session = session)
sync_process_debug!(session, handle.trace, model)      # from the refresh hook
```

- Examples: `process`, the transmit procedure above with an unrefined step; `process_drain`; and `process_diagram`, the drain process as a flowchart, in `example/domain/process/`. The atomic catalog has one document for each process type, from the `make_process_*_document_example` functions of `ProcessDocumentExample.jl`.
- Test: `test_process()` runs the layering guard, `test_process_document()`, `test_process_debug()`, `test_process_diagram()`, `test_process_to_julia_code()` and `test_process_to_syntax()`.

## Limits

- No gesture writes `session.command` or toggles a breakpoint. `toggle_breakpoint!`, the command cell and the bridge work and have tests, but a caller must call them in code. [plan/done/process-domain.md](../../../../plan/done/process-domain.md) defers the gestures to the work on the editor surface.
- A selection lights a box only when it names the node exactly. A caret inside the action of a step does not light its box. An edge is not clickable.
- The flowchart does not always read from top to bottom. A layout computed from the tree, with a sequence as a column, a decision that opens two columns and the back edge of a loop in a margin lane, would give that. It is an idea, and no plan holds it yet.
- No screenshot of a process example exists.
- Not modeled: a decision with more than two ways, which nests in `else_branch`; a loop that tests last; a `foreach` with more than one clause; conditional breakpoints, step over, and a step back in a recorded trace; and more than one run of one model in one session.
