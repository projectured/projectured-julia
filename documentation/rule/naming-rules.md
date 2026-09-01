# Naming

> **Kind:** rule · **Status:** current · **Stands on:** [division-terminology.md](division-terminology.md), [package-rules.md](package-rules.md), [system-anatomy.md](../design/system-anatomy.md)

How things are named here — in every package, not only the kernel. The goal is
guessability in both directions: given a concept, you can derive its name; given
a name, you can tell what kind of thing it is and what it does, without looking
it up. Meaningful, scheme-following names take priority over brevity or Julia
idiom. The convention departs from Julia Base style (compressed lowercase names,
minimal prefixes) exactly where doing so improves bidirectional guessability; it
agrees with Julia on CamelCase types and modules, `!` for mutation,
`SCREAMING_SNAKE_CASE` for constants, and avoiding abbreviations.

The vocabulary of the divisions — package, layer, slice, module, leaf — is
[division-terminology.md](division-terminology.md). What a package may depend on
is [package-rules.md](package-rules.md). This document says what each of them is
called.

## Packages

### The prefix and the slice

Every package name is `Projectured<Slice>` in CamelCase, and the umbrella is
`Projectured` alone. The package directory is `package/<PackageName>/`, one
folder per package, carrying the name exactly.

The slice is the lower-case name with the prefix removed, and it is the folder
its code lives in: `ProjecturedSequenceChart` is
`package/ProjecturedSequenceChart/`, its code is `source/sequencechart/`, its
suite is `test/sequencechart/` and its documents are `example/sequencechart/`.
That derivation is a rule and not a coincidence —
`ProjecturedKernelTest.package_source_root` computes it, and
`test_package_graph()` walks it.

### The suffix says which kind of package it is

`Example`, `Test`, `Repl` and `Build` are the only reserved suffixes, and they
mean nothing else. A package with no suffix holds the code.
[package-rules.md](package-rules.md) states the five kinds, what each may depend
on, and why a leaf matters.

- **A package whose name merely begins with another's is a stem of its own**,
  not a kind of it. `ProjecturedOdbc` and `ProjecturedTulip` are separate
  packages that carry a third-party dependency, not sub-packages of
  `Projectured`.
- **Two leaves are named outright rather than by suffix**, because the
  distinction they carry is real: `ProjecturedExecutable` is the artifact
  PackageCompiler compiles, and `ProjecturedBuilder` is the tool that drives the
  build. A tool is not a kind of artifact. `ProjecturedBench` is a leaf too.
- **A package extension is `<Package><Dependency>Ext`.** That is the name
  Julia's `[extensions]` table needs, and it reads as what it is. No package
  here has one yet.
- **A test package's entry point is `test_<slice>()`.** `ProjecturedJsonTest`
  exports `test_json`, `ProjecturedKernelTest` exports `test_kernel`, and the
  static layering guard beside it is `test_<slice>_layering()`. The table of
  every scope is in [testing-guide.md](../guide/testing-guide.md).

### A package holds a name and an include list

A package directory holds its `Project.toml` and `src/<PackageName>.jl`, and
that root file holds the docstring, the imports, the module aliases and the
ordered `include`s. The code it includes lives in `source/`, `test/` or
`example/`. The rule and what it cost are in
[plan/done/repository-tree.md](../../plan/done/repository-tree.md).

## Files and modules

- **Module = filename + `Module`.** `Clock.jl` defines `ClockModule`,
  `ProjectionApi.jl` defines `ProjectionApiModule`. Grep-by-guess must work in
  both directions — with no per-folder exceptions.
- **A module that owns a folder of fragments is `<Concept>Module.jl` itself.**
  A layer's primary module carries only its docstring, its export list, and its
  ordered `include`s (`DocumentModule.jl`, `BackendModule.jl`, `DeviceModule.jl`),
  so `<Concept>.jl` is free to be the contract fragment it includes first
  (`Device.jl`). The rule above still reads in both directions —
  the module is the file name, the `Module` suffix already spelled out. Where the
  bare concept name would be ambiguous with the type it declares, the contract
  fragment takes the prefix (`BackendInterface.jl`, `DocumentInterface.jl`,
  `ReferenceInterface.jl`, `SelectionInterface.jl`); where the folder holds one
  contract and the bare name reads cleanly, `Interface.jl` says it (`operation/`).
