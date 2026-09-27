# Layer 10 — document (`source/kernel/document/`)

Commit 15b40434, 2026-09-27. Seal state: 2 of 10 sealed (`DocumentSearch.jl`, `ForwardProtocol.jl`).

## Verdict

The layer has three High faults, and each gives a wrong result with no error.
`search_documents` drops every document after the first that holds an equal scalar value (L10-1).
The path walk never records a `@document` node, so a cycle stops only at `maxdepth` and two links per node make the path count grow exponentially (L10-2).
`sync_document!` stores a mutable leaf value in the shadow by reference, so later changes reach no reader (L10-3).
The copy has five Medium faults: parametric schemas, vector element types, the `Vector`→`CellVector` substitution, back-links and nested collections (L10-4 to L10-8).
The 5 kernel-suite failures on `main` come from a stale test, not from the macro (L10-14), and the layer design document and the `@document` docstring contain false statements.

## Shape

- Purpose: the document contract. The layer holds the `Document` supertype, the `@document` codegen, the value protocol (copy, shadow sync, duplicate), the reflection walk and its value search, the value that a `selection` cell holds, and the protocol forward macros.
- Files:

| file | lines | seal | what it holds |
| --- | ---: | --- | --- |
| `DocumentModule.jl` | 60 | ⬜ | module docstring, header, export block, includes |
| `DocumentInterface.jl` | 439 | ⬜ | `Document`, `CopyPolicy`, 28 bodiless generics |
| `DocumentDefaults.jl` | 120 | ⬜ | trait defaults, policy-hook defaults, layout-registry defaults, `HiddenElements`, debug `show` |
| `DocumentCopy.jl` | 246 | ⬜ | `copy_document` (policy form and kind form), `DuplicatePolicy`, `DocumentCopyException` |
| `DocumentSync.jl` | 135 | ⬜ | `sync_document!`, record and positional walks, the bound |
| `DocumentMacro.jl` | 751 | ⬜ | `@document`, `@document_preset`, eight emitters |
| `SelectionDocument.jl` | 69 | ⬜ | `SelectionDocument`, `unwrap_selection` |
| `DocumentWalk.jl` | 224 | ⬜ | `DocumentWalk`, `walk_document`, `make_string_predicate` |
| `DocumentSearch.jl` | 14 | 🔒 | `search_documents` |
| `ForwardProtocol.jl` | 137 | 🔒 | `@forward_protocol`, `@forward_vector_protocol`, `@adapt_map_protocol` |

- Seal history: both sealed files were sealed on 2026-07-18 (commit 1fb02fa6). After the seal, a path move (cff9c079) changed both of them, and a rename sweep (0b77137a, `string_predicate` → `make_string_predicate`) changed `DocumentSearch.jl`. Both changes are mechanical. `DocumentWalk.jl` was unsealed on 2026-09-23 with the owner's permission (6d273c85). The owner keeps its re-seal for a review of his own.
- Imports: `using ..CellModule`, `using ..CellStructModule` (layers 3 and 4). No import of a higher layer.
- Imported by: 7 kernel modules (selection, reference, operation, binding, projection, llm, editor), 58 files in `source/` outside the kernel, and 87 files in omnet-julia and inet-julia.
- Public surface: 50 exported names. There are 43 names in the export block. The `@document struct SelectionDocument` expansion exports 7 more (`ASelectionDocument`, `ACSelectionDocument`, `RC…`, `IC…`, `MC…`, `DC…`, `MSelectionDocument`). Most names have users outside the kernel. No user outside the layer: `copy_selection_cell` (no method except its default) and the 7 generated `SelectionDocument` names. `@forward_protocol`, `HiddenElements`, `get_document_family` and `DOCUMENT_SHOW_MAX_DEPTH` each have one user.
- State: no process-global mutable state. The constants are tuples, an `Int` and one `const` vector (`_VECTOR_PROTOCOL`) that only the macro reads at expansion time. `DuplicatePolicy` holds its memo for one copy. The walk makes its visited sets for each call.
- Tests: `test/kernel/document/` has 2 files. `DocumentContractTest.jl` passes 75 of 75. `DocumentMacroTest.jl` passes 84 and has 3 Fail and 2 Error on `main`; see L10-14. Five more files test this layer from the substrate test package because their fixtures are substrate types: `DocumentWalkTest.jl`, `BoundedSyncTest.jl`, `DocumentDuplicateTest.jl`, `CollectionDocumentTest.jl` and `DocumentReflectionTest.jl`. No test covers the failure scenarios of L10-1 to L10-8; see L10-15.

## Summary

| Category | High | Medium | Low |
| --- | ---: | ---: | ---: |
| Correctness | 3 | 6 | 5 |
| Architecture | 0 | 1 | 0 |
| Shape | 0 | 1 | 1 |
| Types/performance | 0 | 0 | 1 |
| Naming | 0 | 0 | 1 |
| Documentation | 0 | 2 | 2 |
| Tests | 0 | 2 | 1 |
| **Total** | **3** | **12** | **11** |

## Findings

### L10-1 `search_documents` reports only the first document that holds a given scalar value

