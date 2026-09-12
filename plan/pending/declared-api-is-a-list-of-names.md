# The declared API is a list of names

**Status:** pending. Written 2026-09-12. No step is implemented.

**Goal:** a person says which **names** a language model may write, not which
modules. A module stays the shorthand for "all of its exports", because that is
usually what is meant.

**Asked for by:** the user, 2026-09-12:

> we will eventually let the llm handle all kinds of symbols from all over the
> place. We need some kind of white listing, maybe a separate module is not the
> right answer. For example, transforming data frame data needs a lot of
> functions, we don't want to reeexport them.

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

### 3.2 A narrowed module does not bind its own name

A whole-module entry keeps its alias, as today — `PaneModule.anything` resolves.
A narrowed entry binds no alias, because an alias is a door to every name in the
module and would make the list decorative.

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

### 3.7 What is rejected

**A blacklist** — "this module except these". The default would be "everything",
which is the thing this plan is about.

**A pattern** — `DataFrames => r"^(select|transform)"`. A person reading a
regular expression cannot see what the model may call, and that list is the one
thing this declaration exists to make readable.

**A registry a package writes itself.** The result-frames plan settled that the
API is handed in and not registered, for the reason that only the assembly knows
every part. A whitelist is more of that decision, not less.

## 4. Stages

### Stage A — the declaration takes names

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

### Stage B — the namespace narrows

1. `_scratch_module` emits `using M: <declared names>`.
2. A narrowed entry binds no module alias.

**Test.** A declared name resolves unqualified; a name in the same module that
the declaration left out is an `UndefVarError` in the round that used it, which
is the assertion `DeclaredApiTest.jl` already makes for a module outside the
list. A narrowed module's own name does not resolve.

### Stage C — discovery narrows

1. `_index_declared` indexes the declared names, and reads the list rather than
   `names(M)`.
2. The module and type resources register only what is declared.
3. `read_function_documentation` refuses a name outside the list.
4. `_execute_julia_code_description` says what §3.6 says.

**Test.** `search_api` does not answer a name the declaration left out, and
`read_function_documentation` refuses it with a message that says so.

### Stage D — the callers stop qualifying

1. `OmnetCampaignUi` declares `PaneModule => (:PaneTree, :PaneSplit, :PaneGroup,
   :PaneTab)` and `ReferenceModule => (Symbol("@reference"),)`.
2. `PaneAgentModule` stops exporting the three module aliases.
3. `show_layout`'s printed program loses `PaneModule.` and `ReferenceModule.`,
   and its tests take the shorter text.

**Test.** The existing round trip: the program it prints rebuilds the same
window. It is the one that proves the namespace still resolves every name the
program uses.

### Stage E — a data frame, when a verb needs one

`OmnetIde` writes the list of frame-transforming names beside the verbs that
expect a model to use them. Nothing in this plan blocks it, and nothing in this
plan builds it: the list is worth writing when a verb hands a model a frame and
says "work on it".

## 5. What can go wrong

| trap | why | where it is caught |
| --- | --- | --- |
| An existing caller breaks. | `set.api` is typed `Vector{Module}` and read in fourteen places. | Stage A. A bare `Module` entry keeps today's meaning, and the tests for it are already written. |
| The whole-surface mode breaks. | `isempty(set.api)` means "every submodule of the project", and it is a different branch in four functions. | Stage A test. |
| A model finds a name it cannot call. | The index reads `names(M)` and the namespace reads the list. | §3.4, stage C. |
| The list becomes unreadable. | 86 names inline in a declaration. | §3.6. The long list is a `const` beside what it is for, and the tool description does not inline it. |
| A macro will not import. | `using M: @reference` needs the symbol spelled `Symbol("@reference")`. | It is how the scratch namespace already imports macros; stage B test. |

## 6. Out of scope

**Per-name documentation.** A declared name reads its own docstring, and this
plan adds no way to write another.

**A permission model.** This says what a model may *name*, not what it may *do*.
`execute_julia_code` still runs Julia, and a declared name can reach anything the
process can.
