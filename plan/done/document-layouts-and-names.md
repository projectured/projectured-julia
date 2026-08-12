# Document layouts and their names

> **Status (2026-08-12): DONE.** Every part is built, across all three
> repositories. Of the five items under **What this plan leaves undone**, three
> are now resolved (`Packet` took the native binding, the `record_tap!` signature
> drift is fixed, and the three test environments now resolve standalone); two
> stay open (the precompile-statement staleness, and the two files below still
> unsealed awaiting review). None of the five was ever a step of this plan.
>
> Two sealed files were edited and are left **unsealed**, marked ⬜ in `CLAUDE.md`,
> so that the owner knows to review them: `document/DocumentMacro.jl` and
> `reference/ReferenceEvaluation.jl`. The owner authorized both on 2026-08-10 and
> asked for the unsealing. See **Sealed files**.
>
> **Rule 3 changed on 2026-08-11.** The bare name binds **per schema**, and the
> default is the cell layout — what it means today. Binding every schema's bare
> name to the concrete default spelling was measured and reverted: it costs 1774
> annotation rewrites, 608 import lines and a forced move of the reference token,
> for a benefit that three schemas want. See **Rule 3** in Part 2.
>
> This plan supersedes Phases 1, 4, 6 and 7 of
> [document-native-variant-layouts.md](../pending/document-native-variant-layouts.md). That
> file stays as the record of its Phases 1 to 3, which are done, and of its
> measurements and its four companion `.jl` proofs. Two corrections to it are
> marked there.

`@document` emits one schema as many types. Today the *name* of a type is the
only way to ask for a layout, so a call site that wants the plain mutable struct
must write `FooMut`. In omnetpp-julia the plain struct is the primary object, so
that suffix is on 76 lines. This plan gives layout a first-class handle, fixes the
cross-layout bug that the missing handle causes, and settles the names.

## What is wrong

Three facts, all measured on this checkout.

**Fact 1 — `copy_document` does not convert layout.** The kind argument converts
cells, not the struct layout.

```
copy_document(ReactiveCell, ProbeRootMut(...))  →  ProbeRootMut
```

**Fact 2 — a reactive shadow silently freezes.** When a document child first
appears in a native source, `_synced_child` calls `copy_document(K, source_child)`
and gets a native node back. That node goes into the reactive shadow. Its fields
hold no cells, so every later `sync_document!` writes them with a plain
`setfield!` and invalidates nothing.

```
shadow type       = ProbeRoot{Cell, Cell}    # a real reactive stem
src.child = ProbeChildMut(value = 7); sync_document!(shadow, src)
shadow child      = ProbeChildMut            # native node inside a reactive shadow
child has cells   = false
watch (1st read)  = 7
src.child.value = 99; sync_document!(shadow, src)
shadow value      = 99
watch (re-read)   = 7                        # the reader never runs again
```

`m.pending = TicTocMessage1Mut("tictocMsg")` in omnetpp-julia
(`package/tictoc/main/src/Waiting.jl:34`) has exactly this shape.