- **`Api` is a layer marker carried in the filename.** Every file in `api/`
  ends in `Api` (`DocumentApi.jl`, `BackendApi.jl`), so the rule above yields
  its `XApiModule` directly — no special case.
- Every exported name has exactly one owning module. Never export the same
  name from two modules. For a generic function, the owning module defines
  and exports the generic; other modules may import it and add methods, but
  may not re-export or redefine it.

## Projections

From a single stem derive all four names:

| artifact | name |
|---|---|
| file | `<Stem>.jl` |
| type | `<Stem>Projection` |
| module | `<Stem>ProjectionModule` |
| iomap | `<Stem>ProjectionIoMap` |

The stem answers a different question per folder:

- **`generic/` stems are gerunds saying what the projection does to the
  *document***: Copying, Filtering, Focusing, Reversing, Searching, Sorting.
- **`higherorder/` stems are gerunds saying what the projection does with
  its *child projections***: Chaining, Switching, Nesting, TypeDispatching,
  PredicateDispatching, ReferenceDispatching, WindowInputUnwrapping,
  WindowManaging.

Two exceptions:

- The degenerate projections take the standard math nouns: **Identity**
  (input passes through as the same object) and **Constant** (fixed output,
  input ignored). Together with Copying they form a triangle worth keeping
  sharp: *same object through* / *fresh copy with iomaps* / *fixed output
  ignoring input*.
- **Recursive** stays an adjective ("Recursing" is awkward, "Recursive" is
  universally understood).

## The pipeline ladder

The editing pipeline's vocabulary is a ladder of distinct kinds — no two
rungs are synonyms:

> **Event** → **Gesture** → **Intent** → **Operation** → **Document**

The user acts (events: `KeyDown`, `MouseMove`, `WindowClose`); acts combine
into a gesture (a click is down + up, a chord is two presses); readers read
the user's intent from the gesture (`Intent` carries the gesture plus the
operation-so-far, born unresolved and refined one domain inward per reader
step); the intent resolves to an executable edit (an operation); evaluation
applies it to the document. Name new concepts onto this ladder, not
alongside it.

## Types

- **Documents** are nouns (`CellVector`, `PrimitiveString`, `WindowDocument`).
- **A coded prefix names one variant of a document schema.** `@document Foo`
  emits them all, they mean the same thing in every schema, and none of them is
  ever hand-rolled.

  | name | what it is |
  |---|---|
  | `Foo` | what the declaration says its bare name is. The cell layout by default. |
  | `AFoo` | the family. Abstract, and it matches every variant. |
  | `ACFoo` | the cell layout, `ACFoo{C1<:AbstractCell, …}`, one cell per field. |
  | `MFoo` / `IFoo` | the native struct, mutable or immutable. Plain fields, no cell box. |
  | `RCFoo` / `ICFoo` / `MCFoo` | the cell layout with every field reactive / immutable / mutable. |
  | `DCFoo` | the cell layout with each field in its declared default kind. |

  Every one of them abbreviates a phrase, adjective first: `ACFoo` is the
  abstract cell `Foo`, `MCFoo` the mutable cell `Foo`, `MFoo` the mutable `Foo`,
  `IFoo` the immutable `Foo`.
  So a reader who forgets the convention can say the name out and get it back.

  A `C` says the variant keeps its fields in cells, and its absence says the
  fields are plain. That is the whole of what tells `MCFoo` from `MFoo`: the
  first is an immutable struct holding one `MutableCell` box per field, the
  second a single mutable object with its fields inline.
- **Operations are verb-first phrases with the `Operation` suffix**:
  `ReplaceSelectionOperation`, `OpenWindowOperation`,
  `ReplaceNumberRangeOperation`. Even the null operation is verb-first:
  `DoNothingOperation`. No word-order exceptions — not
  `NumberReplaceRangeOperation`, not a bare `ReplaceReferencedValue`. The
  one structural exception is `CompoundOperation`, a sequence of operations
  evaluated as one.
