# The declared API is a list of names

**Status:** pending. Written 2026-09-12. **Stages A to D are done, and half of
F.** Stage E waits for a verb that hands a model a data frame. The other half of
F is blocked by a package dependency and is §4's last paragraph.

**Goal:** a person says which **names** a language model may write, not which
modules. A module stays the shorthand for "all of its exports", because that is
usually what is meant.

**And then the `*AgentModule` boundary stops earning its keep.** A module that
exists to collect names for a declaration has one job, and the declaration takes
it over. §3.7 says why, and stage F does it.

**Asked for by:** the user, 2026-09-12:

> we will eventually let the llm handle all kinds of symbols from all over the
> place. We need some kind of white listing, maybe a separate module is not the
> right answer. For example, transforming data frame data needs a lot of
> functions, we don't want to reeexport them.

And, on what follows from it:

> We can get rid of the AgentModules then, no? Every verb that is useful for an
> agent is also probably useful for the program and vice verse, I think

## 1. What a module costs today

`declare_api!(set, modules)` stores `Vector{Module}`, and every exported name of
every one of them arrives. Two prices, both measured while
[assistant-controls-the-layout.md](../../../omnet-julia/plan/done/assistant-controls-the-layout.md)
was built:

- **The surface floods.** `@document` exports about thirty generated schema
  variants per document type — `APaneSplit`, `ACPaneSplit`, `DCPaneSplit` — none
  with documentation of its own. Declaring `PaneModule` and `ReferenceModule`
  beside two verb modules took the surface from **10 names to 122**, and a search
  for "what panes are open" then answered with those variants.
- **A borrowed name has to be qualified or re-exported.** Re-exporting breaks the
  rule that a name has one owning module
  ([naming-rules.md](../../documentation/rule/naming-rules.md)), so the layout
  work qualifies instead: the program a model edits says
  `PaneModule.PaneSplit(…)` and `ReferenceModule.@reference(…)` on every line.

`DataFrames` is the case that settles it: 86 exported names, and a verb that
transforms a frame wants perhaps eight of them. Neither re-exporting eight names
into a module that does not own them, nor declaring all 86, is right.

**Base is not the problem.** A bare `Module` has `Base` in scope already, so
`sum`, `map`, `filter` and the rest need no declaration. Only a package's own
names do.

## 2. The shape of the answer

```julia
declare_api!(set, [
    PaneAgentModule,                                      # every exported name
    PaneModule  => (:PaneTree, :PaneSplit, :PaneGroup, :PaneTab),
    ReferenceModule => (Symbol("@reference"),),
    DataFrames  => DATA_FRAME_VERBS,
])
```

An entry is a `Module` — which keeps today's meaning exactly — or a
`Module => names` pair. Nothing else changes at the call site, and every existing
caller keeps working.

## 3. Decisions

### 3.1 A declared name arrives unqualified

