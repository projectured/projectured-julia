# Architecture review: the kernel model (cells, documents, projections, IO maps, operations)

Commit 3a9b4fae4. Reviewer area key: kernel-model.

## Scope

Paths: `source/kernel/{cell,struct,document,iomap,projection,intent,operation}`,
`source/platform/projection` (`higherorder`, `generic`, `compound`), `source/platform/domain`,
`source/platform/reflection`. For use: `source/domain/json`, `source/domain/sql`, `source/domain/fsm`.

Read in full (about 8 200 source lines):

- `source/kernel/projection`: all files but the head of `ProjectionModule.jl` (3 400 lines, with `ProjectionTemplate.jl`, 1 755 lines).
- `source/kernel/iomap`: all four files (305 lines).
- `source/kernel/intent/Intent.jl` (164 lines).
- `source/kernel/operation`: `OperationInterface.jl`, `Operations.jl`, `Rerooting.jl`, `Inversion.jl`, `PathChain.jl`, `OperationDefaults.jl` (1 603 lines).
- `source/kernel/cell`: `CellModule.jl`, `UntrackedCell.jl`, `ImmutableCell.jl`, `MutableCell.jl`, `CellDefaults.jl`, `CellComputation.jl` (335 lines).
- `source/platform/projection`: the module, `ReaderDefaults.jl`, `ProjectionDocument.jl`, the seven small higher-order files, `Chaining.jl`, `Sorting.jl`, `Filtering.jl`, `Identity.jl`, `Constant.jl`, the two compound files (about 1 500 lines).
- `source/domain/json/JsonToSyntax.jl`, `JsonDocument.jl`, `source/domain/fsm/FsmToFsmDiagram.jl`.

Sampled (heads, outlines by `grep`, and chosen functions): `DocumentInterface.jl` (lines 1 to 330),
`DocumentWalk.jl` (1 to 110), `DocumentModule.jl`, `Copying.jl`, `FaultCatching.jl`, `Searching.jl`,
`Focusing.jl`, `Reversing.jl`, `source/platform/domain/*` (module, `DocumentView.jl`, head of
`DocumentRelease.jl`, outline of `Domain.jl`), `source/platform/reflection/*` (module, heads),
`SqlToSyntax.jl` (outline and three nodes), `FsmDiagramToGraph.jl` (1 to 120).

Not read: `ReactiveCell.jl`, `CellInterface.jl`, `CellWriterCheck.jl`, `CellFaultScope.jl`, the three
files of `source/kernel/struct`, `DocumentMacro.jl`, `DeclaredType.jl`, `DocumentCopy.jl`,
`DocumentSync.jl`, `ForwardProtocol.jl`, `Description.jl`. For the document macro I used the guide
`documentation/package/kernel/macros.md` (lines 1 to 420) and counts by `grep`.

Documents read: `concepts.md`, `architecture-decisions.md`, the sections "Documents and domains",
"Projections", "References and selection" and "Operations" of `architecture-invariants.md`,
`projection-system.md`, and the heads of the plans named below. Every count in this report comes
from a `grep` over `source/` at this commit; where a count is a heuristic, the text says so.

## State

The model is sound at its centre. A projection is four functions, the recursion goes through
`print_child` and the stored child IO maps, and one reconciler keeps the IO map of each child. The
JSON domain shows what the model gives when it is used as designed: `JsonToSyntax.jl` has 193 lines
and no hand-written reference map and no hand-written reader.

The main weakness is that most of the mechanisms around this centre exist in two or more forms
that grew one after the other, and the older form was never taken away. The reader has two
signatures, and about 80 % of its 441 methods use the one that the rules call obsolete. A projection
that wraps one other projection has no shared base, so about two dozen projections repeat the same 20
lines, each with an IO map type of its own. An operation tells the readers how it travels in one of
five ways, and 38 functions walk into a compound operation by hand. The template engine has seven
shapes of node with 31 methods for them, and limits between the shapes. The generic sort, filter
and reverse of the projection algebra have no user in `source/` outside the projection slice
itself, because the product uses a newer stage in another slice.

None of these is a fault of the principles. Each is a place where the general rule exists already
(`WrappingOperation`, `PickingProjection`, `ContentIoMap`, the 4-argument reader, the tree slice)
and the code beside it does not use it yet.

## Inventory

### 1. Ways to define a projection

