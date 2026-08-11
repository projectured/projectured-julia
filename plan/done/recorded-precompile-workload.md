# A recorded precompile workload, in all three repositories

## Why

A precompile workload compiles what it runs, so it compiles what somebody
thought to run. Measured in omnetpp-julia, that reached the printers and never
reached the readers: the read half of the first click cost 528 ms with the
workload and 518 ms without it, because atoms are documents and a document is
printed, not read.

Recording inverts it. A driver opens the real editor and drives it with mouse
and keyboard, Julia writes down every method instance it compiles, the list is
checked in, and later builds replay it. Measured in omnetpp-julia on the demo
catalog, first click on the line chart page:

| level | build | image | session | first click | of which read |
| --- | ---: | ---: | ---: | ---: | ---: |
| `:none` | 5 s | 14 MB | — | 4105 ms | 533.0 ms |
| `:recorded` | 103 s | 247 MB | 5.4 s | 61 ms | 4.4 ms |
| `:live` | 98 s | 153 MB | 4.6 s | 737 ms | 527.7 ms |

A second click is 7–9 ms at every level; there is nothing left to compile.

Two things are wrong with where that landed. The machinery lives in
`OmnetppRepl`, and the other two repositories still carry the four levels
`:none` / `:minimal` / `:demo` / `:full` — the same `set_workload!` with the same
error message, copied twice. This plan writes the machinery once and gives all
three leaves the same vocabulary.

## What each repository has now

| repository | leaf | workload body | levels |
| --- | --- | --- | --- |
| projectured-julia | `ProjecturedRepl` | `ProjecturedExample.precompile_workload(level; atoms)` | four |
| omnetpp-julia | `OmnetppRepl` | `OmnetppPresentationExample.precompile_workload()` | `:none` `:recorded` `:live` |
| inet-julia | `InetRepl` | `InetExample.precompile_workload(level)` | four |

A fourth consumer: `ProjecturedExecutable` calls
`ProjecturedExample.precompile_workload(APP_WORKLOAD)` when `APP_WORKLOAD` is not
`:none`.

## The shape to reach

One vocabulary in every leaf:

| level | what the build does |
| --- | --- |
| `:none` | nothing |
| `:recorded` | replays that repository's checked-in list — the default |
| `:live` | runs that repository's workload for real |

`precompile_workload` loses its level argument in all three repositories. The
levels existed to trade build time against the first click, and a recording
settles that trade; what is left is a choice between replaying a file and not
depending on one.

## Where the machinery lives

`ProjecturedExample`, in a new `example/PrecompileRecording.jl`. It already owns
`precompile_atoms`, `precompile_atom_walks` and `precompile_atom_parsers`, and
every leaf in all three repositories reaches it.

The public surface, used by three leaves and written once:

- `record_precompile_statements(; output, driver, project, threads) -> path` —
  run `driver` in a fresh process under `--trace-compile`, clean what it wrote,
  and write the list to `output`.
- `replay_precompile_statements(statements, scope; warn, ratio) -> (compiled, skipped, total)` —
  resolve each statement in `scope` and compile it, answering how many took.
- `PRECOMPILE_STALE_RATIO = 0.1` — the share that may be skipped before the build
  asks for a new recording.

### The scope module belongs to the leaf, not to the helper

A statement names its types from the module that defines them, so every loaded
module has to be reachable by name — measured, 12.9 % of a list resolves against
one package's own imports and 99.2 % against every loaded module. The helper
therefore binds `Base.loaded_modules` into a scope module before resolving.

That module **must belong to the leaf being built**. Binding constants into
`ProjecturedExample`'s own module while a *dependent* package precompiles is
Julia mutating one package's image from another's build, which is the thing that
makes incremental compilation unsafe. So each leaf declares

```julia
module StatementScope end
```

and passes it in. The contract is two lines per leaf and it keeps every write
inside the image being built.

## What each leaf gains

Three files and one preference, the same in each repository:

- `package/repl/record/driver.jl` — what the recorder runs.
- `package/repl/src/PrecompileStatements.jl` (or beside the leaf where it has no
  `src/`) — the generated list, checked in.
- `module StatementScope end` in the leaf.
- `WORKLOAD` / `set_workload!` / `get_workload` over the three levels, and a
  `@compile_workload` that dispatches on them.

## What each driver drives

A driver is the only part that knows the product, which is the point: the
machinery does not.

- **projectured-julia** — every example in `ProjecturedExample.examples` (103),
  each opened in a real editor and driven with the gesture set.
- **omnetpp-julia** — the demo catalog end to end (37 pages, first and second
  clicks) plus all three example registries (126 examples). Already written.
- **inet-julia** — its own demo catalog plus `InetExample.examples`.

Each driver first runs its repository's `precompile_workload()`, so a recording
is a superset of the live workload and `:recorded` never loses to `:live`.

## Steps

Each step is a commit. Mark it here when it lands.