- Category: Correctness · Severity: High · Confidence: Confirmed by a run
- Checked by the lead on 2026-09-27: A run: two `@document` values that each hold the value 5. `search_documents` finds 1 of the 2, also with `raw = true`.
- Where: [DocumentWalk.jl:141](../../../source/kernel/document/DocumentWalk.jl#L141) ⬜, [DocumentWalk.jl:172](../../../source/kernel/document/DocumentWalk.jl#L172) ⬜
- Evidence: Under `:once_per_object`, `_enter_node` puts every node in `seen`, and scalar leaves are included: `haskey(seen, obj) && return nothing; seen[obj] = true`. `seen` is an `IdDict`, and two equal numbers, symbols or strings are the same key (`===`). Example: `search_documents(CellVector([PrimitiveNumber(7), PrimitiveNumber(7)]), x -> x == 7)`. The walk reports the first `PrimitiveNumber`. The leaf `7` of the second one is already in `seen`, so the walk prunes it before the predicate runs, and the second document is not reported. The same happens for a `String` query, which is what the assistant prompt teaches: "`search_documents(editor.document, query)` returns the matching document nodes themselves (each once)" ([AssistantDocument.jl:27](../../../source/assistant/AssistantDocument.jl#L27)). The comment at [DocumentWalk.jl:128-131](../../../source/kernel/document/DocumentWalk.jl#L128) says this collapse is deliberate. That is correct for `raw=true`, but with the default fold to the enclosing document it loses a different document. Every scalar leaf also costs one `IdDict` insert, which is O(n) extra memory for a numeric array.
- Rule: bug; PAR-SEARCH-DONT-WALK says "a bare string/regex query matches every occurrence of the same value".
- Fix: Do not put a walk leaf in `seen`. A leaf has no children, so it cannot close a cycle. Run the predicate and the `reported` check first, then do `is_walk_leaf(obj) && return` before `_enter_node`. `reported` still reports each location once.
- Reach: `DocumentWalk.jl` only. `DocumentSearch.jl` 🔒 does not change. Add a test to `DocumentWalkTest.jl`.

### L10-2 The path walk never records a `@document` node, so a cycle stops only at `maxdepth`

- Category: Correctness · Severity: High · Confidence: Confirmed by a run
- Checked by the lead on 2026-09-27: A run: a doubly linked list of three `ListNode`s gives 126, 510, 2046 and 8190 results at `maxdepth` 12, 16, 20 and 24 (0.38 s at 24). The default `maxdepth` is 64, so the count is about 2^32.
- Where: [DocumentWalk.jl:133-139](../../../source/kernel/document/DocumentWalk.jl#L133) ⬜
- Evidence: Under `:once_per_path`, `_enter_node` records a node only `if ismutable(obj)`. Every `@document` cell layout is an immutable struct, so the walk never records a document as an ancestor. `ListNode` is one of them, and `prev`/`next` close a loop. The test pins the defect: [DocumentWalkTest.jl:72](../../../test/substrate/document/DocumentWalkTest.jl#L72) asserts that `search_references(a, is_str; maxdepth = 8)` returns fewer results than `maxdepth = 64` for a 2-node loop. That is true only because the loop is not cut. Consider a 3-node doubly linked list, or the lazy prime list of [LazyDocumentExample.jl](../../../example/substrate/LazyDocumentExample.jl), which links `prev` back to its parent. At every middle node the walk can take `prev` or `next`, so about 2^32 paths reach depth 64. Each path pushes results and copies `seen` at each mutable node. `ConversationDraft.assistant` ([ConversationDocument.jl:120](../../../source/conversation/ConversationDocument.jl#L120)) is a real back-link: from an assistant pane, the walk walks the assistant subtree again at every second level down to depth 64. The sealed [ReferenceSearch.jl](../../../source/kernel/reference/ReferenceSearch.jl) docstring says the ancestor rule keeps a doubly linked list finite. That is false.
- Rule: bug. The `DocumentWalk` docstring promises that "a path that loops back through one of its own ancestors is dropped".
- Fix: Record every node that is not a walk leaf, not only mutable ones. The `IdDict` key of an immutable document is the identity of its cells, so it is a stable key. Change the test at line 72 so that it asserts a count that does not grow with `maxdepth`.
- Reach: `DocumentWalk.jl`, `DocumentWalkTest.jl`. The docstring in `ReferenceSearch.jl` 🔒 becomes true again with no edit.

### L10-3 `sync_document!` writes a leaf container into the shadow by reference, and later changes never invalidate

- Category: Correctness · Severity: High · Confidence: Confirmed (code, and two notes in omnet-julia)
- Checked by the lead on 2026-09-27: Read the code: line 83 writes `sv` by reference, and the next sync compares the object with itself.
- Where: [DocumentSync.jl:83](../../../source/kernel/document/DocumentSync.jl#L83) ⬜, [DocumentSync.jl:111](../../../source/kernel/document/DocumentSync.jl#L111) ⬜
- Evidence: A field value that is not a `Document` is a leaf: `isequal(cur, sv) || setproperty!(shadow, nm, sv)`. When a `Vector`, `Dict` or other mutable container changes, the sync stores the source's own object in the shadow cell. The native source then changes that object in place (`push!`). The shadow now shows the new content, but the sync wrote no cell, so no reader is invalidated. The next `isequal(cur, sv)` compares the object with itself, so the sync writes nothing again. The display stays stale with no error. omnet-julia records this: "it stores the run path's OWN vector in the interface's document, so the two alias and nothing invalidates again" (`VectorResult.jl:85-90`), and "`sync_document!` aliases the native one" (`ParallelEngine.jl:718`). The shadow document is the double-buffer target that the layer exists for ([DocumentSync.jl:3-8](../../../source/kernel/document/DocumentSync.jl#L3)).
- Rule: bug; PAR-WRITE-DRIVEN-PROPAGATION (the shadow changes with no write).
- Fix: Write a copy of a mutable leaf container, not the object itself. For a positional container, sync it into the shadow's collection. For other containers, compare by value against a copy that the shadow owns.
- Reach: `DocumentSync.jl`; `BoundedSyncTest.jl` or `DocumentContractTest.jl` for a test. omnet-julia can then drop `sync_vector_result!`.

### L10-4 A copy of a parametric schema rebinds or loses the programmer's type parameter

- Category: Correctness · Severity: Medium · Confidence: Confirmed (code); the `TypeError` is not run
- Where: [DocumentCopy.jl:95](../../../source/kernel/document/DocumentCopy.jl#L95), [DocumentCopy.jl:105](../../../source/kernel/document/DocumentCopy.jl#L105), [DocumentCopy.jl:224](../../../source/kernel/document/DocumentCopy.jl#L224), [DocumentCopy.jl:245](../../../source/kernel/document/DocumentCopy.jl#L245) ⬜
- Evidence: Both copy forms rebuild through the bare `UnionAll` (`Base.typename(T).wrapper`, `get_document_cell_type(T)`) and pass cells. The outer constructor of the schema then binds the parameter from `get_cell_struct_argument_type(cell)`, which is `Any` for a `ReactiveCell{Any}` ([CellStruct.jl:255](../../../source/kernel/struct/CellStruct.jl#L255)). So `copy_document(DmParametric(3))` gives `DmParametric{Any,…}`, not `DmParametric{Int,…}`. `copy_document(DmBounded(2.0))` asks for `DmBounded{Any}`, and `A<:Real` rejects it with a `TypeError`. A schema whose parameter no field binds, such as omnet-julia's `SequentialEngine{A}`, has no bare constructor, so a copy or a sync rebuild of it is a `MethodError`. omnet-julia builds that shadow by hand (`reactive_simulator`).
- Rule: bug.
- Fix: Take the programmer's parameters from `typeof(document)` (the first parameters of the cell layout) and call `base{params…}(args…)`.
- Reach: `DocumentCopy.jl`; a test in `DocumentMacroTest.jl` or `DocumentContractTest.jl`.

### L10-5 The copy of a vector narrows its element type and drops an `AbstractVector` wrapper

- Category: Correctness · Severity: Medium · Confidence: Confirmed (code, and two workarounds in omnet-julia)
- Where: [DocumentCopy.jl:56](../../../source/kernel/document/DocumentCopy.jl#L56), [DocumentCopy.jl:179](../../../source/kernel/document/DocumentCopy.jl#L179) ⬜
- Evidence: `copy_document(policy, v::AbstractVector) = [copy_document(policy, x) for x in v]`. The unbounded kind form does the same. A comprehension takes its element type from the values it produces. So a `Vector{JsonValue}` that holds only `JsonString`s comes back as a `Vector{JsonString}`, and a later `push!` of a `JsonNumber` fails. Two special methods keep `Vector{Cell}` and `Vector{Any}` (lines 60 and 64); every other abstract element type narrows. A range, a `BitVector` or an `AbstractVector` document such as omnet-julia's `Sweep` comes back as a plain `Vector`. omnet-julia widened a field type because of this (`Configuration.jl:350-356`), and it wrote its own `copy_document` for `ASweep` (`Configuration.jl:101-137`). The bounded path uses `similar(v, 0)` (line 182), so the element type depends on whether the copy has a policy.
- Rule: bug.
- Fix: Build the result with `similar(v)` and set the elements, as the bounded path does. Keep the `AbstractVector` type when `similar` returns the same type.
- Reach: `DocumentCopy.jl`. omnet-julia can then drop two workarounds.

### L10-6 The `Vector` to `CellVector` substitution changes only the alias types, and no constructor builds a `CellVector`

- Category: Correctness · Severity: Medium · Confidence: Confirmed (code); the `MethodError` is not run
- Where: [DocumentMacro.jl:78-84](../../../source/kernel/document/DocumentMacro.jl#L78), [DocumentMacro.jl:141](../../../source/kernel/document/DocumentMacro.jl#L141), [DocumentMacro.jl:256](../../../source/kernel/document/DocumentMacro.jl#L256), [DocumentMacro.jl:270](../../../source/kernel/document/DocumentMacro.jl#L270), [DocumentInterface.jl:166-171](../../../source/kernel/document/DocumentInterface.jl#L166) ⬜
- Evidence: The docstring of `get_cell_layout_field_type` says: "the cell layout substitutes the reactive collection, so an editor still gets one cell per element". The code does not do that:
  - The bare constructor takes its cell types from `get_cell_struct_value_types` (line 140), not from the substituted `_cell_value_types`. A raw `Vector` is stored as one cell around a plain vector.
  - `ICFoo(…)` and `MCFoo(…)` call `ImmutableCell{CellVector}(v)` and `MutableCell{CellVector}(v)` (line 270). The default constructor of a cell converts `v` to `CellVector`, and no such `convert` exists, so the call is a `MethodError`.
  - `DCFoo` names the substituted types (line 256), but the bare constructor builds the unsubstituted ones. For a `[DC]` schema with a kind marker and a `Vector` field, the bare name therefore builds a value that is not of the type that the bare name denotes.
  - `copy_document(K, doc)` falls back to `typeof(v)` (line 214), and the sync writes the raw vector (L10-3).
  omnet-julia converts by hand (`lift_parameter_value`, `Parameters.jl:208`), and a note says a `Vector{Parameter}` field "is already a bare `Vector`". No test in `test/` names `get_cell_layout_field_type`.
- Rule: bug; PAR-HONEST-DOCS.
- Fix: Wrap a raw `AbstractVector` argument in the substituted type in the generated constructors and in the kind copy, as Rule C does for a declared `CellVector`. Otherwise, remove the substitution and the claim.
- Reach: `DocumentMacro.jl`, `DocumentCopy.jl`, `DocumentInterface.jl`; the collection slice registers the type. Many schemas in omnet-julia and inet-julia declare `Vector{T}` fields.

### L10-7 The plain copy, the kind copy and the sync follow a back-link until the stack overflows

- Category: Correctness · Severity: Medium · Confidence: Confirmed (code); no caller path to the overflow was run
- Where: [DocumentCopy.jl:48](../../../source/kernel/document/DocumentCopy.jl#L48), [DocumentCopy.jl:217-246](../../../source/kernel/document/DocumentCopy.jl#L217), [DocumentSync.jl:62-70](../../../source/kernel/document/DocumentSync.jl#L62) ⬜
- Evidence: Only a policy with a memo stops a cycle ([DocumentCopy.jl:87-94](../../../source/kernel/document/DocumentCopy.jl#L87)). `PlainCopyPolicy` has none, the kind form has none, and the sync keeps no set of visited nodes. `ConversationDraft.assistant` holds the owning `Assistant`, whose `draft` holds the draft ([ConversationDocument.jl:120](../../../source/conversation/ConversationDocument.jl#L120)). So `copy_document(assistant)`, `copy_document(ReactiveCell, assistant)` or a sync over it recurses without end and throws `StackOverflowError`. Callers of the plain copy include `VersioningToAny.jl:168` (`copy_document(version.value)`) and `_pure_snapshot` in the projection layer. The `get_copy_memo` docstring states this for the policy form only. The kind form and `sync_document!` do not say it.
- Rule: bug.
- Fix: Give `PlainCopyPolicy` a memo, or stop a back-link with a `DocumentCopyException` as `DuplicatePolicy` does. Give the kind copy and the sync a visited set.
- Reach: `DocumentCopy.jl`, `DocumentSync.jl`, `DocumentInterface.jl` (docstrings).

### L10-8 A nested collection bypasses its own kind-copy method, and the extension signature is not documented

- Category: Correctness · Severity: Medium · Confidence: Confirmed (dispatch); the `MethodError` is derived, not run
- Where: [DocumentCopy.jl:169-200](../../../source/kernel/document/DocumentCopy.jl#L169), [DocumentCopy.jl:241](../../../source/kernel/document/DocumentCopy.jl#L241), [DocumentInterface.jl:181-215](../../../source/kernel/document/DocumentInterface.jl#L181) ⬜
- Evidence: The kind walk calls every child with four positional arguments: `copy_document(K, inner, policy, depth + 1)`. `CellVector` specializes only the two-argument form ([CellVector.jl:295](../../../source/collection/CellVector.jl#L295)), so a `CellVector` in a field or in a slot cell goes through the generic field walk. For `K = MutableCell` that walk stores `Vector{MutableCell{T}}` slot cells inside a `MutableCell{Vector}`. The top-level method stores plain values. `setindex!` and `push!` for that kind write a plain value into the vector ([CellVector.jl:188-192](../../../source/collection/CellVector.jl#L188)), which then needs a `convert` to `MutableCell{T}` that does not exist. `ListNode.jl:48` and omnet-julia's `ASweep` extend the four-argument form, so that form is the real extension point. The contract docstring names only `copy_document(K, value)`. The signature has two optional positional arguments (`policy = nothing, depth::Int = 0`), and so does `sync_document!`. The protocol list of the argument guard excuses the count, but not the optional-argument clause.
- Rule: bug; code-quality-rules.md §4 ("at most one optional positional argument").
- Fix: Document the four-argument form as the method a kind adds, or route the walk through one entry that the two-argument specializations also reach. Move `CellVector`'s method to the four-argument form. Make `policy` and `depth` keywords, or add a marker that states the exception.
- Reach: `DocumentCopy.jl`, `DocumentSync.jl`, `DocumentInterface.jl`; `CellVector.jl`, `ListNode.jl`, `BoundedSync.jl`; omnet-julia `Configuration.jl`.

### L10-9 The walk enters closures, type objects and undo history, so a search finds nodes that are not on the screen

- Category: Correctness · Severity: Medium · Confidence: Confirmed (code); the undo case was seen in a session on 2026-09-26
- Where: [DocumentWalk.jl:60-61](../../../source/kernel/document/DocumentWalk.jl#L60), [DocumentWalk.jl:212-222](../../../source/kernel/document/DocumentWalk.jl#L212) ⬜
- Evidence: `is_walk_leaf` stops only at `nothing`, `Number`, `AbstractString`, `Symbol`, `Char` and opaque documents. Every other struct is entered by `fieldnames`. That includes a closure (its captured variables, which can hold an editor or another tree), a `DataType` (its `TypeName`, method table and cache), and an `UndoBuffer`'s `redo_entries` ([UndoDocument.jl:76](../../../source/undo/UndoDocument.jl#L76)). A search from the root found an undone tab in the redo entries. PAR-SEARCH-DONT-WALK expects results that can be selected. The `UndoBuffer` declares `get_edited_field(::UndoBuffer) = :content`, but the walk does not read it. Callers add `descend` predicates one at a time (`is_pane_search_step`, `_is_draft_search_step`).
- Rule: PAR-SEARCH-DONT-WALK (results must be selectable); bug.
- Fix: Treat `Function`, `Type`, `Module` and `Task` as walk leaves. Give a wrapper a way to hide its history, through `is_walk_opaque` on the history container or a default `descend` that follows `get_edited_field`.
- Reach: `DocumentWalk.jl`; possibly `UndoDocument.jl`.

### L10-10 The walk swallows every exception from the predicate, `InterruptException` included

- Category: Architecture · Severity: Medium · Confidence: Confirmed (code)
- Where: [DocumentWalk.jl:175](../../../source/kernel/document/DocumentWalk.jl#L175), [DocumentWalk.jl:213](../../../source/kernel/document/DocumentWalk.jl#L213) ⬜
- Evidence: `if (try predicate(obj) catch; false end)` and `fnames = try fieldnames(typeof(obj)) catch; () end`. Both catch every exception and record none. A Ctrl+C during a long search is lost at one node, and the walk goes on. A `StackOverflowError` or `OutOfMemoryError` in a predicate becomes "no match". A bug in a predicate gives an empty result and no trace. The fault layer (layer 1) provides `is_passthrough_exception` for exactly this.
- Rule: PAR-REPORT-NEVER-THROWS ("a barrier never swallows a fault in silence"; pass-through exceptions are never caught).
- Fix: Rethrow when `is_passthrough_exception(e)`. Record other exceptions, or let them reach the caller. `fieldnames` of a concrete type does not throw, so remove that `try`.
- Reach: `DocumentWalk.jl`, `DocumentModule.jl` (add `using ..FaultModule`).

### L10-11 The `@document` expansion depends on which methods exist at the moment the macro runs

- Category: Shape · Severity: Medium · Confidence: Suspected (needs a re-expansion under Revise)
- Where: [DocumentMacro.jl:81](../../../source/kernel/document/DocumentMacro.jl#L81), [DocumentMacro.jl:336](../../../source/kernel/document/DocumentMacro.jl#L336) ⬜
- Evidence: The macro calls two open generics at expansion time: `get_cell_layout_field_type(Val(name))` and `is_collection_field_type(Val(t))`. Higher packages add their methods. So the same declaration expands differently before and after the collection package loads. [CellVector.jl:33-35](../../../source/collection/CellVector.jl#L33) declares `elements::Vector` before line 58 registers `get_cell_layout_field_type(::Val{:Vector}) = CellVector`. A re-expansion after the registration would give `CellVector` its own type as element storage in the aliases. Julia 1.12 can redefine a struct, so Revise can trigger that re-expansion. The commit that added the seam (3bdf2eb2) checked the order by hand ("nothing expands before `CellVector.jl` fills the seam"). No guard holds that order.
- Rule: PAR-FRAMEWORKS-SINK (a seam is a call at run time, not at expansion time); code-quality-rules.md §3, "A trait keeps a concrete type out of a lower layer".
- Fix: Emit the substitution as a call at run time: the generated code asks `get_cell_layout_field_type` when it is evaluated. Otherwise, register the `Val{:Vector}` method before the `@document struct CellVector` declaration, excluded from it, and add a test for the order.
- Reach: `DocumentMacro.jl`; `CellVector.jl`.

### L10-12 The `@document` docstring states several things that the code does not do

- Category: Documentation · Severity: Medium · Confidence: Confirmed (code)
- Where: [DocumentMacro.jl:440-534](../../../source/kernel/document/DocumentMacro.jl#L440), [DocumentMacro.jl:3](../../../source/kernel/document/DocumentMacro.jl#L3), [DocumentMacro.jl:593](../../../source/kernel/document/DocumentMacro.jl#L593) ⬜
- Evidence:
  - Lines 470-473 say that the injected field is `selection::Union{Nothing, Reference}` and that "declaring it by hand is an **error**". Line 620 injects `Union{Nothing, Reference, SelectionDocument}`. Lines 611-614 accept an explicit `selection` field when it is the last field, and a test covers that case.
  - Lines 498-499 name the kind constructors `ICFoo(args…)` / `MFoo(args…)`. The macro emits `MCFoo` (line 299). `MFoo` is the native layout.
  - Lines 496-497 say that `RCFoo` is "what the bare ctor builds". Line 225 says that the bare constructor builds `DCFoo`, and L10-6 shows that neither is always true.
  - Lines 446-447 and the table name only the layout codes `C`, `DC` and `M`. The code also accepts `I` (line 27).
  - Line 3 says "a parse followed by six emitters". The file has eight `_emit_` functions.
  - The comment at line 593 repeats the old union.
- Rule: PAR-HONEST-DOCS; PAR-MODULE-DOCSTRING ("a docstring that names a function that no longer exists is a defect").
- Fix: Correct the six statements.
- Reach: `DocumentMacro.jl`.

### L10-13 The layer design document and three rule texts describe a layer that no longer exists

- Category: Documentation · Severity: Medium · Confidence: Confirmed (code)
- Where: [document.md](../../../documentation/package/kernel/document.md), [macros.md:85](../../../documentation/package/kernel/macros.md#L85), [architecture-invariants.md](../../../documentation/rule/architecture-invariants.md)
- Evidence:
  - `document.md` omits `SelectionDocument.jl` from its file tree. It gives the injected field as `selection::Reference` and says a hand-written one is an error. It places `Collection` and `Primitive` in `base` and `ScreenDocument` in `visual`, and no such packages exist.
  - `document.md` does not mention the layout list, the layout registry (`get_document_family`/`_cell_type`/`_native_type`/`_schema_name`), `@document_preset`, `get_wrapped_document`/`replace_wrapped_document!`/`get_edited_field`, `get_document_title`, `SelectionDocument`/`unwrap_selection` or `HiddenElements`.
  - "Testing pressure" names only `ToyNode`, but most tests of the layer use substrate fixtures.
  - The duplicate example uses `SimulationFilter` and `filter_runner`, which are types of a private downstream program.
  - `macros.md` lines 85, 100 and 172 repeat the old selection union.
  - PAR-DOCUMENT-IDENTITY says that a `@document` type "is a `mutable struct`". The cell layout is an immutable struct, and `macros.md:516` says so.
  - PAR-NO-NESTED-CELL says that "a cell of another type is a `MethodError`". The stem bounds are `<: AbstractCell` (DocumentMacro.jl:111), and every constructor passes any cell through (lines 159-160, 270).
  - PAR-SEARCH-DONT-WALK says that a string query matches every occurrence, which L10-1 disproves.
- Rule: PAR-UPDATE-THE-GUIDE; PAR-HONEST-DOCS; writing-rules.md "No private name".
- Fix: Rewrite the file tree, the selection paragraph and the contract surface of `document.md`. Replace the example. Correct the three rule texts.
- Reach: `documentation/package/kernel/document.md`, `macros.md`, `architecture-invariants.md`. Planned in part: `plan/pending/documentation-rewrite-survey.md` lists `document.md` as "KEEP" with one pointer to add, and it does not see these defects.

### L10-14 The 5 kernel-suite failures on `main` come from a stale test, and they are not marked broken

- Category: Tests · Severity: Medium · Confidence: Confirmed (code and the baseline log)
- Where: [DocumentMacroTest.jl:10-15](../../../test/kernel/document/DocumentMacroTest.jl#L10), [DocumentMacroTest.jl:28-31](../../../test/kernel/document/DocumentMacroTest.jl#L28), lines 168, 173, 183, 194, 195
- Evidence: Rule C now finds its collection field through `is_collection_field_type(::Val{name})` ([DocumentMacro.jl:336](../../../source/kernel/document/DocumentMacro.jl#L336)). Only [CellVector.jl:46](../../../source/collection/CellVector.jl#L46) registers a method, and the kernel test package does not load it. The test's stand-in `CellVector` registers nothing, so Rule C never fires in the kernel suite. The file docstring still says that "Rule C detects its collection field by matching the declared type's *symbol*". The baseline run of `test_kernel()` shows exactly these five: 2 `MethodError` (lines 168 and 183) and 3 Fail (173, 194, 195). They are plain `@test`, so every kernel run has 5 unmarked non-passes. That breaks the rule that an unmarked Fail is a regression.
- Rule: PAR-MARK-BROKEN-TESTS.
- Fix: Add `DocumentModule.is_collection_field_type(::Val{:CellVector}) = true` beside the stand-in, and correct the file docstring. The five assertions then test the macro again.
- Reach: `test/kernel/document/DocumentMacroTest.jl` only.

### L10-15 No test covers the failure scenarios of this layer's faults

- Category: Tests · Severity: Medium · Confidence: Confirmed (grep of `test/`)
- Where: `test/kernel/document/`, `test/substrate/document/`
- Evidence: No test searches for two documents that hold an equal scalar (L10-1). The only cycle test asserts the defect (L10-2). No test mutates a leaf container between two syncs (L10-3). No test copies a parametric schema (L10-4), checks a vector element type after a copy (L10-5), or names `get_cell_layout_field_type` (L10-6). No test copies a back-linked document without a memo (L10-7) or copies a nested collection by kind (L10-8). The kernel suite has no test of `SelectionDocument` or `unwrap_selection`, a dormant selection through copy and sync, `get_edited_field`, or `replace_wrapped_document!`. `@forward_protocol` and `@adapt_map_protocol` have no direct test.
- Rule: PAR-NEW-CODE-SHIPS-TESTS.
- Fix: Add one case for each of these findings, together with its fix. Add a kernel test of `SelectionDocument` with a toy document.
- Reach: `DocumentContractTest.jl`, `DocumentMacroTest.jl`, `DocumentWalkTest.jl`, `BoundedSyncTest.jl`.

### L10-16 The bounded copy and the bounded sync apply the bound differently at collection elements

- Category: Correctness · Severity: Low · Confidence: Confirmed (code)
- Where: [DocumentCopy.jl:178-194](../../../source/kernel/document/DocumentCopy.jl#L178), [DocumentSync.jl:96-118](../../../source/kernel/document/DocumentSync.jl#L96), [DocumentDefaults.jl:29](../../../source/kernel/document/DocumentDefaults.jl#L29) ⬜
- Evidence:
  - `_copy_elements` never asks `is_descendable_for_sync` for an element document. `_sync_elements!` asks it for every element (line 107). With a policy that stops at depth 1, a shadow that a copy creates holds whole elements, and a shadow that a sync grows holds markers.
  - The copy clamps the limit (`min(limit, n)`), but the sync pushes `source[i]` up to `limit` (line 114). A policy that answers more than `length(source)` causes a `BoundsError`.
  - `HiddenElements` has no bounds check against `to`.
  - The copy passes `()` as the shadow to `sync_element_limit`. The contract says the call gets the whole shadow.
- Rule: bug.
- Fix: Ask the bound for each element in `_copy_elements`. Clamp in `_sync_elements!`. Add `@boundscheck` to `HiddenElements`.
- Reach: `DocumentCopy.jl`, `DocumentSync.jl`, `DocumentDefaults.jl`.

### L10-17 The sync rebuilds children in the kind of the shadow's first field

- Category: Correctness · Severity: Low · Confidence: Confirmed (code); no document in the three repositories hits it now
- Where: [DocumentSync.jl:53](../../../source/kernel/document/DocumentSync.jl#L53) ⬜
- Evidence: `K = get_cell_struct_kind(shadow)` reads the kind of the first field only. In a document with fields of different kinds, a first field declared `ImmutableCell{T}` or `MutableCell{T}` makes every rebuilt child immutable or mutable. The next sync into an immutable child throws a `MethodError`. A mutable child never invalidates its readers.
- Rule: bug.
- Fix: Take the kind from the cell that holds the child slot, or from a field that is not declared with a kind.
- Reach: `DocumentSync.jl`.

### L10-18 The sync reads fields through `getproperty`, which hides a dormant selection

- Category: Correctness · Severity: Low · Confidence: Confirmed (code)
- Where: [DocumentSync.jl:77-83](../../../source/kernel/document/DocumentSync.jl#L77) ⬜
- Evidence: The generated `getproperty` passes the value through `unwrap_selection` ([DocumentMacro.jl:205-206](../../../source/kernel/document/DocumentMacro.jl#L205)). A dormant `SelectionDocument` reads as `nothing`, so the sync writes `nothing` into the shadow's selection and the dormant path is lost. A live one reads as a bare `Reference`. For a native source, `getproperty` is `getfield`, so the source gives a `SelectionDocument` and the shadow gives a reference. The sync then rebuilds and writes the selection on every call, which invalidates every selection reader each frame.
- Rule: bug; PAR-WRITE-DRIVEN-PROPAGATION.
- Fix: Compare and write the `selection` field through `getfield(…)[]`.
- Reach: `DocumentSync.jl`.

### L10-19 The walk skips every field named `ref`, with no comment

- Category: Correctness · Severity: Low · Confidence: Confirmed (code)
- Where: [DocumentWalk.jl:215](../../../source/kernel/document/DocumentWalk.jl#L215) ⬜
- Evidence: `(fn == :ref || …) && continue` is a magic name from an older search (commit e48cdcaa, 2026-06-18). Nothing states the reason. `ref::ImmutableCell{StyleText}` fields exist in [FsmToSyntax.jl:135](../../../source/fsm/FsmToSyntax.jl#L135), line 207, and `FsmDiagramToGraph.jl:45`. `search_documents` and `search_references` cannot find them.
- Rule: PAR-TIGHT-COMMENTS (a constraint the code cannot show needs its sentence); bug.
- Fix: Remove the skip, or replace it with a trait on the type that needs it.
- Reach: `DocumentWalk.jl`.

### L10-20 The forwarded mutators return the field value, and the adapted map has no `length`

- Category: Correctness · Severity: Low · Confidence: Confirmed (code) for the return values; Suspected (not run) for `collect`
- Where: [ForwardProtocol.jl:15-22](../../../source/kernel/document/ForwardProtocol.jl#L15), [ForwardProtocol.jl:49-52](../../../source/kernel/document/ForwardProtocol.jl#L49), [ForwardProtocol.jl:130-135](../../../source/kernel/document/ForwardProtocol.jl#L130) 🔒
- Evidence: `push!`, `insert!`, `deleteat!` and `setindex!` forward as `f(getproperty(x, :field), args…)`, so they return the collection in the field. Base's convention returns the collection that the caller gave, so `push!(wrapper, v) === wrapper` is false. `@adapt_map_protocol` defines `iterate` but no `length`, and `Base.IteratorSize` defaults to `HasLength`. So `length(json_object)` and `collect(json_object)` fail for `JsonObject`, which defines no `length` either.
- Rule: bug.
- Fix: Return `x` from the four mutators. Emit `Base.length` in `@adapt_map_protocol`.
- Reach: `ForwardProtocol.jl` (sealed; needs the owner's permission).

### L10-21 The generated and private surface is larger than the layer needs

- Category: Shape · Severity: Low · Confidence: Confirmed (code)
- Where: [SelectionDocument.jl:59-63](../../../source/kernel/document/SelectionDocument.jl#L59), [DocumentModule.jl:32-48](../../../source/kernel/document/DocumentModule.jl#L32), [DocumentCopy.jl:205](../../../source/kernel/document/DocumentCopy.jl#L205), [DocumentCopy.jl:225-226](../../../source/kernel/document/DocumentCopy.jl#L225) ⬜
- Evidence:
  - `@document struct SelectionDocument` uses the default layouts `[C, M]`. It exports 7 generated names that nothing uses. Its "native" `MSelectionDocument` holds a cell in its `selection` field.
  - `DocumentModule.jl` exports `SelectionDocument` by hand, and the macro exports it too. The export block is one statement for all fragments, with a comment inside (line 47). Planned: `plan/pending/export-block-rule.md`.
  - Every `@document` expansion extends the private `_declared_value_types` from the caller's module, and `DocumentMacroTest.jl:227` reaches it as `DocumentModule._declared_value_types`.
  - `copy_selection_cell` has no method except its default.
  - `base === nothing` at line 225 can never be true, because `get_document_cell_type` never answers `nothing`.
  - `DocumentMacro.jl` has 751 lines against a budget of 500. `_document_expr` has 166 lines and `_emit_kind_aliases` has 73, against a budget of 60 (code-quality-rules.md §5).
- Rule: code-quality-rules.md §1 (the export block) and §5 (budgets); PAR-MODULE-BOUNDARY-IS-API (a private seam).
- Fix: Declare `SelectionDocument` with `[C]`. Split the export block. Export `_declared_value_types` under a public name, or state the exception. Remove the dead check. Split `_document_expr`.
- Reach: `SelectionDocument.jl`, `DocumentModule.jl`, `DocumentCopy.jl`, `DocumentMacro.jl`.

### L10-22 Every generated property read dispatches `unwrap_selection` at run time for a reactive field

- Category: Types/performance · Severity: Low · Confidence: Suspected (needs a measurement)
- Where: [DocumentMacro.jl:197-206](../../../source/kernel/document/DocumentMacro.jl#L197) ⬜
- Evidence: `getproperty` is `unwrap_selection(getfield(obj, name)[])`. The docstring says that the call "resolves on the concrete stored type and inlines away". For the default `ReactiveCell{Any}` field, the stored type is `Any`, so the compiler cannot choose between the two methods. Each read of each field of a reactive document then makes one more dynamic call. That is the hot path that the per-frame `reads` counter counts.
- Rule: bug in the docstring claim; hot-path cost.
- Fix: Measure a read before and after. If the cost shows, call `unwrap_selection` only in the `selection` accessor, for example through a `Val(name)` branch that constant-folds.
- Reach: `DocumentMacro.jl`.

### L10-23 One exported function does not start with a verb

- Category: Naming · Severity: Low · Confidence: Confirmed (code)
- Where: [DocumentInterface.jl:364](../../../source/kernel/document/DocumentInterface.jl#L364), [DocumentSync.jl:30](../../../source/kernel/document/DocumentSync.jl#L30), [DocumentSync.jl:41](../../../source/kernel/document/DocumentSync.jl#L41), [DocumentWalk.jl:60](../../../source/kernel/document/DocumentWalk.jl#L60) ⬜
- Evidence: `sync_element_limit(policy, source, shadow) -> Int` reads as a noun phrase, and it computes a count from the shadow. The naming plans in `plan/pending/` do not list it. The private helpers `is_same_document_type`, `copy_shadow_element` and `is_walk_leaf` have no leading underscore, although the other private helpers of the layer have one.
- Rule: naming-rules.md "Every function name starts with a verb".
- Fix: `compute_sync_element_limit` (use `workspace/bin/julia-rename.jl`). Add the underscore to the three helpers.
- Reach: `DocumentInterface.jl`, `DocumentDefaults.jl`, `DocumentSync.jl`, `DocumentCopy.jl`, `DocumentModule.jl`; `source/reflection/BoundedSync.jl`, `DocumentReflection.jl`; omnet-julia (1 file).

### L10-24 Nine comments describe what the code was

- Category: Documentation · Severity: Low · Confidence: Confirmed (code)
- Where: ⬜ in all of these files:
  - [DocumentInterface.jl:72-74](../../../source/kernel/document/DocumentInterface.jl#L72) ("Before it existed …") and [DocumentInterface.jl:169-170](../../../source/kernel/document/DocumentInterface.jl#L169) ("Before it, a declaration had to name …").
  - [DocumentSync.jl:26-27](../../../source/kernel/document/DocumentSync.jl#L26) ("the old wrapper test … it now also unifies") and [DocumentSync.jl:103](../../../source/kernel/document/DocumentSync.jl#L103) ("the original short-circuit, kept").
  - [DocumentCopy.jl:222-223](../../../source/kernel/document/DocumentCopy.jl#L222) ("is what let a native child land …").
  - [DocumentMacro.jl:24-25](../../../source/kernel/document/DocumentMacro.jl#L24) ("where it has always been"), line 163 and line 263 ("keeps the constructor it had"), line 451 ("emits what it always did"), and lines 638-640 ("before it, the type name was the only way …").
- Rule: code-quality-rules.md §2 "A comment says what is, never what was"; PAR-TIGHT-COMMENTS.
- Fix: Delete each phrase. Keep only the constraint, in the present tense.
- Reach: `DocumentInterface.jl`, `DocumentSync.jl`, `DocumentCopy.jl`, `DocumentMacro.jl`.

### L10-25 Docstrings name higher-layer functions, personify the walk, and give a false count

- Category: Documentation · Severity: Low · Confidence: Confirmed (code)
- Where: [DocumentInterface.jl](../../../source/kernel/document/DocumentInterface.jl) ⬜, [DocumentCopy.jl](../../../source/kernel/document/DocumentCopy.jl) ⬜, [SelectionDocument.jl:13-18](../../../source/kernel/document/SelectionDocument.jl#L13) ⬜, [DocumentSearch.jl:5](../../../source/kernel/document/DocumentSearch.jl#L5) 🔒
- Evidence:
  - Higher-layer names in the interface file: `get_edited_document` (line 418), `write_document_file` (line 384), `read_document_file` (line 403), "A strip asks it each time it prints a tab" (lines 288-289), `ChainModel` (lines 103-106) and `NedParam` (line 167). The sealed `DocumentSearch.jl:5` names `PrimitiveString`.
  - Personification: "A copy refused `value`" ([DocumentCopy.jl:30](../../../source/kernel/document/DocumentCopy.jl#L30)), the `DuplicatePolicy` list "It refuses …" (lines 134-141), "The walk asks …" (DocumentInterface.jl:247) and "the walk knows only …" (line 347).
  - The `Document` docstring has a fifth paragraph after "See also" (lines 31-35).
  - `SelectionDocument.jl` gives "64 modules import the reference layer by name (`import ..ReferenceModule: Reference`)" as the reason for its place. Now 1 file does so, and 66 use a bare `using ..ReferenceModule`.
- Rule: PAR-NO-CONSUMER-DOCS; writing-rules.md "No personification"; code-quality-rules.md §1 (the four parts of a docstring).
- Fix: Name concepts, not functions of higher layers. Rewrite the personified sentences with the mechanism as the subject. Merge the fifth paragraph. State the placement reason without the count: the macro splices the type as an object, so the type must be at or below this layer.
- Reach: `DocumentInterface.jl`, `DocumentCopy.jl`, `SelectionDocument.jl`; `DocumentSearch.jl` (sealed).

### L10-26 The tests of the layer define a struct at run time, test another layer, and carry history comments

- Category: Tests · Severity: Low · Confidence: Confirmed (code and log); Suspected for which reader emits the warnings
- Where: [DocumentMacroTest.jl:370](../../../test/kernel/document/DocumentMacroTest.jl#L370), [DocumentContractTest.jl:96-118](../../../test/kernel/document/DocumentContractTest.jl#L96), [DocumentWalkTest.jl:14](../../../test/substrate/document/DocumentWalkTest.jl#L14)
- Evidence:
  - `@eval @document ImmutableCell struct DmValueSel` runs inside `test_document_macro()`. The first 48 lines of the kernel log hold 8 world-age warnings ("access to binding … in a world prior to its definition world"), and they name exactly the 8 bindings that this expansion exports.
  - `DocumentContractTest.jl` tests `get_selection`, `set_selection!`, `clear_selection!` and `with_selection`. Those belong to the selection layer (layer 12).
  - History comments: `DocumentContractTest.jl:137`, lines 148 and 183, and `DocumentMacroTest.jl:5`.
  - `DocumentWalkTest.jl:14` says that the file "Lives in `base`". `BoundedSyncTest.jl:8` says "the old behaviour".
- Rule: PAR-NEW-CODE-SHIPS-TESTS (right package and layer); code-quality-rules.md §2.
- Fix: Declare `DmValueSel` at the top level, as the other fixtures are. Move the selection cases to `test/kernel/selection/`. Delete the history phrases.
- Reach: the three test files.

## Accepted before, not raised again

- Rule Y's `req ≥ 1` gate: a struct whose fields all have defaults gets no positional constructors. A new default on the only required field removes `Foo(x)`. `plan/done/document-macro-positional-defaults.md`: "The `req ≥ 1` guard is the whole safety story".
- Rule C puts an already built collection inside a new one when a caller passes it to a document whose one field is that collection. `DocumentMacroTest.jl:177-186` pins this as deliberate.
- Rule C finds the collection by the declared type's name, so an alias of the type gets no sugar. `plan/done/document-layer-cleanup.md`, "Known wart, recorded not fixed". The trait `is_collection_field_type(::Val{name})` keeps the key on the name.
- A sync after a front dequeue rewrites the whole tail. `plan/done/cell-kind-documents.md`, "Known limitation, measured not hidden"; the identity-keyed refinement is deferred.
- A bare 2-argument `CellVector(a, b)` reaches the 2-field inner constructor. `plan/done/cell-kind-documents.md`, "Constructor footgun found + documented".
- `MStem` and `MCStem` share a first letter. `plan/done/document-layouts-and-names.md`: accepted.
- `DocumentWalk.jl` is unsealed for the `descend` keyword. The owner keeps its re-seal for a review of his own. Lines 77-78 were already over the line budget on `main`, and they are open for the owner. `plan/done/an-operation-enters-at-any-reference.md`.
- Reactive cells hold `Any`. This report does not flag the storage type. L10-22 is about one extra call on the read.

## Checked and clean

- PAR-INTERFACE-DECLARES-ONLY: `DocumentInterface.jl` holds two abstract types and bodiless generics only, and the export block exports every name that it declares.
- PAR-PACKAGE-CHAIN, PAR-LOWEST-PACKAGE: the layer imports only the cell and struct layers. The layering guard passed on this commit.
- PAR-QUALIFIED-EXTENSION: the fragments define their functions without qualification. `Base` extensions are qualified. The macro extends generics through spliced function objects.
- PAR-PER-EDITOR-STATE, PAR-NO-PROJECTION-GLOBALS: no module-level mutable state. The visited sets and the copy memo live for one call.
- PAR-FIELDS-ARE-CELLS: the macro wraps every field and emits transparent accessors. `getfield` appears only in the copy, sync and walk machinery, which must reach the cells.
- PAR-NO-NESTED-CELL: a `Function` field stays a value through both copy forms (tested at `DocumentContractTest.jl:136-143`). A cell argument becomes the field's cell. The rule text is wrong about the `MethodError` (L10-13).
- PAR-DOCUMENT-IDENTITY: the layer compares leaf values in the sync and never compares whole documents with `==`. The rule text is stale (L10-13).
- PAR-PERSISTENCE-BY-VALUE: the walk unwraps every cell before it descends, so it never reaches `dependents`. Copy and sync read with `c[]`. That is correct for a copy that must follow its source, and neither of them is a serializer.
- PAR-EVERY-DOCUMENT-HAS-SELECTION: the macro injects `selection` last and defaults it, or accepts an explicit field as the last one.
- PAR-EMPTY-PATH-IS-SELECTION: `unwrap_selection` keeps `nothing` (no selection) apart from a dormant selection, as its docstring says.
- The `@document` expansion names `Reference` as a symbol that resolves in the caller's module, so the layer takes no import of layer 11. This is documented at `DocumentMacro.jl:598-603`.
- PAR-NAMING-LAW: the types, macros, predicates and mutators follow the rules, except `sync_element_limit` (L10-23).