`print_document` is the printer, `read_intent` the reader, `map_reference_forward` and
`map_reference_backward` the two reference maps. `@projection_template` is the macro of
[ProjectionTemplate.jl:1732](../../../source/kernel/projection/ProjectionTemplate.jl#L1732) that writes the
printer and the reader from a builder function.

| Way | Count in `source/` | Output domains | Reference maps | Reader | Child IO maps kept by |
| --- | --- | --- | --- | --- | --- |
| Four hand-written functions | 403 `print_document` methods (kernel 7, platform 271, domain 119, adapter 6) | all | by hand: 213 forward and 203 backward methods in the platform, 76 and 79 in the domains | by hand, see table 2 | `ChildrenIoMap` or an IO map type of its own |
| `@projection_template` | 162 uses in 16 files (159 in domains, 3 in the platform) | syntax only | derived from the builder | derived, plus the gesture table of the document | the shared reconciler |
| Generic projections (`source/platform/projection/generic`) | 8 types | any | by hand, per projection | default or by hand | per projection |
| Higher-order projections (`higherorder`) | 9 types | any | delegate | delegate | see table 4 |
| View on demand | `ObjectToWidget` (313 lines), `ObjectToSyntax` (430), `ReflectionToWidget` (213) | widget, syntax, widget tree | by hand | by hand | by hand |

They are layers of one mechanism in one respect: all end in the four functions. They are parallel
in what the author must write. The template gives the maps, the reader delegation and the path
cells; every other way repeats them.

A projection type is declared in three ways: a plain `struct … <: Projection` (119), `@projection
UntrackedCell struct` (380), and `@projection struct` with reactive fields (15). So 96 % of the uses
of the macro name a kind that is not its default.

### 2. What a hand-written projection repeats (three domains)

Lines inside `print_document`, the two maps and `read_intent`, counted by an `awk` script over
top-level functions:

| File | Lines | Printer | Maps | Reader | Maps + reader |
| --- | --- | --- | --- | --- | --- |
| [SqlToSyntax.jl](../../../source/domain/sql/SqlToSyntax.jl) (20 hand-written nodes, 10 template rules) | 2 013 | 578 | 702 | 99 | 40 % |
| [JsonToSyntax.jl](../../../source/domain/json/JsonToSyntax.jl) (all template) | 193 | 0 | 0 | 0 | 0 % |
| [FsmToSyntax.jl](../../../source/domain/fsm/FsmToSyntax.jl) (all template) | 299 | 0 | 0 | 0 | 0 % |
| [FsmToFsmDiagram.jl](../../../source/domain/fsm/FsmToFsmDiagram.jl) (by hand) | 70 | 15 | 16 | 0 | 22 % |
| [MathToSyntax.jl](../../../source/domain/math/MathToSyntax.jl) (mixed) | 699 | 139 | 125 | 16 | 20 % |

One hand-written node, `SqlComparisonToSyntaxNode`
([SqlToSyntax.jl:888](../../../source/domain/sql/SqlToSyntax.jl#L888) to line 960), has 73 lines. About 8
say what the node looks like. The rest is: a cell of the child prints, a cell of the child IO maps,
the deferred IO map cell (`iomap_cell = Cell(nothing)`, 77 times in `source/`), the path cells, two
maps of 18 lines each, a reader of 3 lines that equals the default, and a catch-all reader that
answers `nothing`. `SqlToSyntax.jl` also calls `print_document(recursion, recursion, …)` 30 times
where the rule PAR-RECURSE-VIA-PRINT-CHILD asks for `print_child`.

### 3. Kinds of IO map

The kernel gives three: `SimpleIoMap` (projection, input, output), `ChildrenIoMap` (plus
`child_iomaps`) and `ContentIoMap` (plus `inner_iomap`), in
[IoMapDefaults.jl:58](../../../source/kernel/iomap/IoMapDefaults.jl#L58). `source/` declares 127 IO map
types: 125 with the macro `@iomap` and 2 plain structs. Three of them are the kernel shapes
themselves, so 124 are types of a projection. Their fields, grouped by shape:

| Shape | Types | Note |
| --- | --- | --- |
| exactly the fields of `SimpleIoMap` | 14 | for example `FsmToFsmDiagramIoMap`, `WordWrappingIoMap` |
| the fields of `ContentIoMap`, with the fourth named `inner_iomap` | 10 | |
| the same, named `child_iomap` | 11 | |
| the same, named `content_iomap` | 3 | |
| the fields of `ChildrenIoMap` | 1 | `GraphGraphToGraphLayoutIoMap` |
| other | about 85 | carry real data: tables of rows, coordinates, slots |

So 39 of the 124 types repeat a kernel shape under a name of their own.

Three services read an IO map by its shape, and each needs a method per type:

| Service | What it is | Methods |
| --- | --- | --- |
| `get_child_iomaps` | the child IO maps, so that an intent with a route reaches its child | 24, by hand; 9 of the 24 types with the shape of `ContentIoMap` have one |
| `get_content_iomap` | the IO map behind a wrapper that adds nothing | 2 (`ReferenceDispatchingIoMap`, `FaultCatchingIoMap`); about 34 calls |
| property forwarding (`Base.getproperty` to the inner IO map) | a parent reads a field of the child through the wrapper | 2 (the same two types) |

### 4. Higher-order and generic projections

"Transparent" means that the printer answers the IO map of the inner projection.

| Projection | IO map | The reader finds the inner projection by | The maps find it by | Choice follows a change | Uses in `source/` outside `source/platform/projection` |
| --- | --- | --- | --- | --- | --- |
| `RecursiveProjection` | transparent | its field | its field | — | 59 |
| `TypeDispatchingProjection` | transparent | the table again, by `iomap.input isa T` ([:60](../../../source/platform/projection/higherorder/TypeDispatching.jl#L60)) | `iomap.projection` ([:72](../../../source/platform/projection/higherorder/TypeDispatching.jl#L72)) | no (a type does not change) | 56 |
| `PredicateDispatchingProjection` | transparent | the predicates again ([:49](../../../source/platform/projection/higherorder/PredicateDispatching.jl#L49)) | the predicates again ([:64](../../../source/platform/projection/higherorder/PredicateDispatching.jl#L64)) | no | 1 |
| `ReferenceDispatchingProjection` | own plain struct with forwarding ([:86](../../../source/platform/projection/higherorder/ReferenceDispatching.jl#L86)), or transparent when `applies` answers false | the inner IO map | the inner IO map | yes | 2 |
| `SwitchingProjection` | own ([:10](../../../source/platform/projection/higherorder/Switching.jl#L10)) | the index cell again ([:70](../../../source/platform/projection/higherorder/Switching.jl#L70)) | the inner IO map | yes | 0 |
| `NestingProjection` | own, field `child_iomap` | its fields | its fields | — | 15 |
| `WindowInputUnwrappingProjection` | own, field `inner_iomap` | its field | its field | — | 0 |
| `FaultCatchingProjection` | own mutable struct with forwarding | — | through the inner | — | 25 |
| `ChainingProjection` | own, a cell per stage | each stage in turn | each stage in turn | yes, per stage | 115 |
| `CopyingProjection` | own; four printers by kind of input | — | — | yes | 11 |
| `SortingProjection`, `FilteringProjection` | own; three printers by kind of input each | — | — | yes for a `CellVector` | 0 |
| `ReversingProjection`, `SearchingProjection`, `FocusingProjection`, `ConstantProjection` | `ChildrenIoMap`, own, `SimpleIoMap`, `SimpleIoMap` | — | — | — | 0 |

Pairs that need code of their own:

- `RecursiveProjection` with a template IO map: three methods that only remove an ambiguity ([ReaderDefaults.jl:80](../../../source/platform/projection/ReaderDefaults.jl#L80)).
- The template reader is keyed on the projection type, not on its IO map, because the transparent wrappers would make it ambiguous ([ProjectionTemplate.jl:1690](../../../source/kernel/projection/ProjectionTemplate.jl#L1690)).
- `ReferenceDispatchingProjection` with `applies` false: four more methods for a foreign IO map ([ReferenceDispatching.jl:156](../../../source/platform/projection/higherorder/ReferenceDispatching.jl#L156)).
- A parent that reads the IO map of a child through a barrier or a dispatch: `get_content_iomap`, about 34 calls.
- A parent whose child went through `CopyingProjection`: `make_copying_field_iomap` and `make_copying_element_iomap`.
- A chain and an intent with a route: `_read_routed_chain` and `_read_routed_gesture`, about 60 lines ([Chaining.jl:187](../../../source/platform/projection/higherorder/Chaining.jl#L187)).
- A gesture that must win over an operation (`ClaimedGesture`): a private walk that enters only template IO maps ([ProjectionTemplate.jl:1556](../../../source/kernel/projection/ProjectionTemplate.jl#L1556)).

### 5. Operations

141 types subtype `Operation` in `source/` (16 in `source/kernel/operation`). How a type tells the
readers what to do with it on the way up:

| Way | What the author writes | Count |
| --- | --- | --- |
| subtype `ReplacePathOperation` | `make_path_operation` | 3 types in the kernel, 4 methods in all |
| the pair `operation_reference` / `retarget_operation` | 2 methods | 15 and 17 method lines |
| subtype `WrappingOperation` | `get_wrapped_operation`, `rewrap_operation` | 8 |
| `is_self_contained_operation(op) = true` | 1 method | about 45 lines outside the kernel |
| built in | `CompoundOperation`, `CollectedIntentsOperation`, `ReplaceReferencedValueOperation`, `SelectDocumentOperation` | 4 |
| a method of `reroot_operation` | 1 method | 5 in `Rerooting.jl` (nothing, the catch-all, a path operation, a compound, a wrapper) and 1 in `Intent.jl:158` (a collected set); no type outside the kernel registers this way |
| nothing | the default reader answers `nothing` for it | for example `ReplaceFocusPartOperation`, `SetVersionCriterionOperation`, `SetReflectedDisclosureOperation` |

The default reader is one function with eight branches by type
([ProjectionDefaults.jl:139](../../../source/kernel/projection/ProjectionDefaults.jl#L139)). The inverse of
an operation is `make_inverse_operation` (59 method lines). 38 function names in `source/` have a
method for `::CompoundOperation`, and 22 have one for `::WrappingOperation`.

Reader payloads beside an event and an operation: `ClaimedGesture` (a gesture with the operation
that a later stage made of it) and `CollectIntents` (the question "what is available"), both in
[Intent.jl:99](../../../source/kernel/intent/Intent.jl#L99). `Intent` itself holds the gesture, the
operation, a description, a domain and a route.

### 6. Kinds of document and of value

| Kind | Where | Special cases that the kernel carries |
| --- | --- | --- |
| `@document` schema | 607 declarations | adds `selection` and `mouse_target`; a family `AFoo`, the cell layout `Foo`, the native layout `MFoo`, the aliases `RCFoo`, `ICFoo`, `MCFoo`, `DCFoo`, `ACFoo`; 9 declarations give a layout list |
| collection documents | `CellVector`, `CellMatrix`, `CellTable`, `ListNode` in `source/platform/collection` | seven kernel seams with one registrant each (finding KM-7) |
| view document | `make_document_view`, `make_following_document` in `source/platform/domain/DocumentView.jl` | `get_edited_field`, `is_view_state_field` |
| plain value in a document | a struct, a tuple, a `Vector` | `_is_plain_slot`, `with_object_field`, `_find_cell_anchor` in `Operations.jl` (lines 386 to 511) |
| pending value | `PendingValue`, the marker of a template | the declared-type check lets it pass |
| referenced document | `get_document` | a document never holds one |

### 7. Kinds of cell

| Kind | Contract | Use outside the kernel layers |
| --- | --- | --- |
| `ReactiveCell` (alias `Cell`) | records readers, computes on read | everywhere |
| `ImmutableCell` | one value, no write | 61 lines in 29 files |
| `MutableCell` | a box, no reader recorded | 2 lines; the sibling repositories use it for native state |
| `UntrackedCell` | computes at each read, records nothing | 402 lines in 90 files, 380 of them `@projection UntrackedCell struct` |

Each kind has a contract that no other has. See "Examined and sound".

## Findings

### KM-1 The reader has two signatures, and most methods use the one that the rules call obsolete

- **Kind:** several-ways · **Value:** high · **Effort:** large · **Confidence:** high
- **Principle:** PAR-FOUR-FUNCTIONS (the four functions are the whole interface); PAR-PREFER-REFERENCE-RETARGET ("Do not write the obsolete 3-arg shim in new code"); first principle 7 (one mechanism).
- **Today:** `read_intent` is the function that turns what a person did into an operation. It has two forms. The 4-argument form takes an `Intent`, the value that holds the gesture, the operation so far, the labels and the route: `read_intent(projection, recursion, change::Intent, iomap)`. The 3-argument form takes one payload, an event or an operation: `read_intent(projection, iomap, payload)`. A bridge in the kernel calls the second from the first ([ProjectionDefaults.jl:250](../../../source/kernel/projection/ProjectionDefaults.jl#L250)). The interface says "do not write a 3-arg method in new code" ([ProjectionInterface.jl:220](../../../source/kernel/projection/ProjectionInterface.jl#L220)). Of 441 method definitions, about 360 are 3-argument and about 81 are 4-argument (the first count of 516 held 75 lines that are calls or lines of a docstring). The two forms meet in three kinds of extra method: 43 one-line shims that call the 4-argument form with `recursion = nothing` (for example [Chaining.jl:253](../../../source/platform/projection/higherorder/Chaining.jl#L253), [EscapeQuitting.jl:51](../../../source/platform/screen/EscapeQuitting.jl#L51)); 53 catch-all methods `read_intent(::P, iomap, op) = nothing`; and about 70 methods for `::ReplacePathOperation`, of which the ones I read repeat the default (for example [SqlToSyntax.jl:955](../../../source/domain/sql/SqlToSyntax.jl#L955)).
- **Example:**
  ```julia
  # today: a wrapper writes the reader twice
  function read_intent(p::EscapeQuittingProjection, recursion, change::Intent, iomap::EscapeQuittingIoMap)
      …
  end
  read_intent(p::EscapeQuittingProjection, iomap::EscapeQuittingIoMap, payload) =
      read_intent(p, nothing, Intent(payload), iomap).operation

  # today: a node that wants only the caret writes the default again, and blocks the rest
  function read_intent(p::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op::ReplacePathOperation)
      result = map_reference_backward(p, iomap, op.path)
      result === nothing ? nothing : make_path_operation(op, result)
  end
  read_intent(::SqlComparisonToSyntaxNode, iomap::ChildrenIoMap, op) = nothing

  # after: one form; the default is a plain function that a reader can call
  function read_intent(p::EscapeQuittingProjection, recursion, change::Intent, iomap)
      …
  end
  # (`read_mapped_intent` and `decline_intent` are names of this sketch)
  read_intent(p::SqlComparisonToSyntaxNode, recursion, change::Intent, iomap) =
      change.operation isa ReplacePathOperation ? read_mapped_intent(p, change, iomap) : decline_intent(change)
  ```
- **Problem:** A 3-argument reader does not see the gesture and the operation together, and it gets no `recursion`. So three features exist only on the 4-argument path. (1) The route of an intent: the bridge follows it only when the IO map answers `get_child_iomaps`, and says "The 3-arg reader follows no route". (2) A gesture that must win over an operation: the payload `ClaimedGesture` exists because a 3-argument reader "would mistake a `ClaimedGesture` for an event", and its descent is a private walk ([ProjectionTemplate.jl:1556](../../../source/kernel/projection/ProjectionTemplate.jl#L1556)). The offer starts only in the reader of a template, and the descent of a key enters template IO maps only (`_read_override_gesture`); the descent of a click also enters a part that no template prints, through `get_child_iomaps`, and fires the gesture bindings of its projection (`_read_part_override_click`, `_read_own_override_click`, lines 1603 to 1636). So a hand-written projection hosts such a click only below a template, and such a key not at all. (3) The labels of an intent. The 3-argument form also dispatches on three arguments at once (projection, IO map, payload), which is why the tree has catch-alls, methods that only remove an ambiguity ([ReaderDefaults.jl:80](../../../source/platform/projection/ReaderDefaults.jl#L80)), and about 18 calls of the 3-argument default through `invoke` (about 27 more `invoke` calls go to the 4-argument bridge, so they do not come from the 3-argument form). The next domain must learn both forms and the rules between them.
- **Proposal:** One reader: `read_intent(projection, recursion, change::Intent, iomap) -> Intent`. The work of today's default reader becomes plain functions that a reader calls: map an operation backward, ask the gesture table of the input document, follow a route. A reader that wants to dispatch on the kind of operation calls a private function of its own. An `Intent` that holds both a gesture and an operation is what `ClaimedGesture` is today, so every reader can answer it and the payload type can go.
- **What goes away:** the 3-argument generic and the bridge; about 43 shims; the 3 disambiguation methods and the "keyed on the projection type" rule of the template; most of the 54 catch-alls and of the 66 path readers (the default serves); `ClaimedGesture` and the private walk `_read_override_click_along` / `_read_part_override_click` / `_read_override_gesture` (about 110 lines of `ProjectionTemplate.jl`).
- **What stays:** every reader behaviour. The chain reads last to first as now. The default still maps a path, a compound, a wrapper and a collected set. A gesture that must win still wins, in every projection.
- **Risk and open questions:** About 360 methods change, in 113 files, and the sibling repositories follow. The conversion can go slice by slice while the bridge stays. A test that calls the 3-argument form (the chain comment names "tests, hit-test recursion") needs a helper. Whether `CollectIntents` stays a payload in the gesture slot is open.
- **Related plans:** `plan/pending/unify-projection-api-parameter-names.md` (not started; renames parameters, calls the 3-argument form "legacy", does not remove it). `plan/pending/kernel-audit/17-projection.md` L17-3 and L17-7 (file-level symptoms of the two forms; in the fix list). `plan/pending/projection-template-engine.md` (in progress; removes the hand-written readers of the `*ToSyntax` files, not the form).
- **Check:** confirmed-with-corrections. I opened the bridge, the interface text, the rule PAR-PREFER-REFERENCE-RETARGET, `Intent.jl`, the claimed-gesture code and `plan/done/reader-gesture-context.md`, and counted the methods again with a script that reads a signature over several lines. The two forms, the bridge, the shims, the catch-alls and the three disambiguation methods are as said, and no plan removes the 3-argument form. Corrections, made above: 441 method definitions and not 516; about 360 are 3-argument (82 %) and about 81 are 4-argument; 43 shims; 53 catch-alls; 113 files; the `invoke` calls of the 3-argument default are about 18, and 27 more go to the 4-argument bridge; the claimed click does enter a part that no template prints. The fix L17-7 of the kernel audit is done (`ProjectionTemplate.jl:1541` calls the 4-argument reader of the child). One part of the proposal does not hold as written: "`ClaimedGesture` can go, because an `Intent` with a gesture and an operation is the same". It is not the same. An `Intent` with both is what every stage gets on the way back, and it asks the stage to translate the operation. A `ClaimedGesture` asks a different question, "do you take this gesture before the operation is translated?", and a child that translated the operation would map a reference that it does not own (`ProjectionTemplate.jl:1556` to 1562; the docstring at `Intent.jl:76` gives the reason for the payload). So the offer needs a mark of its own in the one form too, and the about 110 lines of the private walk do not go away by the change of the signature alone. What the proposal changes for an author: a 3-argument reader is chosen by the type of the payload (`evt::MouseClick`, `op::ReplacePathOperation`); with one form each projection writes that choice as branches or as private functions of its own. No feature is lost. The plan `projection-template-engine.md` removes about 45 of the 3-argument readers by itself (39 are in the SQL domain and 5 in math). Value stays high.

### KM-2 A projection that wraps one other projection has no shared base

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** medium · **Confidence:** high
- **Principle:** first principle 7 (generic before special); PAR-HIGHER-ORDER-IS-DOMAIN-FREE. The model is in the code already: `WrappingOperation` ([OperationInterface.jl:49](../../../source/kernel/operation/OperationInterface.jl#L49)), "one method for every wrapper there will ever be" ([Rerooting.jl:41](../../../source/kernel/operation/Rerooting.jl#L41)).
- **Today:** Many projections wrap one inner projection, print what it prints, map references as it does, and change only the reader: quit on Escape, cycle the focus, track a drag, show a tooltip, record gestures, catch a fault, unwrap a window input. Each writes the same pieces by hand. In the two that I read in full, [EscapeQuitting.jl:22](../../../source/platform/screen/EscapeQuitting.jl#L22) to line 57 and `FocusCycling.jl` lines 19 to 57, about 20 of 36 lines are: the struct with the field `inner`, the keyword constructor, an `@iomap` struct of four fields, a printer of two lines, the 3-argument shim, and two map methods. The same pieces are in `Nesting.jl`, `WindowInputUnwrapping.jl` and `Switching.jl`. The kernel has the IO map for this, `ContentIoMap`, with 4 uses in the platform; 24 other IO map types have its four fields, under three names for the fourth (`inner_iomap` 10, `child_iomap` 11, `content_iomap` 3).
- **Example:**
  ```julia
  # today (EscapeQuitting.jl), and the same again in each wrapper
  struct EscapeQuittingProjection <: Projection
      inner::Projection
  end
  @iomap struct EscapeQuittingIoMap
      projection::Any
      input::Any
      output::Any
      child_iomap::Any
  end
  function print_document(p::EscapeQuittingProjection, recursion, input, ctx)
      child_iomap = print_document(p.inner, recursion, input, ctx)
      EscapeQuittingIoMap(p, input, Cell(@computation child_iomap.output), child_iomap)
  end
  read_intent(p::EscapeQuittingProjection, iomap::EscapeQuittingIoMap, payload) = …
  map_reference_forward(::EscapeQuittingProjection, iomap::EscapeQuittingIoMap, reference) = …
  map_reference_backward(::EscapeQuittingProjection, iomap::EscapeQuittingIoMap, reference) = …
  function read_intent(p::EscapeQuittingProjection, recursion, change::Intent, iomap) … end

  # after: the wrapper writes what is its own
  struct EscapeQuittingProjection <: WrappingProjection
      inner::Projection
  end
  function read_intent(p::EscapeQuittingProjection, recursion, change::Intent, iomap) … end
  ```
- **Problem:** The services that see through a wrapper are registered per IO map type, so they hold for some wrappers only. Of the 24 types, 9 answer `get_child_iomaps`. Two answer `get_content_iomap`, and the same two forward a property read to the inner IO map ([ReferenceDispatching.jl:93](../../../source/platform/projection/higherorder/ReferenceDispatching.jl#L93), [FaultCatching.jl:135](../../../source/platform/projection/higherorder/FaultCatching.jl#L135)). A parent that reads the type or a field of the IO map of its child (about 34 calls of `get_content_iomap`) sees through a fault barrier and a reference dispatch, and not through a `SwitchingProjection`, a `NestingProjection` or any of the reader wrappers. So whether two projections combine depends on which wrapper stands between them. Each new wrapper must repeat the 20 lines and choose again which services to register.
- **Proposal:** An abstract `WrappingProjection <: Projection` with one accessor, the inner projection. The kernel gives its defaults once: the printer answers a `ContentIoMap` whose output cell forwards the inner output, both maps delegate, `get_child_iomaps` answers the inner IO map, and the reader passes the intent on. A wrapper overrides only what it changes. A wrapper that adds nothing to the output says so with one trait, and `get_content_iomap` and the property forwarding follow from the trait.
- **What goes away:** about 24 IO map types; in each wrapper the printer, the shim and the two maps (about 15 lines each, so about 350 lines by my estimate); 9 `get_child_iomaps` methods; the two hand-written `getproperty` forwards become one.
- **What stays:** every wrapper and its reader. A wrapper that keeps data of its own (a log, an overlay, a drag state) keeps an IO map of its own with the same first four fields.
- **Risk and open questions:** A wrapper whose output differs from the inner output (an overlay, a tooltip window) must not be see-through for `get_content_iomap`; the trait must default to "not see-through". The transparent wrappers (`RecursiveProjection`, `TypeDispatchingProjection`) answer the inner IO map itself today, which is cheaper; they can stay as they are. Whether a parent should read the IO map of a child at all is a question for the area of printer locality.
- **Related plans:** `plan/pending/printer-locality.md` and `printer-locality-findings.md` (touch what a parent reads of a child). `plan/pending/packages-compose-by-seams.md` (not read in full). No plan gives the wrappers a base.
- **Check:** confirmed-with-corrections, value lowered to medium. I listed every `@iomap` struct of `source/` with its fields by script and opened 22 of the wrapper files. 24 types beside `ContentIoMap` have its four fields (10 `inner_iomap`, 11 `child_iomap`, 3 `content_iomap`), 9 of them answer `get_child_iomaps`, and two types answer `get_content_iomap`; no shared base exists and no plan or document gives a reason for the separate types. Corrections. (1) The 24 are not one family. About 9 wrap the same input and delegate both maps unchanged (`EscapeQuitting`, `FocusCycling`, `SelectionWalking`, `GestureLogRecording`, `GestureHelpDecorator`, `CommandPaletteDecorator`, `WindowManaging`, `WindowInputUnwrapping`, `Nesting`). About 8 take a state document and print its field `content` through a reconciled child cell, so their maps add and remove the step `content` and their reader reroots the answer (`DragTracking`, `TooltipWindow`, `AppearanceManaging`, `SettingsManaging`, `GestureTracking`, `UndoBufferToAny`, `ContextMenuWindow`, `Arranging`). The rest are not wrappers of this kind (`RosterToGraphics`, `RepeatedFile`, `TextViewToGraphics`, `ScreenWindow`, `Dragging` with an output of its own, `FaultSafeMode` whose maps answer `nothing`). So the base needs a second accessor, the step from the input to the content (empty for the first family), and it removes about 17 IO map types, not 24. (2) The 9 that answer `get_child_iomaps` are the state wrappers; the same-input wrappers pass the whole intent, with its route, to the inner reader, so a route is not lost there. (3) The "combine" problem is real only for a wrapper that stands between a parent and its child, which is `NestingProjection` (15 uses) and `SwitchingProjection` (0 uses); the session wrappers stand around the whole editor projection and no parent reads through them. The part of the proposal that gives every see-through wrapper the property forwarding by a trait widens the reads of a parent into the IO map of a child, which the settled decision "a projection never reads the state or the output of another projection" and `plan/pending/printer-locality.md` go against; leave that part out. Nothing is lost by the base itself.

### KM-3 An operation tree has no generic walk, and five ways to say how it travels

- **Kind:** repeated-by-hand · **Value:** high · **Effort:** medium · **Confidence:** high for the facts, medium for the default rule of the proposal
- **Principle:** PAR-REGISTER-NEW-OPERATION ("registers once"); first principle 7 (verbs combine with no special case); first principle 3 (one way to edit).
- **Today:** An operation can hold other operations: `CompoundOperation` holds a vector, a `WrappingOperation` holds one, `CollectedIntentsOperation` holds one per intent. There is no function that maps or searches such a tree. So each function that must look inside writes the recursion itself: 38 function names have a method for `::CompoundOperation` and 22 for `::WrappingOperation`, for example `has_mouse_target` with four methods ([PathChain.jl:71](../../../source/kernel/operation/PathChain.jl#L71)), `_find_claimed_selection` with four ([ProjectionTemplate.jl:1639](../../../source/kernel/projection/ProjectionTemplate.jl#L1639)), `keep_held_arrangement` with four. The trip through the readers is the same recursion once more, in the eight branches of the default reader ([ProjectionDefaults.jl:139](../../../source/kernel/projection/ProjectionDefaults.jl#L139)) and the five methods of `reroot_operation` ([Rerooting.jl:31](../../../source/kernel/operation/Rerooting.jl#L31); a sixth, for a collected set, is at `Intent.jl:158`). An operation type tells these two what to do with it in one of five ways (table 5). The fifth is to say nothing: the default reader then answers `nothing` ([ProjectionDefaults.jl:222](../../../source/kernel/projection/ProjectionDefaults.jl#L222)), and the rule says "with no error". About 45 lines outside the kernel are `is_self_contained_operation(::X) = true`, which only says "pass me on".
- **Example:**
  ```julia
  # today: an operation that holds its subject needs a line, or a default reader drops it
  struct OpenUrlOperation <: Operation … end
  is_self_contained_operation(::OpenUrlOperation) = true

  # today: each question about an answer writes the walk
  has_mouse_target(::Any) = false
  has_mouse_target(::ReplaceMouseTargetOperation) = true
  has_mouse_target(operation::CompoundOperation) = any(has_mouse_target, operation.operations)
  has_mouse_target(operation::WrappingOperation) = has_mouse_target(get_wrapped_operation(operation))

  # after: one walk, and one function that maps the references of an operation
  has_mouse_target(answer) = any_operation(op -> op isa ReplaceMouseTargetOperation, answer)
  reroot_operation(op, steps) = map_operation_references(r -> reroot_reference(r, steps), op)
  ```
- **Problem:** (1) A function that handles a compound and forgets a wrapper works until an operation arrives in a `ReplaceViewStateOperation` or a `ShowSelectionOperation`. 21 of the 38 names have no method for `::WrappingOperation`; I did not check each body for a branch inside, and four of the 21 (`read_intent`, `read_move_answer`, `evaluate_operation`, `evaluate_invertible_operation!`) handle a wrapper in another way. (2) Three operation types that I checked have no registration at all: `ReplaceFocusPartOperation` ([Focusing.jl:48](../../../source/platform/projection/generic/Focusing.jl#L48)), `SetVersionCriterionOperation` ([VersioningToAny.jl:146](../../../source/platform/versioning/VersioningToAny.jl#L146)) and `SetReflectedDisclosureOperation` ([DocumentReflection.jl:60](../../../source/platform/reflection/DocumentReflection.jl#L60)). Each works where its own projection gives the last answer, and is dropped where a projection with the default reader stands before it in a chain. So the feature works in some compositions only. (3) `ReplaceSelectionOperation` is registered twice, as a path operation and by the pair ([Rerooting.jl:53](../../../source/kernel/operation/Rerooting.jl#L53)).
- **Proposal:** Two functions in the operation layer. `map_operation_references(f, operation)` answers the operation with `f` applied to each reference that is relative to the frame of the reader, or `nothing` when `f` answers `nothing` for one; it has one method each for a compound, a wrapper, a collected set, a path operation and `ReplaceReferencedValueOperation`, and a type with a reference adds one method. `reroot_operation` and the default reader both call it. An iterator over the leaves of an operation serves every question such as `has_mouse_target`. An operation that carries no such reference travels as it is, which is what `is_self_contained_operation` says by hand today.
- **What goes away:** `is_self_contained_operation` and its about 45 methods; the pair `operation_reference` / `retarget_operation` (15 and 17 method lines) or the pair `get_operation_path` / `make_path_operation`, one of the two; six of the eight branches of the default reader; four of the five `reroot_operation` methods; the `CompoundOperation` and `WrappingOperation` methods of the functions that only ask a question or rebuild an answer, such as `has_mouse_target`, `_find_claimed_selection`, `keep_held_arrangement` and `is_appearance_change`.
- **What stays:** every operation type and its evaluation; the rule that a compound maps whole or not at all, and the exception for the answer to a move; the inverse protocol, which reads the document and is a different job.
- **Risk and open questions:** Today's default drops an unknown operation on purpose: "a projection that answers an operation it does not understand is worse than one that declines" ([OperationInterface.jl:256](../../../source/kernel/operation/OperationInterface.jl#L256)). With "travels as it is" as the default, a type that holds a frame-relative reference and forgets its method would reach the editor with a reference in the wrong frame. A static guard can close that: a test that finds each `Operation` subtype with a field of type `Reference` and no method. This default is a decision for the owner. The kernel audit kept three families at L13-8 and L13-15; this finding proposes to go one step further.
- **Related plans:** `plan/pending/kernel-audit/13-operation.md` L13-4, L13-8 (file-level; both done) and `17-projection.md` L17-18 (done). `plan/pending/kernel-audit-fixes.md` (in progress): the owner decided L13-8 on 2026-09-30 (answer A, "one pair registers an operation that carries a path"), and step D5 is done with the three families that stand now (the pair, `ReplacePathOperation`, `WrappingOperation`).
- **Check:** weakened, value lowered to medium. The facts hold: 38 function names have a method for `::CompoundOperation` and 22 for `::WrappingOperation` (counted again), 21 of the 38 have none for a wrapper, the default reader has eight branches, no generic walk exists in `source/` (I searched for `map_`, `walk_`, `any_`, `find_` and `each_` names over an operation), and the three operation types have no registration. Spot check of the 21: `_take_tooltip` (`TooltipWindow.jl:171`) and `_take_pointer_shape` (`WindowManaging.jl:137`) name `ReplaceViewStateOperation` and no other wrapper, and `changes_lines` and `is_text_element_write` (`TextDocument.jl:1904`, `:2277`) enter a compound and no wrapper. So the first half of the proposal holds: one walk over an operation tree (a test of the leaves, a rebuild of the leaves, and the taking of one leaf out of a compound, which is a third kind that the proposal does not name: `_take_tooltip`, `_take_context_menu`, `_split_drag_start`, `_drop_selection_moves`). The second half does not pass. (1) "An operation with no reference travels as it is" turns a stated default around: `OperationInterface.jl:256` to 259 and PAR-REGISTER-NEW-OPERATION say that the default reader drops what it can not place, and the owner decided the registration model on 2026-09-30 (L13-8, answer A; D5 done), which keeps the pair. The proposal would lose that guard; the static test that it offers (a field of type `Reference`) does not see a reference in a field of type `Any`, and it would flag `ReplaceFocusPartOperation`, whose `part` is relative to the projection that it carries. (2) "Six of the eight branches go away" is too many: the event branch, the `SelectDocumentOperation` branch (it reads `iomap.input`), the compound branch (whole or not at all, with the exception for a move and for a held `SelectDocumentOperation`) and the collected branch (a row that does not map keeps its row) have rules of their own; the path, wrapper, value-write and open branches are the ones that fold. (3) `ReplacePathOperation` is named sound in this same report, so "one of the two pairs goes" is not decided by the facts here. What remains: the generic walk, and the three operation types that need their one line today.

### KM-4 The template engine has seven shapes of node, with limits between them

- **Kind:** several-ways · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** first principle 7 (one mechanism for every list, every part); PAR-DELEGATE-AND-LIFT.
- **Today:** `@projection_template` builds the real output with markers in it: `bound(:field, …)` for a value of a field, `project(:field)` for a child, `collection(:field)` for the children of a vector, `tokens(…)` and `sections(…)`. `_dispatch_print` ([ProjectionTemplate.jl:297](../../../source/kernel/projection/ProjectionTemplate.jl#L297)) then sorts the output into one of seven shapes, each with a wiring struct: `AtomicWiring`, `NodeWiring`, `FixedNodeWiring`, `ConditionalNodeWiring`, `MixedNodeWiring`, `InlineWiring`, `SectionsWiring` ([:120](../../../source/kernel/projection/ProjectionTemplate.jl#L120) to line 214). Each shape has its own printer, forward map, backward map, and most have a focused-child finder and an output-child finder: 31 methods by a second count (7 printers, 7 forward maps, 7 backward maps, 5 focused-child finders, 5 output-child finders), about 1 000 of the 1 755 lines. The IO map field `child_iomaps` holds five different structures, one per group of shapes. The mixed maps repeat the slot code of the fixed maps and the element code of the node maps ([:1104](../../../source/kernel/projection/ProjectionTemplate.jl#L1104), [:978](../../../source/kernel/projection/ProjectionTemplate.jl#L978)).
- **Example:**
  ```julia
  # today: the child list that a builder gives a node
  [open_leaf, collection(:columns), close_leaf]   # error, line 694:
                                                  # "fixed children after a spliced collection are not supported"
  [collection(:columns), collection(:values)]     # error, line 691:
                                                  # "only one spliced collection per mixed node"

  # after: the same builders print; a node is a list of slots, and a slot is one of
  # introduced | bound(field) | project(field) | splice(collection field) | group(sub-node)
  ```
- **Problem:** The shapes do not combine. One collection per mixed node, and it must be last ([:691](../../../source/kernel/projection/ProjectionTemplate.jl#L691), [:694](../../../source/kernel/projection/ProjectionTemplate.jl#L694)); a collection directly in a fixed node is an error ([:607](../../../source/kernel/projection/ProjectionTemplate.jl#L607)); an inline node has exactly one bound token; a section is a shape of its own. The syntax output hides these limits because a `SyntaxNode` has fields for its delimiters. An output with no such fields, such as a row of widgets, meets them at once, and every use of the template today has a syntax output (table 1). A new shape costs five methods.
- **Proposal:** One wiring: a node is a list of slots that a cell computes, and a slot is introduced, bound, projected, a spliced collection or a group. One forward map, one backward map, one focused-child finder and one output-child finder walk the slot list and count the places of a splice. Node is the list of one splice; fixed is a list with none; mixed, conditional, inline and sections are lists too.
- **What goes away:** six wiring structs, about 25 of the 33 methods, the five structures of `child_iomaps`, the four limits. My estimate is 500 to 600 lines; I did not write the new code.
- **What stays:** the builder syntax and the five marker words; every template projection as written; the reconciler per collection; the introduced step for a part that the node printed.
- **Risk and open questions:** The maps run for every caret move, so the slot walk must not cost more than a field test does now; a node with one splice needs a fast path. `ProjectionTemplate.jl` is a kernel file and is not sealed (`SEALING.md` line 250). The kernel audit has file-level fixes in the same functions (L17-1, L17-5, L17-6, L17-20), and `kernel-audit-fixes.md` marks the four done, so the new shape starts from the fixed code.
- **Related plans:** `plan/pending/projection-template-engine.md` (in progress; converts files to the engine, names the six wirings as done, and puts output domains other than syntax out of scope). `plan/pending/kernel-audit/17-projection.md` L17-1, L17-5, L17-20 (file-level).
- **Check:** confirmed-with-corrections, value stays medium. I opened the seven wiring structs (`ProjectionTemplate.jl:120` to 214), `_dispatch_print` (:297) and the three error lines (:607, :691, :694); each is as said. The plan `projection-template-engine.md` lists the wirings as they were added one by one and has no step that joins them, and it gives no reason for the limits. Corrections, made above: 31 methods, not 33; the file is not sealed; the audit fixes are done. Two more. (1) "Six wiring structs go away" is one too many: `AtomicWiring` is a leaf with a bound field and no child list, so it stays beside the slot list, and five go. (2) `ConditionalNodeWiring` is already a slot list that a cell computes, so the proposal is to give that wiring a splice slot and a group slot and to express the other node shapes by it; this makes the change smaller than the text suggests. One limit of the value: no template of `source/` meets the limits today (162 uses, each prints), and the plan puts output domains other than syntax out of scope, so the gain is for the engine itself (a new marker costs one method, not five) and for a later template with a widget output. No feature is lost, as long as a node with one collection keeps its reconciled cell per collection.

### KM-5 Choosing one inner projection is implemented four times

- **Kind:** several-ways · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** first principle 7; PAR-STABLE-IOMAP-IDENTITY; PAR-MAPPERS-ARE-INVERSES (the reader and the maps must agree with the printer).
- **Today:** Four higher-order projections choose one inner projection for an input: by type, by predicate, by reference path, by an index cell. Table 4 gives their differences. Two answer the inner IO map and decide again in the reader and in each map; the type dispatch decides in two different ways in its own file (the table in the reader, `iomap.projection` in the maps). Two keep an IO map of their own with a reconciled inner IO map, and follow a change of the choice.
- **Example:**
  ```julia
  # today
  TypeDispatchingProjection(JsonNull => a, JsonBool => b)        # transparent, decides 3 times
  PredicateDispatchingProjection(is_inline => a, is_block => b)  # transparent, runs the predicates again
  ReferenceDispatchingProjection(default, path => a)             # own IO map, reactive
  SwitchingProjection([a, b], index)                             # own IO map, reactive

  # after: one mechanism, four ways to give the choice
  DispatchingProjection(choose)          # choose(input, context) -> projection
  TypeDispatchingProjection(pairs...)    = DispatchingProjection(by_type(pairs))
  SwitchingProjection(projections, index) = DispatchingProjection((input, context) -> projections[index[]])
  ```
- **Problem:** A predicate that reads a cell can answer another projection at the read than at the print; the reader and the maps then call a projection that did not make the IO map. The type and the predicate dispatch do not follow a change; the other two do. `SwitchingProjection` reads the index cell again in its reader ([Switching.jl:70](../../../source/platform/projection/higherorder/Switching.jl#L70)) where the inner IO map already names its projection. A fifth way to choose would be a fifth implementation.
- **Proposal:** One dispatching projection that takes a function from the input and the context to a projection. The reader and both maps always go to the projection of the IO map that stands, as `ReferenceDispatchingProjection` does now ([ReferenceDispatching.jl:130](../../../source/platform/projection/higherorder/ReferenceDispatching.jl#L130)). Where the choice can not change, the dispatch answers the inner IO map and costs nothing, as the `applies` rule does now. The four names stay as constructors.
- **What goes away:** three of the four implementations (about 200 lines), `SwitchingIoMap`, the three decisions of the type dispatch, the four extra methods for a foreign IO map.
- **What stays:** the four names and their arguments; the order of the pairs; the zero cost of a type dispatch.
- **Risk and open questions:** `TypeDispatchingProjection` is on every print path (56 uses), so its fast path must stay a loop over a vector. `SwitchingProjection` has no user in `source/`.
- **Related plans:** `plan/pending/parallel-projection.md` (not started; names `SwitchingProjection` as a neighbour). None covers this.
- **Check:** weakened, value lowered to low. I opened the four files in full. The facts of table 4 hold. The difference is smaller than "four implementations": there are two mechanisms, each written twice. The type and the predicate dispatch answer the inner IO map and decide again from `iomap.input`; the reference dispatch and the switch keep an IO map of their own with a reconciled inner IO map. The two mechanisms differ for a reason that one `DispatchingProjection(choose)` can not remove: a reader and a map get no printer context, so a dispatch that answers the inner IO map can decide again only when the choice needs the input alone. A choice that reads the context or a cell needs the IO map of its own. So the one projection would still hold both modes, and the saving is about 100 lines, in two files with 1 and 0 users (`PredicateDispatching.jl` 76 lines, `Switching.jl` 88 lines), not 200. The rule "the reader always goes to the projection of the IO map that stands" would lose something: the type dispatch and the switch read through the projection object that they chose (`TypeDispatching.jl:60`, `Switching.jl:70`), so a wrapper in that slot that answers the inner IO map still takes part; a `RecursiveProjection` there passes itself as `recursion` to the reader below it (`Recursive.jl:45`). `get_iomap_projection` of the inner IO map names the innermost projection and skips that wrapper. The maps need no `recursion`, which is why they can use `iomap.projection`. So "decides in two ways in its own file" has a cause, and `Switching.jl:70` is not a fault. What remains true: a predicate that reads a cell can choose another projection at the read than at the print (one user in `source/`), and it is fixed inside `PredicateDispatching.jl`.

### KM-6 The generic sort, filter and reverse are a second implementation of a stage that the product uses

- **Kind:** redundant · **Value:** medium · **Effort:** small · **Confidence:** high
- **Principle:** first principle 2 (a general step works for every domain); first principle 7; settled decision "one generic solution for every list".
- **Today:** The projection algebra has `SortingProjection`, `FilteringProjection` and `ReversingProjection`. Each has its own IO map or map code, and the first two have three printers each, for a `CellVector`, a `Vector{Cell}` and any other input ([Sorting.jl:36](../../../source/platform/projection/generic/Sorting.jl#L36), [Filtering.jl:33](../../../source/platform/projection/generic/Filtering.jl#L33)). `FilteringProjection` and `ReversingProjection` have no caller in `source/` outside their own file. `SortingProjection` has two, both in the projection slice: `SortingAtProjection` ([GenericCompound.jl:10](../../../source/platform/projection/compound/GenericCompound.jl#L10)) and a compound at `HigherOrderCompound.jl:12`; an example of the JSON domain uses `SortingAtProjection`. Each of the three has one example and one to three tests, and no product code uses one. The filter and the sort that a person uses are in the arrangement slice: `PickingProjection(compute_rows)` ([Picking.jl:25](../../../source/platform/arrangement/Picking.jl#L25)), whose output holds the items at the indices that a function answers, "a filter answers the indices of the items that it keeps, and a sort a permutation". The plan of that slice records the change: a stage that prints its children, as `SortingProjection` does, hands printed output to a printer that prints items.
- **Example:**
  ```julia
  # today: two stages for one job
  SortingProjection(by = entry -> entry.key)                      # algebra; prints the children itself
  PickingProjection(items -> sortperm(items; by = item -> item.key))  # arrangement; passes the items on

  # after: one stage in the algebra, and the three names as constructors
  SortingProjection(; by = identity, lt = isless, rev = false) =
      PickingProjection(items -> sortperm(collect(items); by, lt, rev))
  FilteringProjection(; predicate) = PickingProjection(items -> findall(predicate, items))
  ReversingProjection() = PickingProjection(items -> reverse(eachindex(items)))
  ```
- **Problem:** `concepts.md` names the filter and the sort as the proof that a general step works for every domain, and the steps that carry that sentence are not the ones in use. The two families differ where it matters: `PickingProjection` keeps its last final rows while a key is provisional and keeps a cell per item; the older ones compute the whole order again. A fix or a feature lands in one family only. The general stage sits in a slice that the algebra can not use.
- **Proposal:** Move the index-picking stage into `source/platform/projection/generic`. Define the sort, the filter and the reverse as constructors of it. The arrangement slice keeps its descriptions (`ArrangementFilter`, `ArrangementSort`) and its row functions.
- **What goes away:** `SortingIoMap`, `FilteringIoMap`, the seven printers and six maps of the three projections; their three files have 249 lines.
- **What stays:** the three names and their keywords, so the examples and `SortingAtProjection` stay; every feature of the arrangement.
- **Risk and open questions:** `SortingProjection` prints each child with the index of the source in its context; a caller that relies on that needs the chain of the arrangement (`ArrangedChainingProjection`), which I did not read. `SearchingProjection` is a fourth unused stage with a walk of its own ([Searching.jl:89](../../../source/platform/projection/generic/Searching.jl#L89)) beside `search_references`; it could follow the same way, and I did not check it in detail. This finding reaches the area of the arrangement and the collections.
- **Related plans:** `plan/pending/filter-sort-and-find-any-table.md` (step 2 done; made `PickingProjection`, left the older ones). `plan/pending/injecting-projection.md` (in progress; describes its stage as the dual of `FilteringProjection`, so it should be the dual of the one stage). `plan/pending/the-header-of-a-table-filters-and-sorts-its-arrangement.md`.
- **Check:** weakened, value lowered to low. I opened `Sorting.jl`, `Filtering.jl`, `Reversing.jl`, the head of `Picking.jl` and step 2 of `filter-sort-and-find-any-table.md`, and searched the three repositories for callers (corrected above; omnet-julia and inet-julia use none of the four). Only one of the three does the same job as the picking stage. `FilteringProjection` passes the kept items on and prints none, as `PickingProjection` does, so it is a second implementation. `SortingProjection` and `ReversingProjection` have another contract: they print each child through the `recursion` and arrange the outputs (`Sorting.jl:40`, `Reversing.jl` the same). Step 2 of the plan records this as the reason for the new stage: a stage that prints its children hands printed output to a printer that prints items. So the constructors of the proposal change what the two names do. The case that would be lost: `SortingAtProjection`, which is `ApplyAtProjection(reference, SortingProjection(; by))`, sorts at one path inside a recursive copy, and the children below the sorted collection are printed through that recursion today; a picking stage passes them on and the recursion stops there. The report names this risk and did not read `ArrangedChainingProjection`. A second cost: `Picking.jl` (403 lines) keeps its cells per item by the description of the arrangement (`_ItemCells`, `_FilterRows`, `_SortRows`), so a move into the algebra needs a split of that file first. What remains: `FilteringProjection` as a constructor of the picking stage, once that stage is in the projection slice; the sort and the reverse stay, or go with their examples, by a decision of the owner. No product feature depends on any of the three.

### KM-7 The kernel has seven seams whose only registrant is `CellVector`

- **Kind:** wrong-place · **Value:** medium · **Effort:** medium · **Confidence:** medium
- **Principle:** PAR-FRAMEWORKS-SINK (what several slices need sinks to the layer that owns the concept); PAR-FIELDS-ARE-CELLS and PAR-EVERY-DOCUMENT-HAS-SELECTION, which both name `CellVector` as a part of the model.
- **Today:** `CellVector` is the vector whose elements each have a cell. It lives in `source/platform/collection/CellVector.jl`. The kernel may not name it, so the kernel asks for it through open functions, and `CellVector.jl` is the one file that answers each of them: `is_element_collection` ([:133](../../../source/platform/collection/CellVector.jl#L133)), `is_collection_field_type(::Val{:CellVector})` ([:138](../../../source/platform/collection/CellVector.jl#L138)), `get_cell_layout_field_type(::Val{:Vector}) = CellVector` ([:150](../../../source/platform/collection/CellVector.jl#L150)), `find_declared_element_type` ([:100](../../../source/platform/collection/CellVector.jl#L100)), `get_slot_at` ([:275](../../../source/platform/collection/CellVector.jl#L275)), `child_reference_steps` ([:413](../../../source/platform/collection/CellVector.jl#L413)), and `make_children_container` with `get_children_container_type` ([:426](../../../source/platform/collection/CellVector.jl#L426)). Two of them are keyed on the symbol of a type name, because the macro `@document` asks while it expands. Corrections of the check: `is_collection_field_type` has two keys in that file (`:ListDocument` at line 127 and `:CellVector`); `child_reference_steps` has a second registrant (`ObjectField`, `source/platform/primitive/ObjectField.jl:50`) and a default with real work in the kernel (`Operations.jl:717`); `is_element_collection`, `find_declared_element_type` and `get_slot_at` have a kernel default that works for every value, and `CellVector` overrides it. Only `make_children_container` and `get_children_container_type` have no default, so that the kernel can not do its work without the registrant.
- **Example:**
  ```julia
  # today: the kernel
  function make_children_container end
  function get_children_container_type end
  is_collection_field_type(::Val) = false
  get_cell_layout_field_type(::Val) = nothing
  get_slot_at(container, index::Integer) = container[index]
  # platform/collection/CellVector.jl, the one registrant
  make_children_container(cells::Vector) = CellVector(cells)
  get_children_container_type() = CellVector
  get_cell_layout_field_type(::Val{:Vector}) = CellVector

  # after: the kernel names its own collection
  children = CellVector(@computation [im.output for im in child_iomaps[]])
  ```
- **Problem:** A seam with one possible registrant is not open: `get_children_container_type()` takes no argument, so a second registrant would replace the first. A template node does not print without the platform slice (the kernel audit says so at L17-17), and by the docstring of `get_cell_layout_field_type` a field declared `Vector{T}` stays a plain vector where the slice is not loaded. The key is the symbol of the declared type, so a field declared through an alias of `Vector` has another key; I did not test what the macro does with it. The reader of the kernel meets seven indirections for one fact.
- **Proposal:** Put the cell vector in the kernel, as a layer after the document layer and before the reference layer. The template, the splice of `ReplaceReferencedValueOperation`, the inverse and `@document` name it. The matrix, the table and the linked list stay in the platform and add methods where they differ.
- **What goes away:** `make_children_container`, `get_children_container_type`, `is_collection_field_type`, `get_cell_layout_field_type`, `get_slot_at` as seams (five generics, with seven methods in `CellVector.jl` and three defaults in the kernel); the `Val` keys; `is_element_collection` and `find_declared_element_type` stay only if a second collection needs them.
- **What stays:** `CellVector` and its API, unchanged; the rule that a field declared `Vector{T}` becomes a `CellVector{T}` in the cell layout.
- **Risk and open questions:** The module text says "The kernel defines only this contract; it carries no concrete documents" ([DocumentModule.jl:13](../../../source/kernel/document/DocumentModule.jl#L13)), so this changes a stated rule and needs the owner's word. It does not touch the settled decision that the kernel has no notion of content, view or editor document: a vector of cells is none of them. `ListNode` and the lazy list are a second sequence with one generic memory solution still undecided; if that solution replaces `CellVector`, the kernel collection should be that one. Several kernel files are sealed. This finding reaches the area of the collections.
- **Related plans:** `plan/pending/kernel-audit/17-projection.md` L17-17 and `10-document.md` L10-6 (file-level faults of two of the seams). `plan/pending/cheap-reactive-cells.md` (in progress; L2 is about the slots of a `CellVector`). `plan/pending/strict-document-types.md` (in progress; uses `find_declared_element_type`).
- **Check:** refuted, value none. I listed every method of the eight functions in the three repositories and opened their docstrings and the rules of the kernel. The difference has a stated reason, and the proposal goes against it. `documentation/rule/architecture-rules.md` line 62 says of the kernel "**Zero concrete documents**", and `documentation/package/kernel/architecture.md` lines 20 to 23 say "**No concrete documents** either — Collection and Primitive live in the platform's collection and primitive slices"; the docstrings of the seams say the same ("so the document layer names no concrete collection type", `DocumentInterface.jl:177` and `documentation/package/kernel/document.md:111`). The seams are how that rule is kept, so a seam with one registrant is its expected cost and not a second way to do one thing. The count is also smaller than seven (corrected above): five of the functions are open traits with a default or with a second registrant, and two have no default. The faults that are real are already questions to the owner in `plan/pending/kernel-audit-fixes.md`, each with a smaller fix that keeps the rule: L17-17 (key the children-container seam on the output type, or build the container from the declared field type), L10-6 (make the substitution of `get_cell_layout_field_type` real, or remove it) and L13-3 (remove `child_reference_steps` in favour of `search_references`). None is decided yet. The proposal would also fix a choice that the owner left open: which sequence is the one of the model, while the one memory solution for every list is not decided. The settled decision "the kernel has no notion of content, view or editor document" is not touched.

### KM-8 The parts of a value are listed by several walks, each with its own rules

- **Kind:** several-ways · **Value:** medium · **Effort:** large · **Confidence:** medium
- **Principle:** first principle 7 (one mechanism for every part); PAR-SEARCH-DONT-WALK; first principle 10 (the surface comes by reflection).
- **Today:** `DocumentWalk.jl` says "There is exactly one traversal" for a search. Beside it, these places list the fields or the children of a value themselves: `child_reference_steps` in the operation layer ([Operations.jl:717](../../../source/kernel/operation/Operations.jl#L717)), which the selection of a document, "next hole" and the path cells of an output tree use; the copy ([DocumentCopy.jl:90](../../../source/kernel/document/DocumentCopy.jl#L90)); the sync ([DocumentSync.jl:81](../../../source/kernel/document/DocumentSync.jl#L81)); `SearchingProjection._walk` ([Searching.jl:89](../../../source/platform/projection/generic/Searching.jl#L89)); `_reflect_fieldnames` of the reflected view ([DocumentReflection.jl:133](../../../source/platform/reflection/DocumentReflection.jl#L133)); the form of `ObjectToWidget` ([ObjectToWidget.jl:159](../../../source/platform/widget/ObjectToWidget.jl#L159)); `ObjectToSyntax`; and `get_tree_children_steps` of the tree slice ([TreeInterface.jl:23](../../../source/platform/tree/TreeInterface.jl#L23)). Each has its own rule for what counts: `is_field_walked`, `is_walk_opaque`, `is_view_state_field`, `is_element_collection`, `is_reflection_leaf`, `_is_displayable_field`, "the value is a `Document`".
- **Example:**
  ```julia
  # today: "which fields of this node hold a part?" has one answer per caller
  child_reference_steps(node)                 # fields whose value is a Document, no view state
  walk_document(root, walk)                   # fields that is_field_walked allows, no selection
  _reflect_fieldnames(x)                      # every field of a struct
  [nm for nm in fieldnames(typeof(obj)) if _is_displayable_field(p, obj, nm)]

  # after: one protocol, and each caller filters
  for (step, part) in get_parts(node) … end   # the steps and the parts of one level, lazily
  ```
- **Problem:** A new kind of document (a collection, a link, a view document) must teach each walk about itself, and it works in the walks that someone remembered. A field that one walk hides (a link, view state) shows in another. The selection walk stops at a plain `Vector` while the search enters it.
- **Proposal:** One function that answers the steps and the parts of one level of a value, lazily and without reading a computed cell before it is asked. The traits of a type are asked there once. The search, `child_reference_steps`, the copy, the sync and the three views on demand call it and filter by their own need (documents only; no view state; cells, not values).
- **What goes away:** `child_reference_steps` as a second seam, `SearchingProjection._walk`, the field loops of the reflection and of the object form; several traits fold into one.
- **What stays:** the search and its `DocumentWalk` rules; the bounded sync as a policy of the walk; each view.
- **Risk and open questions:** The copy and the sync need the cell of a slot, a search needs the value, and a reflected view reads any Julia object, so the protocol must give both the slot and the value. I read the copy and the sync only by their `fieldnames` lines. The kernel audit has many file-level findings in these walks (L10-2, L10-7, L10-9, L10-16, L13-3); a redesign should take them in.
- **Related plans:** `plan/pending/kernel-audit/10-document.md` (file-level). `plan/pending/catalog-all-documents.md`, `plan/pending/a-catalog-of-what-each-part-could-say.md` (not read; they may want the same protocol).
- **Check:** weakened, value lowered to low. Each cited place exists and lists fields or children as said (`Operations.jl:717`, `DocumentCopy.jl:88`, `DocumentSync.jl:80`, `Searching.jl:89`, `DocumentReflection.jl:133`, `ObjectToWidget.jl:155`, `TreeInterface.jl:23`). But they do not all do the same job, and the largest one has a plan. (1) `child_reference_steps` is the one true second walk of documents, and the kernel audit already asks the owner to remove it: question L13-3 of `plan/pending/kernel-audit-fixes.md` (not decided yet) recommends that "next hole" uses `search_references`, and says "`child_reference_steps` and its `CellVector` method can go". That goes the other way than this proposal: it uses the one walk that exists and adds no new protocol. The function has three callers (`Operations.jl:227`, `:735`, `OutputPaths.jl:87`). (2) The copy and the sync do not list parts: they read and write every slot of a node, leaves too, and build or update a second node. The report read only their `fieldnames` lines. (3) `get_tree_children_steps` and `_is_displayable_field` are choices of a view, per type: which collections a node shows as children in a tree, which fields a form shows. A structural protocol does not replace them; each would still filter. (4) `reflect_child_pairs` reads any Julia object, not a document. So what the proposal would join is `SearchingProjection._walk` (no user in `source/`) and the field loops of two views. The proposal would lose nothing, but its gain is small once L13-3 is answered. The open point that is worth the owner's eye is the one sentence of the Problem: the selection walk stops at a plain `Vector` and the search enters it.

### KM-9 The reflected view of a running object draws its own tree beside the tree slice

- **Kind:** several-ways · **Value:** low · **Effort:** medium · **Confidence:** medium
- **Principle:** first principle 8 (reuse an existing view before a new one is made); PAR-DELEGATE-ONE-LEVEL.
- **Today:** `ReflectedNode` is the shadow document of any Julia object: a label, a kind, a value and children ([DocumentReflection.jl:35](../../../source/platform/reflection/DocumentReflection.jl#L35)). `ReflectionToWidget` prints it as a `WidgetTree` with a walk of its own, `_tree_node`, which builds every row of the open part in one computation ([ReflectionToWidget.jl:85](../../../source/platform/reflection/ReflectionToWidget.jl#L85)), keeps a table from row path to node, and has an operation of its own for a chevron, `SetReflectedDisclosureOperation`. The tree slice, which came later (2026-10-15, against 2026-07-26 for this projection), shows "a document of any type as a tree of its parts" through four functions that a node type answers: `get_tree_children_steps`, `format_tree_node_label`, `has_tree_children`, `demand_tree_children` ([TreeInterface.jl:23](../../../source/platform/tree/TreeInterface.jl#L23)). `SystemProcessTreeToDocumentTree` uses it: its printer makes a `DocumentTree` of its input in three lines.
- **Example:**
  ```julia
  # today
  ChainingProjection(ReflectionToWidget(), WidgetToGraphics())

  # after: a reflected node is a node of the tree slice
  get_tree_children_steps(::ReflectedNode) = ((FieldReferenceStep("children"),),)
  format_tree_node_label(node::ReflectedNode) = …
  has_tree_children(node::ReflectedNode) = node.children !== nothing
  demand_tree_children(node::ReflectedNode) = request_sync!(node.children)
  ```
- **Problem:** The reflected tree does not get what the tree slice has: open nodes kept by identity, lazy rows, a double click that opens a node as a page, the reveal of a path. A change of one node prints the whole open tree again, because one cell holds the walk.
- **Proposal:** Give `ReflectedNode` the four methods and show it through `DocumentTree`. Keep `ReflectedNode`, the bounded sync and the feed.
- **What goes away:** `ReflectionToWidget.jl` (213 lines) and `SetReflectedDisclosureOperation`.
- **What stays:** the view on demand as a tree; opening one level at a time; the bound of the sync.
- **Risk and open questions:** Closing a node drops its subtree from the shadow at once today; in the tree slice a closed node only stops being read. The release of a closed subtree needs a hook, or the memory of the shadow grows. I did not read `DocumentTreeToWidgetTree.jl` (645 lines). The one caller in this repository is `example/projectured/ValueViewer.jl`. omnet-julia uses it: `SimulationInspectorToWidget.jl:75` chains `ReflectionToWidget()`, and two readers pass `SetReflectedDisclosureOperation` on (`CatalogShellToWidget.jl:290`, `SimulationEmbedToWidget.jl:1503`). This finding reaches the area of the tree and widget views.
- **Related plans:** `plan/pending/a-click-reaches-the-innermost-part-in-every-view.md` and `packages-compose-by-seams.md` name `ReflectionToWidget` (not read in full).
- **Check:** weakened, value stays low. I opened the reflection module text, the head of `ReflectionToWidget.jl`, `TreeInterface.jl` and the callers in the three repositories. The two trees exist as said, and the walk of the reflected tree is one cell. But the difference has a stated reason that the proposal does not keep. The reflection slice records which nodes are open in the shadow itself, and nowhere else: "Expansion state therefore needs no side table: it *is* the presence or absence of markers in the shadow" (`ReflectionModule.jl:21`), and "the shadow is the only place expansion is recorded" (`ReflectionToWidget.jl:30`). That is what keeps the shadow of a large running object small: it grows where a person opened a node, and a closed node gives its subtree back at once ("collapsing is IMMEDIATE — the subtree is dropped behind a marker", on purpose, `DocumentReflection.jl:48` to 52). The same docstring gives the reason for `SetReflectedDisclosureOperation`: the reader stays pure, and opening a node can be undone and written by a script as every other edit. The tree slice keeps its open nodes in the tree document, by identity. So with the four methods of the proposal the open state is in two places that must agree, and a closed node keeps its subtree in the shadow. The report names this in its risk: it "needs a hook", which is a new mechanism in the tree slice, and it did not read `DocumentTreeToWidgetTree.jl`. The feature that would be lost without that hook is the bound on the memory of the shadow. The change also reaches omnet-julia (three files, above). What remains: the gains for the reflected tree are real (lazy rows, the reveal of a path, one row printed again and not the whole tree), so the question to the owner is whether the tree slice gets a way to tell a node type that a node closed.

## Covered by plans

- The hand-written node projections of `SqlToSyntax.jl`, `MathToSyntax.jl`, `FormulaToSyntax.jl` and `CollectionToSyntax.jl` (table 2): `projection-template-engine.md`, in progress, stages B and C open.
- The `selection` and `mouse_target` fields that `@document` adds, the `collapsed` field of the JSON types, and `FocusingProjection` keeping its part in the projection: `views-compose-as-content-composes.md`, decided, later.
- Only the mouse-target chain follows a splice (`_follow_written_chain!` in `PathChain.jl`), and the selection has a chain function of its own: `an-insert-moves-the-paths-after-it.md`, pending.
- Fields declared `Any` where domains compose: `narrow-the-composition-point.md` and `strict-document-types.md`, in progress.
- The names of the parameters of the four functions: `unify-projection-api-parameter-names.md`, not started, waits for the template conversion.
- `print_document_pure` and `print_child_pure`, a second recursive pair with no caller: kernel audit L17-9.
- The cost of a reactive cell and of a slot of a `CellVector`: `cheap-reactive-cells.md`, in progress.
- Two senses of a `print_` name: `a-print-writes-and-a-make-answers.md`, pending.
- A stage that adds elements to a collection: `injecting-projection.md`, in progress (see KM-6).

## Examined and sound

- The four kinds of cell: each has a contract that no other has. `UntrackedCell` is decision D9 of `plan/done/zoom-and-theme-controls.md` (a style field reads the theme with no edge), with the rejected ways written down. `MutableCell` serves the native state of the sibling repositories.
- The layouts of a `@document` schema (cell layout, native layout, family, aliases, layout list, preset): decided in `plan/done/document-layouts-and-names.md`; omnet-julia uses the lists (28 declarations, 35 preset uses).
- The reconcilers `make_reconciled_child_iomaps_cell` and `make_reconciled_child_iomap_cell`: one mechanism that the template, the chain, the reference dispatch and the switch all use.
- `ReplacePathOperation`: one reader method maps the selection, the mouse target and the start of a drag, and a later kind needs no code there.
- `make_output_path_cells` and `set_output_path_computations!`: one forward map wires every kind of path of an output.
- `ChainingProjection`: reads last to first, with one rule for a claim that no stage can carry; one place, used 115 times.
- `WrappingOperation`: the right model of a generic wrapper, and the base of KM-2 and KM-3.
- `@domain` and `@insertion`: one line gives a domain its root, its nothing, its insertion and its gestures; the JSON domain adds six `@insertion` lines.
- The bounded sync of the reflection slice: a policy of the one kernel walk, not a second walk, as its module text explains.
- `ProjectionReferenceStep` for a part that a projection printed: one step, mapped forward and backward by every wiring.
- The range and the space of `PrinterContext` in the kernel: decided in `plan/done/layout-sizing-model.md` and `plan/done/the-window-has-one-system-for-space.md`; I did not review it further.
- `@projection` with `UntrackedCell` named 380 times against 15 uses of the default: a matter of the default of one macro, too small for a finding.

## Check of the report

A second agent checked each finding against the code at commit 3a9b4fae4, the rules, the design
documents and the plans, and tried to refute it. It read only; it ran no Julia. The line
"**Check:**" under each finding gives the detail. Counts that were wrong are corrected where they
stand.

| Id | Verdict | Value in the report | Value after the check | What remains |
| --- | --- | --- | --- | --- |
| KM-1 | confirmed-with-corrections | high | high | One reader form. Counts corrected (441 methods, about 360 of them 3-argument). `ClaimedGesture` does not go by the change of the signature alone. |
| KM-2 | confirmed-with-corrections | high | medium | A base for the wrappers, with the step to the content as a second accessor; about 17 IO map types, not 24. Leave out the property forwarding by a trait. |
| KM-3 | weakened | high | medium | The generic walk over an operation tree holds. The new default "an operation with no reference travels" goes against a stated default and the owner's decision L13-8 of 2026-09-30. |
| KM-4 | confirmed-with-corrections | medium | medium | One slot list for the node shapes; the leaf wiring stays. 31 methods, the file is not sealed, the audit fixes are done. |
| KM-5 | weakened | medium | low | Two mechanisms, each written twice, and one projection would still hold both. The rule "always read through the projection of the IO map" loses a wrapper in the chosen slot. |
| KM-6 | weakened | medium | low | Only the filter is a second implementation of the picking stage. The sort and the reverse print their children through the recursion; `SortingAtProjection` depends on it. |
| KM-7 | refuted | medium | none | The rules say "zero concrete documents" in the kernel. The seams that have a fault are open questions L17-17, L10-6 and L13-3 of `kernel-audit-fixes.md`. |
| KM-8 | weakened | medium | low | `child_reference_steps` is covered by the open question L13-3. The copy and the sync do another job; the tree steps and the form fields are choices of a view. |
| KM-9 | weakened | low | low | The reflected tree keeps its open state in the shadow on purpose, and drops a closed subtree at once. The proposal needs a new hook in the tree slice to keep that. |

Seen during the check and not in the report:

- An operation with no registration is treated in two ways. `reroot_operation` passes it on as it is
  (`source/kernel/operation/Rerooting.jl:32` to 36), and the default reader drops it unless
  `is_self_contained_operation` answers `true` (`source/kernel/projection/ProjectionDefaults.jl:221`).
  So the same operation passes a container and is lost in a chain stage. One rule should serve both.
- `SortingProjection` keeps the IO maps of its elements in the order of the input and reads them
  by the place in the output, in both maps (`source/platform/projection/generic/Sorting.jl:89` and
  `:103`). A path below a sorted element goes through the IO map of another element whenever the
  order differs. It shows only when the elements have maps that differ from each other; I read the
  code and ran no test.
- `ReferenceDispatchingProjection` reads through `get_iomap_projection` of the inner IO map
  (`source/platform/projection/higherorder/ReferenceDispatching.jl:130`), and the type dispatch and
  the switch read through the projection that they chose. A `RecursiveProjection` in the chosen slot
  takes part in the second way and is skipped in the first.
