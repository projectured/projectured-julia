# Document layouts and their names

> **Status: PENDING.** No code is written yet. Part 1 to Part 4 are decided. The
> work needs permission to edit two sealed files. See **Sealed files**.

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

`@document struct Stem … end` emits this system. A name is built from a layout
letter, then a kind letter, then the schema name.

| Name | What it is |
| --- | --- |
| `AStem` | the family. Abstract. It matches every variant. |
| `IStem` | the immutable native struct. Plain `struct`, value fields. |
| `MStem` | the mutable native struct. Plain `mutable struct`, value fields. |
| `CStem` | the cell layout. `CStem{C1<:AbstractCell, …}`, one cell per field. |
| `CIStem` | `CStem{ImmutableCell{T}, …}` |
| `CMStem` | `CStem{MutableCell{T}, …}` |
| `CRStem` | `CStem{ReactiveCell{Any}, …}` |
| `CDStem` | `CStem{per-field default}` |
| `Stem` | a `const` alias for the variant the declaration picks. `CDStem` by default. |

Three rules make the system regular.

1. **The coded name is always the type's real name.** `Stem` is always a `const`
   alias. This is forced: when the default is `CDStem`, the bare name denotes one
   *spelling*, and a spelling cannot be a struct's own name.
2. **`AStem` is the dispatch type.** It is strictly better than today's bare
   `Foo`, which is the UnionAll `Foo{C1,…}` and matches every cell spelling but no
   native layout. `AStem` matches both layouts.
3. **`Stem` is the common concrete case.** A field typed `Stem` is concrete and
   inlines. A signature typed `Stem` accepts the default spelling only.

## Why the bare name is concrete