- **Events are `<Source><Action>`, suffixless and tenseless**: `KeyDown`,
  `MouseMove`, `MouseLeave`, `WindowClose`, `WindowResize`, `WindowDefocus`,
  `WindowQuit`. An event reports what the user or system did, never what
  should happen in response — the response is the reader's job, expressed as
  an operation. The word order alone separates the two families: noun-first
  suffixless = event flowing in (`WindowClose`), verb-first + `Operation` =
  intent flowing out (`CloseWindowOperation`). Where an event is a *request*
  the application may refuse (close, quit), say so in its docstring; the
  name deliberately does not. If the system ever needs both the request and
  the completed notification, the request keeps the plain event name
  (`WindowClose`) and the completion takes a different, non-synonymous
  action stem (e.g. `WindowDestroy`) — never distinguish the two by
  docstring alone.
- **Gesture patterns** mirror their event plus `Pattern`: `KeyDownPattern`,
  `MouseDownPattern`.
- **`Intent` is the reader pipeline's carrier**: the gesture plus the
  operation-so-far (`nothing` until some reader understands it). It is
  deliberately not an "edit" word — the edit is the operation it carries.
- **Exceptions** take the `Exception` suffix: `QuitEditorException`.

## Functions

**Every function name starts with a verb.** The subject is carried by
dispatch, not by the name.

- **Getters are `get_<stem>`**, pairing with their `set_<stem>!` twins:
  `get_selection` / `set_selection!`, `get_property`, `get_iomap_input`,
  `get_display_size`.
- **Derived copies are `with_<stem>`**: `with_property`, `with_selection`,
  `with_available_size` — return a copy with one aspect changed. Together
  with the getter this forms the read / derive / mutate trio:
  `get_property` / `with_property` / `set_property!`.
- **Protocol functions are verb + the unit that flows in**, dispatch
  supplying the subject: `print_document(projection, recursion, input,
  context)`, `read_intent(projection, iomap, intent)`,
  `read_gesture(document, gesture)`, `print_child(recursion, input,
  context)`, `evaluate_operation(operation, …)`. The verbs read, evaluate and print are
  intentional — they mirror the editor's read-evaluate-print loop, and each
  object names the rung of the pipeline ladder being consumed: the document
  flows forward through the printer, the intent flows backward through the
  readers.
- **Protocol functions come in two kinds, and both name their input.**
  A *rung-transformer* moves the unit up the ladder — `read_gesture`
  (gesture in, operation out), `evaluate_operation` (operation in, document
  state out); input and output are different kinds, which is where reading
  and evaluating visibly convert form into meaning. A *domain-translator*
  keeps the kind and moves it across one projection — `print_document`
  (document in, document out inside the returned IoMap), `read_intent`
  (intent in, intent out, translated one domain inward),
  `map_reference_forward` / `map_reference_backward` (reference in,
  reference out). The full reading of a gesture into an operation is
  distributed across the pipeline: each `read_intent` step advances it by
  one domain, and the composition of the steps is the reader.
- **Factories are `make_*`**: `make_agent_server`,
  `make_child_context`, `make_scripted_say`.
- **Predicates start with `is_`** (`is_valid_reference`,
  `is_reference_equal`, `is_cell_up_to_date`) or are plain verbs that read as
  questions at the call site (`matches(pattern, gesture)`).
- **Mutating functions end with `!`**: `insert_row!`, `pop_gesture!`,
  `record_performance!`. A name ending in `!` is an action, so it
  must start with a verb — a "mutating getter" like consuming a queue is a
  `pop_`/`take_`, not a noun.
- **Qualifiers are suffixes**: `get_document_gesture_bindings_own`,
  `is_reference_equal_ignoring_types`, `is_prefix_of_ignoring_types`.

### Words

- **snake_case with underscores between all words**: `is_cell_up_to_date`, not
  `isuptodate`; `insert_row!`, not `insertrow!`.