**Fact 3 — a reference does not cross layouts.**
`get_reference_node_type(document) = Base.typename(typeof(document)).wrapper`
([ReferenceEvaluation.jl:136](package/kernel/main/reference/ReferenceEvaluation.jl#L136)).
A path built on `FooMut` carries the checkpoint `FooMut` and does not match the
same node in the cell layout.

## Goal

1. A caller selects a layout by a function, never by a type name.
2. `copy_document` and `sync_document!` put the right layout in the right tree.
3. A reference matches a node of any layout of one schema.
4. One regular name system covers every variant of every schema.
5. A schema emits only the variants it needs, and the call site says which.

## Vocabulary

The words below are the only words the code uses for these things.

| Word | Meaning |
| --- | --- |
| schema | One `@document` declaration. It emits many types. |
| family | The abstract type over every variant of one schema. |
| layout | How a variant stores its fields: in cells, or as plain values. |
| cell layout | The parametric struct. One cell per field. |
| native layout | A plain struct. Fields hold the declared value types. |
| kind | Which cell class a cell field holds: reactive, mutable, immutable. |
| spelling | One concrete parameter list of the cell layout, such as all-reactive. |
| variant | Any one of the eight types below. |

---

# Part 2 — the names (decided)

Part 2 comes first because the rest of the plan uses its names.

`@document struct Stem … end` emits this system. **Every name abbreviates a
phrase, adjective first**, so a reader who forgets the convention can say the name
out and get it back.

| Name | Reads as | What it is |
| --- | --- | --- |
| `AStem` | AbstractStem | the family. Abstract. It matches every variant. |
| `IStem` | ImmutableStem | the immutable native struct. Plain `struct`, value fields. |
| `MStem` | MutableStem | the mutable native struct. Plain `mutable struct`, value fields. |
| `ACStem` | AbstractCellStem | the cell layout. `ACStem{C1<:AbstractCell, …}`, one cell per field. |
| `ICStem` | ImmutableCellStem | `ACStem{ImmutableCell{T}, …}` |
| `MCStem` | MutableCellStem | `ACStem{MutableCell{T}, …}` |
| `RCStem` | ReactiveCellStem | `ACStem{ReactiveCell{Any}, …}` |
| `DCStem` | DefaultCellStem | `ACStem{per-field default}` |
| `Stem` | — | **what the declaration says its bare name is.** The cell layout by default. |

A `C` says the variant keeps its fields in cells; its absence says the fields are
plain. That is the whole of what tells `MCStem` from `MStem`.

The cell layout carries an `A` because it **is** abstract: `ACStem` is a UnionAll
with no instances of its own, and every spelling is one of its parameterizations.
`AStem` is abstract over every variant, `ACStem` over the cell ones, and the two
`A`s mean the same thing.

## How Part 2 lands, in four steps

The old `IStem` (all-immutable spelling) and the new `IStem` (immutable native)
are different things with one name, and so are the two `MStem`s. A rename that
crossed them would be ambiguous mid-flight, so the spellings move out of the way
first.

| Step | What moves | Sites | State |
| --- | --- | --- | --- |
| 2a | `RStem`/`IStem`/`MStem` → `RCStem`/`ICStem`/`MCStem` | 19 | **DONE** |
| 2b | `AbstractStem` → `AStem` | 42 in `.jl`, 5 in `.md` | **DONE** |
| 2c | `StemMut` → `MStem` | 17, all of them tests and prose | **DONE** |
| 2d | `DStem` → `DCStem` | 480 | **DONE** |
| 2f | the bare-name binding rule, the `DC` code, `const ACStem = Stem` | 0 here | **DONE** |
| 2e | the three style schemas take `[DC]`; their sites lose the `DC` | 479 | **DONE** |
| 2g | every name reads as a phrase: `C…` → `…C`, and the cell layout gains its `A` | 28 | **DONE** |

**2g.** The scheme had the family adjective-first (`AStem`) and a spelling
layout-first (`CIStem`), and `CIStem` expanded to no English at all. Now every
name is an abbreviation read adjective-first, so a reader can say it out and get
it back. The cell layout gained an `A` because it is a UnionAll with no instances
of its own — it really is abstract, and the `A` on it means what the `A` on
`AStem` means.

One thing gets slightly worse and was accepted: `MStem` and `MCStem` now share a
first letter, where `MStem` and `CMStem` differed at position 1. The trade is a
difference you can *say* — "mutable stem" against "mutable cell stem" — for one
you could only see.

Two traps, both caught by the suites rather than by reading:

1. The layout **code** `CD` had to move to `DC` with the name it binds, and the
   binding branch still tested `binding === :CD`. It silently fell through to the
   native target, so a `[DC]` schema tried to bind its bare name to an `MStem`
   that it never emits.
2. The docname list that drives every sweep was built by a regex expecting the
   layout list *before* the field-kind marker. Seven schemas write
   `@document ImmutableCell [DC] struct …` and were missed — including all three
   styles. The regex now accepts the two markers in either order.

**2e, and open question 4 answered: no.** Nothing builds a reactive style. The
names `RCStyleText`, `RCStyleFont` and `RCStyleColor` appear in three comments and
nowhere else, and the only production call that copies with an explicit kind is
`_pure_snapshot`, which lands on the default spelling. So narrowing the three bare
names could not lose a caller, and the six suites agree.

What it bought, measured after the change:

```
StyleText === DCStyleText    : true
StyleText isconcretetype     : true     ← a config cell inlines it
StyleText isbitstype         : false    ← it carries a font String, as it always did
StyleColor isbitstype        : true
cell layout is ACStyleText    : true
snapshot lands on it         : true
```

One thing the sweep needed after it. `import ..StyleTextModule: StyleText,
DCStyleText` collapsed into the same name twice on 36 lines. Julia tolerates it,
but it reads as a mistake, so those lists are deduplicated.

**2f, as built.** `schema` and the cell layout's own type name are now two things
in the macro. Every coded name is built from `schema`, so a spelling of `Foo` stays
`RCFoo` and never becomes `CRCFoo`. The cell layout keeps the programmer's name
under `C` and takes `ACFoo` under any other binding, which is what keeps `show` and
`nameof` unchanged for a schema that does not rebind.

Proved by a fixture per binding in `DocumentMacroTest.jl`:

```
C   ACDmRuleY === DmRuleY,  nameof(typeof(DmRuleY(1, 2))) === :DmRuleY
CD  DmValue === DCDmValue, isconcretetype, isbitstype, DmValue(2).b == 7
M   DmNative === MDmNative, a field holds no cell, n.a = 9 is a setfield!
```

The forwarding constructor was needed exactly where the measurement said. Under
`DC` the bare name is a concrete parameterization with no constructor of its own,
and one catch-all carries Rule Y, Rule C and the keyword form into the cell layout.

`test_kernel()` 1498 → 1515 for seventeen new assertions. The other five suites are
byte-identical.

**2f moved ahead of 2e.** The `DC` code is a *binding*, so it means nothing until
the binding rule exists. Adding it in 2d would have made
`@document [DC] struct …` a code that is accepted and changes nothing, which is
the silent cap this plan warns against. It lands with the rule that gives it a
meaning, and the styles opt in after that.

Step 2f is what omnetpp-julia uses at every declaration and projectured-julia uses
nowhere, so it lands here unexercised and is proved in the next repository.

2b and 2c landed together. Neither renames a call site that does real work —
`StemMut` had no production use in this repository at all — and both were checked
against the six suites before the commit. A collision check ran first for each:
no `AStem` and no `MStem` name existed before its rename.

**2a taught one thing.** `_emit_keyword_ctors` builds a keyword constructor per
alias from its own list of prefixes, so renaming the aliases alone left
`ICStem(a = 1)` with no method while defining a stray `IStem` function. The two
lists must move together. The representative suite caught it as one error, which
is why every step runs the set rather than a targeted test.

Three rules make the system regular.

1. **A coded name is always a real type name.** Every variant has one, and it means
   the same thing in every schema.
2. **`AStem` is the dispatch type.** It is strictly better than today's bare
   `Stem`, which is the UnionAll `ACStem{C1,…}` and matches every cell spelling but
   no native layout. `AStem` matches both layouts.
3. **`Stem` is whatever that schema is used as.** The declaration says so. The
   default is the cell layout, which is what the bare name means today, so a
   schema that says nothing changes in no way.

## Rule 3: the bare name binds per schema

The first entry of the layout list binds the bare name. Three bindings, and the
cost is paid only by the schema that opts in.

| First entry | `Stem` means | Fits |
| --- | --- | --- |
| `C` — the default | the cell layout UnionAll, exactly as today | every projectured-julia schema |
| `DC` | the concrete default spelling | a value document, stored by value in a config cell |
| `M` | the mutable native struct | a schema whose primary object is the one a simulator mutates |

```julia
@document struct JsonString <: JsonDocument      # C   → the UnionAll, unchanged
@document ImmutableCell [DC] struct StyleText    # CD  → DCStyleText, concrete, inlines
@native_document struct SimulationInstance       # M,C → MSimulationInstance
```

### Why `DC` is free for a value document and not for a reactive one

`_pure_snapshot` copies a projection's output to the immutable kind
([Projection.jl:67](package/kernel/main/projection/Projection.jl#L67)). Whether
that snapshot is the *same type* as the bare constructor's output decides whether
narrowing the bare name can lose a caller. Measured:

```
StyleText   DCStyleText  === ICStyleText  : true    snapshot === default form : true
JsonString  DCJsonString === RCJsonString : true    snapshot === default form : false
```

For a value document the default spelling **is** the all-immutable spelling, so
the snapshot lands on it and `::StyleText` keeps matching everything it matched.
For a reactive schema the snapshot is a different type, so `[DC]` there would
narrow `::JsonString` away from it. That is why the styles opt in and JSON does
not: the UnionAll already means "the reactive form and the snapshots taken from
it", and a JSON field is typed `Document` or `JsonDocument` anyway, so
concreteness buys nothing there.

### Why the styles want it

`DStyleText` has 454 uses and they all look like
[CollectionToSyntax.jl:35](../../package/syntax/main/CollectionToSyntax.jl#L35):

```julia
delim::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
```

The comment at [StyleText.jl:28](../../package/style/main/StyleText.jl#L28) says
why: "`DStyleText` is concrete and inlines in config cells". A field cannot inline
a UnionAll, so those sites had to reach past the bare name. With `[DC]` they write
`ImmutableCell{StyleText}` and the `D` prefix leaves the source.

## What the constructor builds

`Stem(args…)` keeps today's semantics exactly. A raw value wraps in its field's
default kind. A cell of any kind passes through as it is.

A schema that binds its bare name to a **cell spelling** needs one extra emission,
because a concrete parameterization is not callable. Measured:

```
DPA full arity -> MethodError: no method matching PA{Cell, Cell, Cell}(::Int64, ::String, ::Nothing)
DPA keyword    -> MethodError: no method matching PA{Cell, Cell, Cell}(; a::Int64)
PA  full arity -> PA{Cell, Cell, Cell}
```

One catch-all covers Rule Y, Rule C and the keyword form at once, and a
hand-written `Stem(v::String)` in a domain stays more specific:

```julia
(::Type{DCStem})(args...; kw...) = ACStem(args...; kw...)
```

## The consequences, and who pays them

| Consequence | Who it reaches |
| --- | --- |
| `show` and `nameof` print the coded name | only a schema that rebinds. A `[C]` schema keeps its struct name, so `show` still prints `JsonString{Cell, Cell}`. |
| `_kind_of` must label from the family | only if a rebinding schema is reflected. Do it when one is. |
| `::Stem` narrows | only a rebinding schema, and for `[DC]` on a value document the measurement above says nothing narrows. |
| An import must gain a name | only where a rebinding schema is imported selectively and annotated. |
| `get_reference_node_type` | unchanged. It stays `document_cell_type`, which already crosses layouts. |

### The repository-wide alternative, and what it measured

Making **every** schema's bare name the concrete default spelling was tried and
measured on this checkout, then reverted:

| | Size |
| --- | --- |
| `::DocName` → `::ADocName` | 1774 lines in 162 files |
| Field declarations that must be excluded | 515 |
| Selective imports needing an `A` name | 608 lines across 210 files |
| `get_reference_node_type` → `document_family` | forced, in the same commit |

Two traps came out of it. A field declaration must not be swept — `left::EvalLeaf`
widened to `::AEvalLeaf` makes `ICStem`/`MCStem` hold an abstract type, so nothing
inlines and a value document stops being isbits. And a hand-written type that
shares a document's name must not be swept either; the kernel test's `CellVector`
stand-in is one.

A first run of the sweep reported 1855 lines and 434 fields. Those numbers were
wrong: the field detector required the line to end at the type, so a field with a
trailing comment was swept. 1774 and 515 are the corrected figures.

The per-schema binding above gets the same benefit at the three sites that want
it, for none of that.

---

# Part 3 — how a declaration picks its variants — **DONE, except the bare name**

The grammar, the emission control and `@document_preset` are built. The **first
entry binds the bare name** rule is not, because before Part 2 the bare name is
the stem's own struct name and there is no renaming machinery to move it. The list
today decides only *which* layouts a schema emits. The binding rule lands with
Part 2.

The default list is `[C, M]`, today's emission, so nothing changed for any
existing declaration.

| Suite | Before Part 3 | After |
| --- | --- | --- |
| `test_kernel()` | 1486 / 3 / 2 | 1498 / 3 / 2 (twelve new assertions) |
| `test_base()` | 387 | 387 |
| `test_visual()` | 52659 pass, 1 broken | 52659 pass, 1 broken |

## The grammar

```
@document [layouts] struct T [<: Super] … end
@document Kind [layouts] struct T … end
@document_preset name [layouts]
```

The layout list holds **layout codes only**: `C`, `CD`, `M`, `I`. The **first
entry binds the bare name**, per Rule 3 in Part 2:

| First entry | `Stem` binds to |
| --- | --- |
| `C` — the default | `ACStem`, the cell layout UnionAll. Today's meaning. |
| `DC` | `DCStem`, the concrete default spelling. |
| `M` | `MStem`, the mutable native struct. |
| `I` | `IStem`, the immutable native struct. |

`DC` is a *binding*, not a fourth layout: it emits nothing that `C` does not
already emit, and only says which name the bare one points at. So `[DC]` and
`[CD, M]` still emit the cell layout, and `[DC]` is `[C]` with the bare name moved
one step in.

The existing field-kind marker keeps its place and comes first when both appear.
It does not select a layout. One word must not carry two meanings.

## What is opt-in and what is always there

| Emission | Rule |
| --- | --- |
| `AStem` | always. Two layouts must share a family. |
| `IStem`, `MStem`, `ACStem` | opt in. Each is a real struct with constructors. |
| `ICStem`, `MCStem`, `RCStem`, `DCStem` | come with `C`, never listed. A `const` costs nothing. |

A list with no `C` is allowed, for a document nothing ever observes.
`document_cell_type` then returns `nothing`, and `sync_document!` must say so
plainly rather than fail deep in the walk.

**As built, two codes are refused by name rather than emitted.**

- `M` and `I` together. One schema has one native struct, because
  `document_native_type` gives one answer, so a list that asked for two is refused
  by name rather than resolved by a rule nobody would remember.
- A list with no `C`. The cell layout carries the four aliases, the auto-wrapping
  constructor, the accessors and Rule Y, so leaving it out is a restructure of the
  whole expansion and no caller wants one yet.

Both raise an error that names the reason. Add either when something asks.

## Presets, not a module-level default

A preset defines a macro. The call site names it, so a reader of one file always
knows what a declaration emits.

```julia
@document_preset native_document [M, C]     # once, in the package root module
```

The alternative was a module-level constant that `@document` reads from
`__module__` at expansion time. It works, and it was rejected: it makes two
identical-looking declarations expand differently, and the reader must find a file
they were not looking at.

| | List at every site | Module constant | Preset macro |
| --- | --- | --- | --- |
| Repetition | 583 sites carry a list | none | 127 sites write a longer name |
| Hidden input | none | **yes** | none |
| Change the set later | 127 edits | 1 edit | 1 edit |
| One file tells the reader | yes | **no** | yes |

**Built, and one thing it taught.** A preset cannot expand into a `@document`
macrocall: the caller's struct definition would go through a second round of
hygiene and come out renamed. The whole expansion is now a function,
`_document_expr(args)`, that both `@document` and a preset call. A preset is the
same expansion with a layout list put in front of the arguments, which is also why
a field-kind marker still reaches it: `@native_document ImmutableCell struct …`.

## The presets that exist after this plan

| Preset | List | Bare name | Who uses it |
| --- | --- | --- | --- |
| `@document` | `[C, M]` today, `[C]` once the native emission is dropped | `ACStem` | projectured-julia, 432 schemas |
| written out, `[DC]` | `[DC]` | `DCStem` | the three value documents: `StyleText`, `StyleFont`, `StyleColor` |
| `@native_document` | `[M, C]` | `MStem` | omnetpp-julia, 127 schemas |

`I`, the immutable native struct, has a caller: `inet-julia`'s `@header` emits
`[I, C]`. A header is a value on a simulation's hot path, and a `mutable struct`
is never isbits however small its fields are — `EthernetFcs` is 4 bytes inline as
`IEthernetFcs` and a heap reference as `MEthernetFcs`.

---

# Part 1 — the layout registry (decided)

The fix for Fact 1, Fact 2 and Fact 3. It changes no name, so it lands first and
alone, before Part 2 renames anything.

## 1.1 Emit the registry — **DONE**

`@document` already emits `document_family`. Emit two more methods beside it, one
per layout.

```julia
document_family(::Type{<:AStem})      = AStem     # exists today
document_cell_type(::Type{<:AStem})   = ACStem     # nothing when C is not emitted
document_native_type(::Type{<:AStem}) = MStem     # nothing when M is not emitted
```

Both accessors take any variant, because every variant subtypes the family. A
hand-written document falls back to itself for both, so the protocol is total.

As built, under today's names: `document_cell_type` answers the stem and
`document_native_type` answers `FooMut`. The fallbacks live in
`DocumentDefaults.jl` — a plain type is its own cell layout and has no native one,
so a hand-written document copies into exactly what it was. `document_native_type`
returns `nothing` rather than a type, so a caller must handle a schema with no
native layout instead of assuming the pair is always complete.

`test_kernel()` went from 1461/3/2 to 1469/3/2. The eight new assertions are the
registry testset. The three failures and two errors are the pre-existing Rule C
ones and are unchanged.

## 1.2 Let `copy_document` choose the layout — **DONE**

`copy_document(K, doc)` builds through `Base.typename(T).wrapper`, which is the
source's own layout. Build through the registry instead, and pick the target from
`K`:

- `K === MutableCell` and the schema has a native layout → the native struct.
- every other `K` → the cell layout.

A source of any layout then copies into the layout the target kind wants. This
alone fixes Fact 2, because `copy_shadow_element` calls exactly this function.

**As built, every kind targets the cell layout.** A kind is a property of a cell,
so a kinded copy only means something in a tree that has cells. Routing
`MutableCell` to the native struct instead is Open Question 2 and is deferred: it
would change what an existing caller gets, and no caller asks for it. The four
call sites in this repository that pass a kind all pass `ImmutableCell`.

The two arities now differ in layout as well as in kind. `copy_document(doc)`
preserves the layout, so a native document copies into a native one.
`copy_document(K, doc)` targets `document_cell_type`.

One rule needed care. The old code wrapped a field in `K` when the **source**
field held a cell. That is wrong once the source can be native, because the target
is a cell layout whose every field is a cell slot. The test is now the target:
`_declared_value_types` is emitted for exactly the macro-emitted schemas, so its
presence says every field of the cell layout is a cell. A hand-written document
has no such method, so there the source's own field shape stays the truth and the
behaviour is what it was.

A schema with no cell layout raises a plain error rather than calling `nothing`.

**Measured.**

| Suite | Clean main | With the change |
| --- | --- | --- |
| `test_kernel()` | 1461 / 3 / 2 | 1479 / 3 / 2 |
| `test_base()` | 387 / 0 / 0 | 387 / 0 / 0 |
| `test_visual()` | 52659 pass, 1 broken | 52659 pass, 1 broken |

The 18 extra kernel passes are the new assertions: 8 for the registry, 10 for the
layout rules. The three failures and two errors are the pre-existing Rule C ones.
`test_visual()` is byte-identical, which is the evidence that the change is a
no-op for every document that exists today — this repository has no native
document, and for a cell-layout source the new code path is the old one.

Both new testsets were checked against the unfixed file: they fail without it.

## 1.3 Say what a shadow is — **DONE**

`sync_document!` reads `K = get_cell_struct_kind(shadow)`, which returns `nothing`
for a native node. A native node inside a reactive shadow therefore crashes the
walk on the next new child. After 1.2 a native node can no longer get into a
reactive shadow, so this is the guard rail, not the fix.

**Built differently from the sketch above, and here is why.** The sketch said to
carry the root's kind down the walk instead of re-reading it per node. That would
change a working case: a shadow may hold a subtree of a different kind, and
re-reading builds a new child in the kind that is actually there, which is the
faithful answer. So the per-node read stays.

What is left is the case where the shadow tree has no cells at all — a native
document, or a hand-written one whose first field is raw. Nothing in such a tree
can invalidate a reader, so it is not a shadow. The walk now says that, in one
sentence, at the one place a child is built. Before, it failed several frames down
as a `copy_document` method that does not exist.

This cannot break a working case, because every case it catches already threw.

`copy_shadow_element` became the single place a child is rebuilt.
`_synced_child` now calls it instead of repeating the rule, which is what the
sketch asked for in its last line.

`test_kernel()` 1479 → 1481 for the two new assertions. `test_base()` unchanged at
387, and `BoundedSyncTest.jl` — the main `sync_document!` user — lives there.

## 1.4 Make a reference layout-independent — **DONE, by a different token**

The sketch said to return `document_family(document)`. **Do not.** It was measured
and it breaks the reference layer.

| Suite | Before | With `document_family` |
| --- | --- | --- |
| `test_kernel()` | 1481 / 3 / 2 | 1472 / **12** / 2 |
| `test_visual()` | 52659 pass, 1 broken | 52606 pass, **24** fail, **5** error |

The plan claimed "both sides of every comparison are computed by this one
function". That is false, and the two failure shapes say why.

```
Evaluated: ::AbstractEvalDoc.child::AbstractEvalChild.n  ==  ::EvalDoc.child::EvalChild.n
Evaluated: AbstractEvalBranch === EvalBranch
```

1. Reference equality is `a.type === b.type`. One side is annotated at run time,
   the other is a literal the `@reference` macro emitted. Widening one alone
   parts them.
2. Pattern matching is `_type_step_matches(nodetype, T) = … || nodetype <: T`. The
   family is a **supertype** of the stem, so `AbstractFoo <: Foo` is false and
   every `::Foo` arm stops matching.

So a family token would need every reference literal and every pattern swept
first, which couples this step to Part 4.

**Built with the cell layout as the token instead.**

```julia
get_reference_node_type(document) = document_cell_type(document)
```

For a cell-layout node this is what it always was, because a schema's
`document_cell_type` **is** its name wrapper. For a native node it now answers the
same token as its cell twin. So a path built while the simulator runs equals a path
built on the shadow the editor draws, and it still matches a pattern written with
the bare name. Nothing has to be swept, and the token stays a subtype relationship
that `<:` accepts.

| Suite | Clean | With the change |
| --- | --- | --- |
| `test_kernel()` | 1481 / 3 / 2 | 1486 / 3 / 2 (five new assertions) |
| `test_base()` | 387 | 387 |
| `test_visual()` | 52659 pass, 1 broken | 52659 pass, 1 broken |
| `test_json()` | 169 | 169 |

**One gap stays open, deliberately.** Validation is `document isa path.type`. A
**native** document is not `isa` its cell layout, so `is_valid_reference` still
fails against a native tree. The direction that matters works: the editor
validates against the shadow, which is a cell tree. Fix it when a caller wants to
validate against the simulator's own tree; it is one predicate, in a sealed file.

## 1.5 Tests — **DONE**

Written with each step rather than after them all.

1. A native source and a cell shadow. A new child appears. The shadow child holds
   cells, and a `ComputedCell` over it runs again after the next sync.
   `DocumentContractTest.jl`.
2. `copy_document(ReactiveCell, native)` returns the cell layout, and the plain
   `copy_document(native)` still returns a native one. `DocumentContractTest.jl`.
   The `copy_document(MutableCell, cell_doc)` half is not written, because 1.2
   deliberately routes every kind to the cell layout. It belongs with Open
   Question 2.
3. A path annotated on a native node equals the path annotated on its cell twin,
   and evaluates on the cell tree. `ReferenceEvalTest.jl`.

Each testset was checked against the unfixed source and fails without it.

One thing the tests taught. `MEvalBranch.left` is typed to one schema, so it
holds a **cell** leaf and not a native one — the limit the older plan described,
and it is real for a field that names a schema. A field typed `Document` takes
either layout, which is why the bug in Fact 2 was reachable. Both statements are
true and they are about different field types.

## 1.6 Let a schema say its own name — **DONE**

Not foreseen here. It was forced by Part 4.2, and it belongs with the registry
because it answers the same kind of question.

`nameof` cannot name a schema. A coded name is a type's real name and the bare
name is a `const` alias, so a schema that bound its bare name elsewhere answers
the coded one — `nameof(ChainModel)` is `:MChainModel`. Anything that *displays*
that name then reads as the layout rather than as the thing. omnetpp's catalog
began showing `MChainModel — K tokens hop along a linear chain` in the user
interface, and nine test failures followed it.

`document_schema_name` answers what the programmer wrote after `struct`, for every
layout, and defaults to `nameof` — right for a hand-written document and for any
schema that left its bare name where it was.

The reflection label in `_kind_of` now uses it. Part 2 had listed that as required
work for the day a rebinding schema was reflected; this was that day.

---

# Part 4 — the sweeps (decided)

There is **no repository-wide annotation sweep.** The per-schema binding in Part 2
removed it. A sweep now touches only the schemas that rebind their bare name, and
in projectured-julia those are three.

## 4.1 projectured-julia

| Rewrite | Sites | State |
| --- | --- | --- |
| `RDocName` / `IDocName` / `MDocName` → `RCDocName` / `ICDocName` / `MCDocName` | 19 | **DONE** |
| `AbstractDocName` → `ADocName` | 42 in `.jl`, 5 in `.md` | **DONE** |
| `DocNameMut` → `MDocName` | 17 | **DONE** |
| `DDocName` → `DCDocName` | 480, of which 455 are `DStyleText` | **DONE** |
| the three styles take `[DC]`; their sites drop the `DC` | the same 479 | **DONE** |
| `::StyleText` / `::StyleFont` / `::StyleColor` annotations | 371, inspected, none rewritten | **DONE** |

The last row was the only place narrowing could bite, and it did not. 267 of the
371 are field declarations, where a concrete type is the point. The rest are
signatures, and nothing can hand them a non-default spelling: a reactive style is
named in three comments and built nowhere, and the only production call that
copies with an explicit kind is `_pure_snapshot`, which lands on the default
spelling for a value document.

## 4.2 omnetpp-julia and inet-julia — **DONE**

It came in two halves, and the first was not optional. Both repositories resolve
against projectured's live checkout, so the moment Part 2 landed on `main` neither
of them loaded:

```
UndefVarError: `AbstractParameterAssignment` not defined in `OmnetppSimulator`
```

**Phase A, the restore.** Mechanical, forced, no decisions.

| Rewrite | omnetpp | inet |
| --- | --- | --- |
| `Abstract<Doc>` → `A<Doc>`, this repository's own schemas | 846 | 154 |
| `Abstract<Doc>` → `A<Doc>`, projectured's families named from here | 20 | — |
| `<Doc>Mut` → `M<Doc>` | 260 | 21 |
| `I<Doc>`/`D<Doc>` → `IC<Doc>`/`DC<Doc>` | 14 | 9 |
| files | 117 | 18 |

The generated `PrecompileStatements.jl` in each repository is left alone. It says
not to edit it and is built to skip a statement that names nothing, so its stale
entries cost coverage and nothing else. A first pass rewrote omnetpp's before that
was noticed; a half-renamed record is worse than a stale one, so it was reverted.

**Phase B, the bare name.** 25 schemas bind theirs to the struct the engine
mutates — 8 in omnetpp, 17 in inet. Each was chosen on evidence, not by category:
built through the native layout, never through the bare name.

| | omnetpp | inet |
| --- | --- | --- |
| schemas | 128 | 21 |
| rebound to `M` | 8 | 17 |
| presets declared | 2 | 3 |

The schemas that go the other way keep their default. inet's four diagram types
are built only through the bare name and `PacketDiagram` carries five
projection-side annotations, so for them the bare name stays the cell layout.

**What Phase B found that this plan had not.** `nameof` is the wrong question once
a bare name can be a `const` alias. Four places in omnetpp displayed a model's name
that way, and the catalog began reading `MChainModel — K tokens hop along a linear
chain` in the user interface. That produced `document_schema_name`, described in
Part 1.6.

**Measured, each at its own pre-existing baseline.**

| Suite | Before | After |
| --- | --- | --- |
| omnetpp `test/runtests.jl` | did not load | 9188 passed, 3 failed, 1 errored |
| inet `test/runtests.jl` | did not load | 2923 passed, 0 failed, 7 errored |

Every one of those eleven predates this work, and each was checked against its
subject rather than assumed:

- Two omnetpp `FilesTest` failures compare `.ned` and `.ini` fixtures against an
  external `omnetpp-cpp/samples/routing` checkout. The sweeps touched only `.jl`
  and `.md`.
- One `ModuleViewsTest` failure asserts a `→` in tree rows. `ModuleViews.jl` was
  edited, and every line of that diff is `AbstractX` → `AX`: same type, same
  dispatch.
- Six inet errors are one signature drift. omnetpp's `record_tap!` takes a
  `ScheduleContext` as of `00f7dff Wave D`; inet still passes a timestamp. The
  name sweep touched that file and changed no `record_tap!` line.
- Two runner test environments lack `Pkg`, and `package/simulator/test` lacks
  `UUIDs`. No `Project.toml` was touched. These also mean a per-slice run tells
  you less than it appears to: three slices never reach their first assertion, so
  a grep for failures reports zero. Use the root environment.

**Three mistakes, all the same shape, all caught by a suite.** A name added in one
place while a second place keeps its own list: `_emit_keyword_ctors` with its own
prefixes, the binding branch still testing `:CD` after the code became `:DC`, and
two submodules with their own import lists. None would have been caught by a
targeted test.

### What was left for the earlier plan's annotation split

The `::DocName` split described below was written before the per-schema binding
existed. With 25 schemas rebound rather than all of them, the split applies only
to those, and it was done as part of choosing each one. The reasoning stands and is
kept:

Each annotation belongs to one side of the sync, and the new names let it say which:
belongs to one side of the sync, and the new names let it say which:

- **Simulation side** — narrows to the bare name, which is now the native struct.
  `simulation_run(instance::AbstractSimulationInstance)` becomes
  `simulation_run(instance::SimulationInstance)`. The signature then says what is
  true: this runs on the object the simulator mutates. There is no cell
  `SimulationInstance` in the repository at all — every construction is
  `SimulationInstanceMut`.
- **User-interface side** — gains a `C`. A projection's printer must be typed to
  the cell layout, because its cells read fields and have to register a
  dependency. `print_document(p, recursion, instance::SimulationInstance, ctx)`
  becomes `instance::ACSimulationInstance`, and the body does not change.

That type is load-bearing, not decoration. A printer that accepted the native
struct would run `set_cell_function!(w, () -> instance.prepared)` against a plain
field, register no dependency, and paint once and never again. Typing it
`ACSimulationInstance` makes that a method error instead of a silent freeze.

Nothing about syncing changes. It is one generic call and stays one
([SimulatorMonitor.jl:21-25](../omnetpp-julia/package/simulator/main/src/telemetry/SimulatorMonitor.jl#L21-L25)):

```julia
function refresh_monitor!(m::ASimulatorMonitor, native)
    m.sampler === nothing || sample!(m.statistics, m.sampler, native)
    sync_document!(m.simulator, native)
    m
end
```

The only place a layout is named is where the shadow is built, once per engine.

## 4.3 The rename hazard

**Do not run a bare `\bAbstractFoo\b` rewrite over the tree.** A word-boundary
rename also rewrites `"AbstractFoo.jl"` inside an `include` call and inside a
documentation link. Exclude string literals, then read the diff for every `.jl`
and `.md` token that moved.

Check for a collision before each sweep. A coded name such as `AStem` or `ACStem`
must not already name something else in the same module.

---

# How the code changes

## projectured-julia

A declaration does not change. `@document` keeps its meaning and its default list.

```julia
@document struct JsonArray <: JsonDocument
    elements::CellVector = CellVector()
    collapsed::Bool = false
end
```

A signature does not change either, because `JsonString` still means what it
means today.

```julia
_json_native(j::JsonString) = String(j.value)
```

A configuration field loses the `D` prefix, and keeps the concrete type that made
the prefix necessary.

```julia
# before
delim::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
# after
delim::ImmutableCell{StyleText}  = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
```

A value-document opts in, once, and then reads as what it is.

```julia
# before
@document ImmutableCell struct StyleText
    font::DStyleFont
    color::DStyleColor
    selection::Nothing
end
# after
@document ImmutableCell [DC] struct StyleText
    font::StyleFont
    color::StyleColor
    selection::Nothing
end
```

## omnetpp-julia

A declaration names its preset once, and the bare name becomes the struct the
simulator runs on.

```julia
# before
@document struct TicTocMessage1
    name::String
end
# after
@native_document struct TicTocMessage1
    name::String
end
```

The hot path loses the suffix. This is the point of the plan.

```julia
# before
NetworkModule.start_module!(ctx, m::Txc1) =
    (send_message!(ctx, m.out, TicTocMessage1Mut("tictocMsg")); m)
# after
NetworkModule.start_module!(ctx, m::Txc1) =
    (send_message!(ctx, m.out, TicTocMessage1("tictocMsg")); m)
```

A signature shortens, and says the same thing.

```julia
# before
dup(m::AbstractTicTocMessage1) = TicTocMessage1Mut(m.name)
dup(m::AbstractTicTocMessage2) =
    TicTocMessage2Mut(m.name, m.source, m.destination, m.hop_count)
# after
dup(m::ATicTocMessage1) = TicTocMessage1(m.name)
dup(m::ATicTocMessage2) =
    TicTocMessage2(m.name, m.source, m.destination, m.hop_count)
```

The two sites that genuinely choose a layout now say so, and they are the only
sites that name a coded type.

```julia
# before
SequentialSimulator(n_modules::Int) = SequentialSimulatorMut(_initial_sim_fields(n_modules)...)
reactive_simulator(n_modules::Int)  = SequentialSimulator(_initial_sim_fields(n_modules)...)
# after
SequentialSimulator(n_modules::Int) = MSequentialSimulator(_initial_sim_fields(n_modules)...)
reactive_simulator(n_modules::Int)  = ACSequentialSimulator(_initial_sim_fields(n_modules)...)
```

An export list shortens.

```julia
# before
export TicTocMessage1, TicTocMessage1Mut, AbstractTicTocMessage1,
       TicTocMessage2, TicTocMessage2Mut, AbstractTicTocMessage2, dup
# after
export TicTocMessage1, ACTicTocMessage1, ATicTocMessage1,
       TicTocMessage2, ACTicTocMessage2, ATicTocMessage2, dup
```

### The two sides of the sync, said in the signatures

A **simulation-side** accessor narrows to the bare name, which is now the native
struct. Today it names the family, which is wider than the truth: nothing runs a
simulation on a cell variant.

```julia
# before
simulation_run(instance::AbstractSimulationInstance)        = instance.run
simulation_parameters(instance::AbstractSimulationInstance) = instance.run.params
model_module_count(instance::AbstractSimulationInstance)    = model_module_count(instance.model)
# after
simulation_run(instance::SimulationInstance)        = instance.run
simulation_parameters(instance::SimulationInstance) = instance.run.params
model_module_count(instance::SimulationInstance)    = model_module_count(instance.model)
```

A **projection printer** goes the other way and gains a `C`. Its body does not
change at all.

```julia
# before — `SimulationInstance` is the UnionAll over the cell spellings, so it
# already excludes the native struct.
function print_document(p::SimulationInstanceToWidget, recursion,
                        instance::SimulationInstance, ctx)
    id_label = WidgetLabel(Point2D(0, 0), "")
    set_cell_function!(id_label, () -> "build: " * string(instance.id))

    state = WidgetBadge(Point2D(0, 0), "Built")
    set_cell_function!(getfield(state, :content),
                       () -> instance.prepared ? "Prepared" : "Built")
    ...
end

# after — the bare name is the native struct, so the printer says C to keep
# meaning what it meant.
function print_document(p::SimulationInstanceToWidget, recursion,
                        instance::ACSimulationInstance, ctx)
    ...unchanged body...
end
```

That type is load-bearing. A printer that accepted the native struct would run
`set_cell_function!(w, () -> instance.prepared)` against a plain field, register
no dependency, and paint once and never again. Typing it `ACSimulationInstance`
turns a silent freeze into a method error.

---

## What this does not buy

I measured the cost of a type that nobody calls, over 435 synthetic schemas.

| 435 schemas | Precompile | Image | Load |
| --- | --- | --- | --- |
| No native struct | 3.18 s | 243 KB | 6 ms |
| Plus the struct only | 3.69 s | 294 KB | — |
| Plus the struct, 2 constructors, 1 export | 4.56 s | 350 KB | 12 ms |

An unused type costs about 3.2 ms of precompile and 245 bytes of image. All 435
unused native structs add about 1.4 s and 107 KB, near 1.6 % of the 6.47 MB
`ProjecturedKernel.ji`. The precompile figures carry about ±1 s of noise. The run
time cost is zero, because Julia never infers a method that nobody calls.

**So do not justify Part 3 on cost.** Justify it on what a reader must hold in
their head: fewer names, no near-synonyms, and less namespace pressure across
583 schemas.

## What to measure

Before and after, on a clean checkout:

1. `test_kernel()` counts, against a base-commit run made the same way.
2. A full-suite diff. A wide macro change is exactly the case where a targeted
   test passes and the suite gains errors.
3. Precompile wall time, for the record. Expect it to be inside the noise.

---

## Sealed files

Two files in the plan are sealed. Ask for explicit permission before either is
touched.

- 🔒 `package/kernel/main/document/DocumentMacro.jl` — Part 1.1, Part 2, Part 3.
- 🔒 `package/kernel/main/reference/ReferenceEvaluation.jl` — Part 1.4.

These are not sealed and need no permission:

- `package/kernel/main/document/DocumentCopy.jl` — Part 1.2.
- `package/kernel/main/document/DocumentSync.jl` — Part 1.3.
- `package/kernel/main/document/DocumentInterface.jl` — the two new declarations.
- `package/kernel/main/document/DocumentModule.jl` — the exports.
- `package/base/main/reflection/DocumentReflection.jl` — the label.
- `package/base/main/domain/Domain.jl` — `_is_layout_variant`.

## Steps

| | Step | State |
| --- | --- | --- |
| 1 | Part 1.1 to 1.5, the layout registry. Renames nothing. | **DONE** |
| 2 | Part 3, the layout list and `@document_preset`. Default keeps today's emission. | **DONE** |
| 3 | Part 2, steps 2a to 2c, the coded names for the spellings, the family and the native layout. | **DONE** |
| 4 | Step 2d, `DStem` → `DCStem`. | **DONE** |
| 5 | Step 2f, the bare-name binding rule, the `DC` code, `const ACStem = Stem`. | **DONE** |
| 6 | Step 2e, the three styles take `[DC]`; their 479 sites drop the prefix. | **DONE** |
| 7 | Step 2g, every name reads as a phrase. | **DONE** |
| 8 | Part 1.6, `document_schema_name`. Forced by step 9. | **DONE** |
| 9 | Part 4.2, omnetpp-julia. This is where 2f is proved. | **DONE** |
| 10 | inet-julia. | **DONE** |

Every projectured step runs the representative set: `test_kernel`, `test_base`,
`test_visual`, `test_json`, `test_sql`, `test_julia`. About 55 000 assertions and
two minutes. `test_all()` is not used — it takes 47 minutes, so it cannot be run
on both sides of every step.

The baseline the set holds at, after this work: kernel 1526/3/2, base 387, visual
52659 pass with 1 broken, json 169, sql 353, julia 42. It was 1461/3/2 for the
kernel before Part 1; every added pass is an assertion this plan wrote.

The other two repositories run their whole suite from the **root** environment,
`julia -t 4 --project=. test/runtests.jl`. Three of omnetpp's test packages and one
of inet's cannot resolve standalone, and a per-slice run therefore reports zero
failures while never reaching its first assertion.

## Open questions

1. ~~Does the immutable native layout `IStem` have a caller?~~ **Answered.**
   `inet-julia`'s `@header` asks for one, so `I` is emitted. A header is an
   immutable value and a `mutable struct` is never isbits.
2. Should `copy_document(MutableCell, doc)` really pick the native layout, or
   should the caller pass a layout beside the kind? The first is terse. The second
   is explicit and cannot surprise a caller who wants `MCStem`.
3. Is `AStem` right, against the Julia idiom `AbstractStem`? `AStem` is regular
   with the other seven names. `AbstractStem` is what a Julia reader expects. The
   decision is `AStem`, for one system over one idiom.
4. Should `@document`'s default list drop `M`? Every projectured schema emits a
   native struct that nothing uses. It costs about 1.4 s of precompile and 107 KB
   across 435 schemas, so the reason would be namespace clarity, not cost.
5. ~~Does anything call `copy_document(ReactiveCell, ·)` on a style?~~ **Answered:
   no.** A reactive style is named in three comments and built nowhere, and the
   only production call that copies with an explicit kind is `_pure_snapshot`,
   which for a value document lands on the default spelling.

## What this plan leaves undone

1. ✅ **RESOLVED (2026-08-12). `Packet`, in both omnetpp-julia and inet-julia.**
   The one schema whose evidence did not point one way is now decided:
   `inet-julia`'s `package/packet/main/PacketEnvelope.jl` declares
   `@native_document struct Packet <: Document`, so `Packet` took the `M`
   binding. Every other schema in both repositories was already settled.
2. ✅ **RESOLVED (2026-08-12). inet-julia calls `record_tap!` with the old
   signature.** omnetpp's commit "Give the tap the context the kernel asks for"
   fixed the tap side, and inet-julia's callers in
   `package/queuing/main/QueuingCapture.jl` and
   `package/linklayer/main/t1s/T1sCapture.jl` now pass `ctx` in the
   `ScheduleContext` position. This predated this plan and nobody owned it; it is
   fixed independently of it.
3. ✅ **RESOLVED (2026-08-12). Three test environments cannot resolve
   standalone.** `package/runner/test` and `package/simulator/test` in omnetpp,
   `package/runner/test` in inet. All three now resolve and instantiate cleanly
   (`Pkg.resolve()` / `Pkg.instantiate()` with no error); the omnetpp `runner`
   suite runs 704/704 standalone. No `Project.toml` was touched by this plan; the
   defects were already there and are now gone, fixed independently of it.
4. **Still open. The recorded precompile statements were 9.1 % stale in
   projectured**, against a 10 % warning threshold, and 709 of the 1165 skips
   were this plan's renames. The next change that moves a type name crosses the
   line. Recording needs a display, so it is the owner's call. Both other
   repositories left their own recordings untouched for the same reason. This
   figure was not re-measured for this audit; treat it as unverified rather than
   fixed.
5. **Still open. Two sealed files are unsealed** and marked ⬜ in `CLAUDE.md`,
   still awaiting review as of 2026-08-12:
   `document/DocumentMacro.jl` and `reference/ReferenceEvaluation.jl`.