1. **Done — projectured-julia, the machinery.** `example/PrecompileRecording.jl`
   in `ProjecturedExample`, exported, called by nobody yet. Commit `4c0813d4`.
2. **Done, with step 3 — projectured-julia, the workload loses its levels.**
   A level-free `precompile_workload` breaks the leaf, so the two landed
   together. `ProjecturedExecutable` runs all of it or none.
3. **Done — projectured-julia, the leaf.** Commit `0f2623ee`. 12760 statements
   from 102 of the 103 examples; `rotating_vector` refused with
   `Int64(::Nothing)`, its own defect. Measured:

   | | `:none` | `:recorded` | `:live` |
   | --- | ---: | ---: | ---: |
   | build | 4.7 s | 92.1 s | 102.9 s |
   | image | 13 MB | 217 MB | 149 MB |
   | session load | 3.3 s | 4.2 s | 3.7 s |
   | json, first paint | 7260 ms | 415 ms | 2559 ms |
   | json, first click | 2650 ms | 475 ms | 2600 ms |
   | — of which read | 1453 ms | 221 ms | 1494 ms |
   | xml, first paint | 2005 ms | 25 ms | 230 ms |
   | second click, any | 1–2 ms | 1–2 ms | 1–2 ms |

   The `workbench` example refuses at every level with an under-typed
   `@reference` in `WorkbenchToWidget.jl:543`. Not this change; worth its own
   look.
4. **Done — omnetpp-julia, call the shared machinery.** Commit `2139892`. The
   copy in `OmnetppRepl` deleted, 142 lines for 30. Same list, same result:
   14161 resolved, 138 skipped of 14299. The leaf gained `ProjecturedExample` as
   a dependency, which needed `Pkg.resolve()`.
5. **Done — inet-julia, the leaf.** Commit `523ee27`. 13765 statements from all
   13 catalog pages and 102 of the 103 upstream examples, which a session here
   can also open. Measured:

   | | `:none` | `:recorded` | `:live` |
   | --- | ---: | ---: | ---: |
   | build | 4.0 s | 97.6 s | 102.9 s |
   | image | 12 MB | 231 MB | 151 MB |
   | session load | 3.0 s | 3.9 s | 3.6 s |
   | the index, first paint | 7728 ms | 510 ms | 1985 ms |
   | `PacketIsChunks.md`, first click | 8568 ms | 42 ms | 1691 ms |
   | `Headers.md`, first click | 3271 ms | 41 ms | 399 ms |
   | second click, any | 20–33 ms | 20–33 ms | 20–33 ms |

6. **Done — the documentation.** The three leaf headers and the three
   `documentation/packages.md`.

## What the three recordings cost

| | statements | file | skipped |
| --- | ---: | ---: | ---: |
| projectured-julia | 12760 | 5.6 MB | 1 |
| omnetpp-julia | 14299 | 6.2 MB | 138 |
| inet-julia | 13765 | 6.0 MB | 9 |

They overlap heavily and still have to be three files: an image only helps the
session that loads it, and a `jp` session never loads `OmnetppRepl`.

## Left for another day

- `rotating_vector` refuses to be driven in every repository —
  `MethodError: no method matching Int64(::Nothing)`.
- The `workbench` example refuses at every level with an under-typed
  `@reference` in `WorkbenchToWidget.jl:543`.
- `simulation_monitor_widget` refuses in omnetpp-julia with a `SelectionMismatch`
  — a seeded selection that was not lifted to a screen-rooted path.
- A recording cannot be regenerated headlessly, because the driver needs a
  display.

## Measurements to take, per repository

Build time, image size, `using <Stem>Repl` time, and the first and second click
of whatever that repository opens. Compare `:none`, `:recorded` and `:live`.

## What this costs

- **Session load.** Measured in omnetpp-julia: 5.4 s against 4.6 s, so the
  recording costs 0.8 s at every session start for a 94 MB larger image.
- **Repository size.** omnetpp-julia's list is 6.2 MB for 14299 statements.
  Three of them, and they overlap heavily, because a package image only helps a
  session that loads it — omnetpp's list cannot serve a `jp` session.
- **A file that rots.** 138 of 14299 statements are already skipped; they are
  the Unitful signatures, whose units live inside the type and do not read back.
  The list degrades gradually and the build reports it, so a re-recording is
  never urgent.
- **The recorder needs a display.** SDL asks for an accelerated renderer, which
  the dummy video driver does not offer. Recording is a person's step, not a
  build's, so this is acceptable; it does mean the list cannot be regenerated in
  a headless job.

## Working arrangement

**Not in a worktree, despite the standing rule.** The three repositories resolve
each other through `[sources]` paths that point at the *main* checkouts, so a
change made in a projectured-julia worktree is invisible to omnetpp-julia and
inet-julia. Steps 4 and 5 measure against steps 1–3, so they would measure the
wrong tree. The work goes on `main` in each repository, one commit per step,
committed with explicit paths because the user works in the same checkouts.