- **No ad-hoc abbreviated words inside names**: `value` not `val`, `function`
  not `fn`, `reference` not `ref`, `operation` not `op`, `performance` not
  `perf`, `evaluated` not `eval`.
- **The sanctioned compact forms are these**: `Api` (the layer marker),
  `IoMap`/`iomap` (a name in its own right), the generated `I<Document>` prefix,
  the canonical keyboard modifier labels `ctrl`/`alt`/`meta` (`has_ctrl_modifier_key`;
  nobody says `has_alternate_modifier_key`), and any well-known, widely-used abbreviation that reads
  unambiguously as its one expansion (`ctor` for constructor, `expr` for
  expression). The bar is guessability in both directions: `ctor` clears it, a
  coined shortening of a domain word (`val`, `ref`, `op`) does not.
- This convention governs exported names. Local and argument names are
  outside its scope, though full words are encouraged there too
  (`context` over `ctx`).

### Exemptions

Two shapes are exempt from the verb-first rule, and only these:

- **DSL words** inside macros: `when` and `prefix` in `@reference_case`.
- **Declarative macros** are noun-named: `@document`, `@iomap`,
  `@projection`, `@gestures`, `@reference`, `@reference_step`, `@event_case`. A macro
  is a DSL keyword — `@document` reads as "here is a document definition" —
  not an action.

## Identifiers in the documentation

A claim the code is checked against carries an identifier, and the prefix says
which document owns it. Both are `SCREAMING-KEBAB-CASE`.

| prefix | means | lives in |
|---|---|---|
| `PR-…` | a capability the editor promises, observable from outside | [accepted-requirements.md](../requirement/accepted-requirements.md) |
| `PAR-…` | an architecture rule every change must respect | [architecture-invariants.md](architecture-invariants.md) |

A bare `§N` always means a section of the file you are reading. Cite any other
file by name — the rule and the reason are under "Cite, do not repeat" in
[README.md](../README.md).

Every document in `documentation/` carries a one-line header naming its
**Kind**, its **Status**, and what it **Stands on**. The kinds, and the folder
each document belongs to, are in [README.md](../README.md).

## Quick reference

| shape | meaning | example |
|---|---|---|
| `Projectured<Slice>` | a package of the product | `ProjecturedJson` |
| `Projectured<Slice><Kind>` | its example or test package | `ProjecturedJsonTest` |
| `<Package><Dep>Ext` | a package extension | `ProjecturedSqlSQLiteExt` |
| `<File>Module` | the Julia module a file declares | `ClockModule` |
| `test_<slice>` | a suite entry point | `test_json` |
| `test_<slice>_layering` | its static layering guard | `test_json_layering` |
| `PR-…` / `PAR-…` | a claim the code is checked against | `PAR-PURE-THUNK` |
| `<Stem>Projection` | projection; gerund stem | `FilteringProjection` |
| `<Verb><Noun>Operation` | executable edit resolved from an intent; flows out of a reader | `CloseWindowOperation` |
| `<Source><Action>` | event, flows into a reader | `WindowClose` |
| `A<Document>` | family, matches every variant | `ACellVector` |
| `AC<Document>` | cell layout | `ACCellVector` |
| `M<Document>` | mutable native struct | `MCellVector` |
| `I<Document>` | immutable native struct | `IEthernetFcs` |
| `IC<Document>` | cell layout, every field immutable | `ICCellVector` |
| `<Event>Pattern` | gesture pattern | `KeyDownPattern` |
| `get_<stem>` / `set_<stem>!` | getter / setter | `get_selection` |
| `with_<stem>` | derived copy | `with_property` |
| `<verb>_<flowing unit>` | pipeline protocol | `print_document`, `read_intent` |
| `make_<thing>` | factory | `make_agent_server` |
| `is_<condition>` / `has_<possession>` | predicate | `is_valid_reference`, `has_ctrl_modifier_key` |
| `<verb>…!` | mutates its subject | `insert_row!` |
| `…_<qualifier>` | variant of the base name | `…_ignoring_types` |