This is the payoff. The scratch namespace already builds itself with
`using M: <names>` ([CodeExecution.jl:77](../../source/kernel/tool/CodeExecution.jl#L77));
it will use the declared list instead of `names(M)`. So a model writes
`PaneSplit(…)`, not `PaneModule.PaneSplit(…)`.

**No module re-exports anything.** The naming rule is about exports, and a
declaration is not an export: `PaneSplit` still has exactly one owning module,
and the person who wrote the declaration said which names this model may use.
The layout plan's §4.8 calls its qualifier a stopgap; this is what ends it.

### 3.2 A narrowed module keeps its own name

Every declared module stays bound under its own name, as today, whether it gave
all of its exports or four of them — so `PaneModule.anything` resolves either
way.

**This reverses what this section first said**, and the reason is what the harm
turned out to be. The measured damage of a wide declaration is to *discovery*: a
search for "what panes are open" answered `ACPaneSplit`, `APaneSplit`,
`DCPaneSplit` — generated schema variants with no documentation — instead of
`show_layout`. Narrowing the **index** fixes that completely, and the module
binding has nothing to do with it. Withholding the binding would buy only
reachability, and `ToolSet` already says of itself that a declaration "is a focus
mechanism and **not a security boundary**".

It would also cost something real: the `using M: …` the namespace is built from
needs `M` bound in it, so withholding the name means binding it under a mangled
one. A mangled binding is a door with a sign on it, which is worse than a door.

### 3.3 A name two entries both give is refused, at declaration time

`using A: x` and `using B: x` in one namespace is an ambiguity Julia reports only
when the model writes `x`. The declaration is where a person can fix it, so that
is where it is caught, with both sources named.

Today's module-only form can collide the same way and says nothing. The check
covers both forms.

### 3.4 Discovery narrows with the namespace

A name the declaration does not list must be invisible to `search_api` and
unreadable by `read_function_documentation`. `_index_declared`'s own comment
already states the rule — "a model that finds a function it cannot call wastes a
round and learns to distrust the answer" — and a narrowed module breaks it unless
the index narrows too.

Four consumers narrow: the search index
([Documentation.jl](../../source/kernel/tool/Documentation.jl)), the
`resource://module/…` and `resource://type/…` registrations, the documentation
readers, and the `execute_julia_code` description.

### 3.5 A name need not be exported by its module

`using M: x` reaches a name `M` does not export. So a declaration can name
`PaneModule.pane_groups` whether or not `PaneModule` exports it, and the index
must read the declared list rather than `names(M)` for a narrowed entry.

This is worth having and not worth encouraging: a name a module does not export
is a name its owner did not offer, and a declaration that reaches for one says
the owner should export it.

### 3.6 The tool description says only what is true

`_execute_julia_code_description` names the declared modules today
([DefaultTools.jl:52](../../source/kernel/tool/DefaultTools.jl#L52)). With
narrowing, "the functions of `DataFrames`" is false.

It names the whole-module entries as it does now, and says of the rest that they
are individual names `search_api` lists. **It does not inline them**: 86 names in
a tool description are 86 names in every request, and the search is what finds a
name when it is wanted.

### 3.7 The module boundary is not the surface

Three modules exist today whose whole job is to be named in a declaration:
`CampaignAgentModule`, `PaneAgentModule` and `ResultAgentModule`, nineteen
exported verbs between them. The declaration is about to say what a model may
write, name by name, so a module that groups names for it says nothing a person
could not read from the list.

**The verbs are not a collection artifact, and they stay.** Each is one word for
a whole act: `run_simulations(editor; config = "Tandem")` is four calls and a
judgement underneath — write the form, check the match, pick a group to keep
clear, start the batch. That compression is worth the same to a person at the
REPL as to a model, which is the owner's point: a verb useful to an agent is
usually useful to the program, and the other way round.

**What the boundary gets wrong today** is the name. A programmer looking for
"focus that pane" does not open `PaneAgentModule`, because the name says it is
for the agent. It is not.

So the verbs move to where the thing they act on lives, and the declaration
becomes the one statement of what a model may do. Stage F says where each one
lands.

**Two things do not dissolve with the modules.**

*The adapter shape.* These verbs take `editor` first, key everything on plain
types, answer sentences, and write their messages for a reader.
`CampaignAgentModule`'s docstring is what states that today — "Take `editor`
first and everything else as a keyword of a plain type. A model that must build a
document to call a verb will build the wrong one" — and proximity is what
enforces it. Moved apart, the rule needs a written home: a section in
[naming-rules.md](../../documentation/rule/naming-rules.md), or the declaration's
own docstring.

*The reviewable list.* Three entries become about nineteen names over four
modules. That is longer, and it is the point: what a model may do stops being a
module boundary that also carries Julia's loading order and becomes one list a
person reads. It is worth keeping it as **one list in one place**, with a comment
per group, rather than scattering it over the packages the names come from.

### 3.8 What is rejected

**A blacklist** — "this module except these". The default would be "everything",
which is the thing this plan is about.

**A pattern** — `DataFrames => r"^(select|transform)"`. A person reading a
regular expression cannot see what the model may call, and that list is the one
thing this declaration exists to make readable.

**A registry a package writes itself.** The result-frames plan settled that the
API is handed in and not registered, for the reason that only the assembly knows
every part. A whitelist is more of that decision, not less.

## 4. Stages

### Stage A — the declaration takes names — **DONE**

1. `ToolSet.api` becomes `Vector{Pair{Module,Union{Nothing,Vector{Symbol}}}}`,
   `nothing` meaning every exported name.
2. `declare_api!` accepts a `Module` or a `Module => names` pair and normalizes.
3. `api_modules(set)` answers the modules, for the readers that only want those.
   Fourteen sites read `set.api` today, across
   [Tool.jl](../../source/kernel/tool/Tool.jl),
   [ToolSet.jl](../../source/kernel/tool/ToolSet.jl),
   [CodeExecution.jl](../../source/kernel/tool/CodeExecution.jl) and
   [DefaultTools.jl](../../source/kernel/tool/DefaultTools.jl).
4. The collision refusal of §3.3.

**Test.** A declaration of mixed entries answers the names it was given; a
declaration that lists a name twice is refused, naming both modules;
`isempty(set.api)` still means the whole surface.

### Stage B — the namespace narrows — **DONE**

1. `_scratch_module` emits `using M: <declared names>`.
2. A narrowed entry binds no module alias.

**Test.** A declared name resolves unqualified; a name in the same module that
the declaration left out is an `UndefVarError` in the round that used it, which
is the assertion `DeclaredApiTest.jl` already makes for a module outside the
list. A narrowed module's own name does not resolve.

### Stage C — discovery narrows — **DONE**

1. `_index_declared` indexes the declared names, and reads the list rather than
   `names(M)`.
2. The module and type resources register only what is declared.
3. `read_function_documentation` refuses a name outside the list.
4. `_execute_julia_code_description` says what §3.6 says.

**Test.** `search_api` does not answer a name the declaration left out, and
`read_function_documentation` refuses it with a message that says so.

### Stage D — the callers stop qualifying — **DONE**

1. `OmnetCampaignUi` declares `PaneModule => (:PaneTree, :PaneSplit, :PaneGroup,
   :PaneTab)` and `ReferenceModule => (Symbol("@reference"),)`.
2. `PaneAgentModule` stops exporting the three module aliases.
3. `show_layout`'s printed program loses `PaneModule.` and `ReferenceModule.`,
   and its tests take the shorter text.

**Tested** by the existing round trip — the program it prints rebuilds the same
window — and the harness under it changed to prove more: `_run_program` runs the
program through a real `ToolSet` that declares exactly what the window declares,
rather than through a namespace the test built for itself. A declaration that
forgets a name the program says now fails there.

Each package declares its own, and they compose: `pane_api()` answers the layout
names, `campaign_api()` adds the simulation verbs, `get_assistant_api()` adds the
result verbs. The program lost its qualifiers:

```julia
runner = get_referenced_value(editor, @reference(window, root.elements[1].tabs[1]))
replace_referenced_value!(editor, @reference(window, root),
    PaneSplit(:vertical, [PaneGroup([runner]), …], weights = [0.3, 0.7]))
```

One test changed shape rather than value. `get_assistant_api()` was asserted by
**count**, and a count is no longer the measure — a name can arrive without a
module of its own. It asserts what its own comment always meant: that the list
and the two texts say the same thing.

### Stage E — a data frame, when a verb needs one

`OmnetIde` writes the list of frame-transforming names beside the verbs that
expect a model to use them. Nothing in this plan blocks it, and nothing in this
plan builds it: the list is worth writing when a verb hands a model a frame and
says "work on it".

### Stage F — the agent modules dissolve — **half done**

Last, and only last: done before the whitelist lands it would move the flood
rather than end it.

Each verb goes to the module that owns what it acts on. Nineteen verbs, four
homes:

| verbs | where they land | state |
| --- | --- | --- |
| `show_layout`, `get_referenced_value`, `replace_referenced_value!`, `get_window_tree`, `describe_pane_content`, `focus_pane`, `close_pane`, `move_pane`, `resize_pane` | `ProjecturedPane`, as `PaneProgramModule` | **done**. All nine are about any pane tree and name nothing of this application. `apply_pane_operation!` went up first, into `PaneSurgeryModule`. |
| `run_simulations`, `run_simulations_in_conversation`, `count_simulations`, `describe_simulations`, `stop_simulations`, `list_panes` | were to go beside `open_simulation_pane!` | **blocked**, see below |
| `get_results`, `show_results`, `plot_results` | `OmnetIde` | already there; only the assembly names both the result packages and the window |

**The table above was wrong about the six, and the check found it.**
`run_simulations` keeps the assistant's own group clear, so it names `Assistant`
— and `OmnetLegacySimulatorPresentation` does not depend on `ProjecturedAssistant`
and should not: that would widen the closure of a package that draws
simulations. The same holds for the result verbs by construction. **Both sets
stay in the package that already names everything they touch**, which is the
assembly, and that is right rather than a compromise.

So what is left of stage F is not a move but a **rename**: `CampaignAgentModule`
and `ResultAgentModule` are named for their reader rather than for what they do,
and that is the fault §3.7 identified. The verbs have nowhere better to live; the
modules have a better name to take. It needs one, and the owner names it.

Then:

1. `CampaignAgent.jl`, `PaneAgent.jl` and `ResultAgent.jl` go, and their
   docstrings' rules go to the written home §3.7 names.
2. `get_assistant_api()` answers the list of names, grouped and commented. It is
   the one place that says what a model may do.
3. The two system prompts stop naming modules. They name what the verbs are for,
   which is what a reader wanted from them anyway.

**Test.** Every suite that exists: the layout round trip, the campaign window,
the result verbs, and the closure guards. Nothing about behaviour changes here —
the same functions answer the same things from different files — so a suite that
moves is a suite that found a real coupling.

**One function moved ahead of the verbs.** `replace_referenced_value!` applies its
operation with `apply_pane_operation!`, which is in this repository's
`SimulationWindowModule` — below the package the verb would move to. It is
generic: it needs `PaneTree` and `evaluate_operation`, both under
`ProjecturedPane`, and its docstring is already written about pane trees and not
about simulations. **It moved to `ProjecturedPane` first**, and this repository
imports it from there — `SimulationTools.jl` and the tests too.

**What stayed behind.** `describe_pane_content`'s generic and its layout methods
go up with it; its methods for `SimulationFilter`, `Assistant`,
`SimulationBatchDocument`, the result frame and the plot stay where those
documents are. That is the method table doing what it is for, and it is why the
generic must be the one thing that moves.

**What it cost in closure.** Nothing, measured: `test_ide_closure()` is 12/12 and
the window is still under its cap. `ProjecturedPane` gained functions naming only
what it already named.

**The test did not move with the code.**
[PaneProgramTest.jl](../../../omnet-julia/test/campaign/PaneProgramTest.jl) stays
in this repository, because one of its assertions clicks into a grid through the
campaign window's own projection — the substrate chain does not route a click
into a layout content at all. The rest of it would move; splitting it to move
half is worth less than leaving it whole where it runs.

## 5. What can go wrong

| trap | why | where it is caught |
| --- | --- | --- |
| An existing caller breaks. | `set.api` is typed `Vector{Module}` and read in fourteen places. | Stage A. A bare `Module` entry keeps today's meaning, and the tests for it are already written. |
| The whole-surface mode breaks. | `isempty(set.api)` means "every submodule of the project", and it is a different branch in four functions. | Stage A test. |
| A model finds a name it cannot call. | The index reads `names(M)` and the namespace reads the list. | §3.4, stage C. |
| The list becomes unreadable. | 86 names inline in a declaration. | §3.6. The long list is a `const` beside what it is for, and the tool description does not inline it. |
| A macro will not import. | `using M: @reference` needs the symbol spelled `Symbol("@reference")`. | It is how the scratch namespace already imports macros; stage B test. |
| The verbs lose their shape once they are apart. | Proximity is what enforces "editor first, plain keywords, a sentence back" today. | §3.7. The rule moves to a written home before the modules go. |
| What a model may do becomes hard to review. | Three entries become nineteen names. | §3.7. One list, one place, a comment per group — not a name declared beside each function. |

## 6. Out of scope

**Per-name documentation.** A declared name reads its own docstring, and this
plan adds no way to write another.

**A permission model.** This says what a model may *name*, not what it may *do*.
`execute_julia_code` still runs Julia, and a declared name can reach anything the
process can.

**A second door for the program.** Stage F moves the verbs; it does not give
them a second form that takes the document instead of the editor. Where a program
wants that, the function the verb wraps is already there and already exported —
`batch_document_counts` under `describe_simulations`, `simulation_window_titles`
under `list_panes`. The verb is the sentence-shaped door, not the only one.