The code already asks for this. `DStyleText` has 454 uses, and they all look like
[CollectionToSyntax.jl:35](package/visual/main/syntax/CollectionToSyntax.jl#L35):

```julia
delim::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
```

The comment at [StyleText.jl:28](package/visual/main/style/StyleText.jl#L28) says
why: "`DStyleText` is concrete and inlines in config cells". A field cannot inline
a UnionAll, so those sites had to reach past the bare name. Under this scheme they
write `ImmutableCell{StyleText}`, and the whole `D` prefix leaves the source.

## What the constructor builds

`Stem(args…)` keeps today's semantics exactly. A raw value wraps in its field's
default kind. A cell of any kind passes through as it is.

When the bare name binds to a cell spelling, the macro must emit a constructor for
the concrete form, because an inner constructor suppresses the parameterized
default:

```julia
(::Type{CDStem})(args...) = CStem(args...)
```

## The consequence to accept

`nameof(typeof(x))` gives `CStem`, and `show` prints `CStem{Cell, Cell, Cell}`.
The reflection label in `_kind_of`
([DocumentReflection.jl:165](package/base/main/reflection/DocumentReflection.jl#L165))
must therefore take its label from the family and strip the `A`. This is now
required work, not an option.

---

# Part 3 — how a declaration picks its variants (decided)

## The grammar

```
@document [layouts] struct T [<: Super] … end
@document Kind [layouts] struct T … end
@document_preset name [layouts]
```

The layout list holds **layout codes only**: `I`, `M`, `C`. The **first entry
binds the bare name**. A `C` in first place binds `Stem` to `CDStem`.

The existing field-kind marker keeps its place and comes first when both appear.
It does not select a layout. One word must not carry two meanings.

## What is opt-in and what is always there

| Emission | Rule |
| --- | --- |
| `AStem` | always. Two layouts must share a family. |
| `IStem`, `MStem`, `CStem` | opt in. Each is a real struct with constructors. |
| `CIStem`, `CMStem`, `CRStem`, `CDStem` | come with `C`, never listed. A `const` costs nothing. |

A list with no `C` is allowed, for a document nothing ever observes.
`document_cell_type` then returns `nothing`, and `sync_document!` must say so
plainly rather than fail deep in the walk.

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

## The two presets that exist after this plan

| Preset | List | Bare name | Who uses it |
| --- | --- | --- | --- |
| `@document` | `[C]` | `CDStem` | projectured-julia, 435 schemas |
| `@native_document` | `[M, C]` | `MStem` | omnetpp-julia, 127 schemas |

`I`, the immutable native struct, has no caller yet. Do not emit it until one asks.

---

# Part 1 — the layout registry (decided)

The fix for Fact 1, Fact 2 and Fact 3. It changes no name, so it lands first and
alone, before Part 2 renames anything.

## 1.1 Emit the registry

`@document` already emits `document_family`. Emit two more methods beside it, one
per layout.

```julia
document_family(::Type{<:AStem})      = AStem     # exists today
document_cell_type(::Type{<:AStem})   = CStem     # nothing when C is not emitted
document_native_type(::Type{<:AStem}) = MStem     # nothing when M is not emitted
```

Both accessors take any variant, because every variant subtypes the family. A
hand-written document falls back to itself for both, so the protocol is total.

## 1.2 Let `copy_document` choose the layout

`copy_document(K, doc)` builds through `Base.typename(T).wrapper`, which is the
source's own layout. Build through the registry instead, and pick the target from
`K`:

- `K === MutableCell` and the schema has a native layout → the native struct.
- every other `K` → the cell layout.

A source of any layout then copies into the layout the target kind wants. This
alone fixes Fact 2, because `copy_shadow_element` calls exactly this function.

Keep the rule in one private helper, so `copy_document` and `sync_document!`
cannot drift apart.

## 1.3 Let `sync_document!` read the kind from the tree, not the node

`sync_document!` reads `K = get_cell_struct_kind(shadow)`, which returns `nothing`
for a native node. A native node inside a reactive shadow therefore crashes the
walk on the next new child. Carry the shadow's kind down the walk instead of
re-reading it per node. After 1.2 a native node can no longer get into a reactive
shadow, so this is the guard rail, not the fix.

## 1.4 Make a reference layout-independent

Change `get_reference_node_type` to return `document_family(document)`.

A checkpoint then names the schema, not the layout, and a path built while the
simulator runs matches the same node in the shadow the editor draws. Both sides of
every comparison are computed by this one function, so the change is neutral for a
document that has one layout.

A literal type name inside `@reference` and `@reference_case` must name the family
after this change, so those literals join the Part 4 sweep and become `AStem`. A
hand-built type checkpoint already follows the rule "use `reference_node_type`,
never `typeof`", so a conforming site needs no edit.

## 1.5 Tests

1. A native source and a cell shadow. A new child appears. Assert the shadow child
   holds cells, and assert a `ComputedCell` over it runs again after the next sync.
2. `copy_document(ReactiveCell, native)` returns the cell layout.
   `copy_document(MutableCell, cell_doc)` returns the native layout.
3. A reference built on the native node evaluates on the cell node.

---

# Part 4 — the sweeps (decided)

## 4.1 projectured-julia

| Rewrite | Sites |
| --- | --- |
| `::DocName` → `::ADocName` | 2662 |
| `AbstractDocName` → `ADocName` | 43 |
| `DDocName` → `DocName` | 476, of which 454 are `DStyleText` |
| `RDocName` / `IDocName` / `MDocName` → `CRDocName` / `CIDocName` / `CMDocName` | 19 |

Step 1 is the one that matters. `::DocName` changes meaning silently, from "any
cell spelling" to "the default spelling only". Nothing fails to compile. A method
stops matching, and either a `MethodError` appears at run time or a more generic
method takes over quietly. Rewriting every one to `::ADocName` preserves today's
meaning at every site and widens it to cover the native layout. Narrow individual
sites back to `::DocName` afterwards, deliberately, and only where the concrete
default spelling is what the site means.

The risk is small even before the sweep, which is why the sweep is safe to do
mechanically:

| | Count |
| --- | --- |
| Schemas whose default spelling differs from all-reactive | **5** of 435 |
| `copy_document` calls with an explicit kind | 4 |
| Uses of an `R` / `I` / `M` alias | 19 |

For the other 430 schemas every field defaults to `ReactiveCell{Any}`, so `CDStem`
and `CRStem` are the same type.

## 4.2 omnetpp-julia

| Rewrite | Sites |
| --- | --- |
| `@document` → `@native_document` | 127 |
| `DocNameMut` → `DocName` | 76 |
| `AbstractDocName` → `ADocName` | 788 |
| `::DocName` → `::ADocName`, then narrow back | 179 |

## 4.3 The rename hazard

**Do not run a bare `\bAbstractFoo\b` rewrite over the tree.** A word-boundary
rename also rewrites `"AbstractFoo.jl"` inside an `include` call and inside a
documentation link. Exclude string literals, then read the diff for every `.jl`
and `.md` token that moved.

Check for a collision before each sweep. A coded name such as `AStem` or `CStem`
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

A signature widens to the family.

```julia
# before
_json_native(j::JsonString) = String(j.value)
# after
_json_native(j::AJsonString) = String(j.value)
```

A configuration field loses the `D` prefix, and keeps the concrete type that made
the prefix necessary.

```julia
# before
delim::ImmutableCell{DStyleText} = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
# after
delim::ImmutableCell{StyleText}  = StyleText(font_ubuntu_monospace_bold_20, color_solarized_gray)
```

A value-document reads as what it is.

```julia
# before
@document ImmutableCell struct StyleText
    font::DStyleFont
    color::DStyleColor
    selection::Nothing
end
# after
@document ImmutableCell struct StyleText
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
reactive_simulator(n_modules::Int)  = CSequentialSimulator(_initial_sim_fields(n_modules)...)
```

An export list shortens.

```julia
# before
export TicTocMessage1, TicTocMessage1Mut, AbstractTicTocMessage1,
       TicTocMessage2, TicTocMessage2Mut, AbstractTicTocMessage2, dup
# after
export TicTocMessage1, CTicTocMessage1, ATicTocMessage1,
       TicTocMessage2, CTicTocMessage2, ATicTocMessage2, dup
```

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

1. Part 1.1 to 1.5. One commit per numbered step. This lands alone and renames
   nothing.
2. Part 3, the layout list and `@document_preset`. The default list keeps today's
   emission, so nothing changes yet.
3. Part 2, the names, behind the new list. Measure.
4. Part 4.1, the projectured-julia sweep. Full-suite diff.
5. Part 4.2, the omnetpp-julia sweep, then inet-julia.

## Open questions

1. Does the immutable native layout `IStem` have a caller? It does not exist
   today. Do not emit it until one asks.
2. Should `copy_document(MutableCell, doc)` really pick the native layout, or
   should the caller pass a layout beside the kind? The first is terse. The second
   is explicit and cannot surprise a caller who wants `CMStem`.
3. Is `AStem` right, against the Julia idiom `AbstractStem`? `AStem` is regular
   with the other seven names. `AbstractStem` is what a Julia reader expects. The
   decision is `AStem`, for one system over one idiom.
