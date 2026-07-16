# Fragment of `OperationModule` — the built-in operations, the selection
# propagation (clear/set/update), the splice helpers, and the
# `child_reference_steps` traversal seam (open generic; base's Collection.jl
# adds the `CellVector` method, others fall through to the default
# fieldnames-walk). The `Operation` supertype + `evaluate_operation` +
# `invalidate_projection!` generics come from `Interface.jl`, already in scope.
#
# `evaluate_operation` is duck-typed on `editor`, so nothing here references
# a concrete editor type — the fragment loads early (well before the editor
# loop) and still works against whatever object carries `editor.document`.

"""
    DoNothingOperation()

An operation that does nothing when applied. Its purpose is to *consume* a
gesture without effecting a change: a reader (or a per-instance gesture binding)
returns `DoNothingOperation()` to say "this gesture is handled — stop looking",
distinct from returning `nothing`, which means "declined, keep looking / fall
through". The canonical way for a per-instance binding to **suppress** a default
behavior (see `get_instance_gesture_bindings`) is to map the pattern to a `DoNothingOperation()`.
"""
struct DoNothingOperation <: Operation end

evaluate_operation(editor, ::DoNothingOperation) = nothing
function evaluate_operation(editor, op::Nothing) end

# Catch-all: silently ignore anything that is not an Operation. Unlike the device
# I/O generics (which deliberately omit a catch-all so an unimplemented backend
# fails loudly), this one is *meant* to swallow: a reader that declines returns a
# raw gesture/event or `nothing`, and those flow all the way up to here, where
# "not an operation" simply means "nothing to apply".
function evaluate_operation(editor, op) end

# Catch-all: an object that caches no projection has nothing to drop. The one that
# does (the editor loop) adds the method that actually clears its cache, so an
# operation can ask without naming a concrete editor type.
invalidate_projection!(editor) = nothing

# ── Text-splice helpers ─────────────────────────────────────────────────────
# The canonical text-replace primitives every domain routes through. They are
# implementations (a single algorithm / a small representation-dispatched method
# set), so they live here rather than in the `Interface.jl` contract.

"""
    splice_string(old, s, e, replacement) -> String

Replace the characters of `old` between 0-based boundaries `[s, e]` with
`replacement`. Character-aware, so multi-byte characters survive intact.
Boundaries are clamped: `s <= 0` keeps nothing on the left, `e >= length(old)`
keeps nothing on the right. This is the one canonical text splice — every
text-replace edit in every domain routes through it.
"""
function splice_string(old::AbstractString, s::Int, e::Int, replacement::AbstractString)
    n = length(old)
    left  = s <= 0 ? "" : first(old, s)
    right = e >= n ? "" : last(old, n - e)
    String(left) * replacement * String(right)
end

"""
    splice_number(old_str, s, e, replacement) -> Union{Int, Float64, Nothing}

Splice the textual form of a number between 0-based boundaries `[s, e]`, then
parse the result back to a number. An integral result parses to `Int`; a result
with a fractional part or exponent parses to `Float64` — so editing `4` into `42`
stays the integer `42` rather than drifting to `42.0`. Returns `nothing` for an
empty result or unparseable input (the value cell tolerates `nothing` as the empty
sentinel).
"""
function splice_number(old_str::AbstractString, s::Int, e::Int, replacement::AbstractString)
    new_str = splice_string(old_str, s, e, replacement)
    isempty(new_str) && return nothing
    something(tryparse(Int, new_str), tryparse(Float64, new_str), Some(nothing))
end

"""
    splice_value!(owner, field, value, s, e, replacement)

Apply a text-replace edit to `owner.<field>` between 0-based boundaries `[s, e]`.
Dispatch is on the *representation* of the current `value` (read from the field
by the caller), not on the document type — so a single small set of methods
covers every domain:

- `AbstractString` — write the spliced string back through the field.
- `Nothing`        — a cleared text field; splice against the empty string.
- `Number`         — splice the textual form and reparse (editing a number's text
                     means "reparse it"; see [`splice_number`](@ref)).

A domain whose field holds a richer text representation (a styled span, or a
sequence of spans) adds its own method here; those methods live in the module
that owns those types. A later unification of all replace-part operations around
a reference will add a sequence/`CellVector` method here for structural element
edits.
"""
function splice_value! end

splice_value!(owner, field::Symbol, value::AbstractString, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_string(value, s, e, replacement))

splice_value!(owner, field::Symbol, ::Nothing, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_string("", s, e, replacement))

splice_value!(owner, field::Symbol, value::Number, s::Int, e::Int, replacement::AbstractString) =
    setproperty!(owner, field, splice_number(string(value), s, e, replacement))

struct QuitEditorException <: Exception end

"""
    CompoundOperation(operations)

Apply a sequence of operations in order, as a single editor step. The Julia
counterpart of Lisp's `make-operation/compound`: a reader returns one
`CompoundOperation` and `evaluate_operation` runs each member operation against
the same editor in turn — for an intent that is naturally several writes at once
(e.g. a cut that both saves the selected value and clears the slot it came from).
"""
struct CompoundOperation <: Operation
    operations::Vector{Any}
end

CompoundOperation(operations...) = CompoundOperation(Vector{Any}(collect(operations)))

function evaluate_operation(editor, op::CompoundOperation)
    for member in op.operations
        evaluate_operation(editor, member)
    end
end

"""
    QuitEditorOperation()

Operation that signals the editor to stop, by throwing `QuitEditorException`
(which the editor loop catches to exit).
"""
struct QuitEditorOperation <: Operation end

function evaluate_operation(editor, op::QuitEditorOperation)
    throw(QuitEditorException())
end

"""
    AdjustZoomOperation(delta)

Editor-global *uniform* readability zoom: `delta` is +1 (in), -1 (out) or 0
(reset). Magnifies the whole editor. The concrete behaviour — rescaling the
display factor, reflowing and repainting — lives in a rendering backend's
`evaluate_operation`; the generic no-op fallback above keeps it harmless under
backends that do not implement it.
"""
struct AdjustZoomOperation <: Operation
    delta::Int
end

"""
    AdjustFontZoomOperation(delta)

Editor-global *font-only* readability zoom, like [`AdjustZoomOperation`](@ref)
but scaling only text, so fixed graphics and spacing keep their size. Behaviour
also lives in a rendering backend.
"""
struct AdjustFontZoomOperation <: Operation
    delta::Int
end

"""
    ReplaceSelectionOperation(path)

Operation that replaces the current selection with `path`. Produced by the reader
side of the projection pipeline and applied by `evaluate_operation`.

Click-versus-keyboard disambiguation does **not** ride on this operation. A
projection that wants a glyph to behave differently on click than under keyboard
navigation keys that off the originating gesture (`change.gesture isa MousePress`),
which travels the reader chain in the `Intent`, rather than off a flag on this
operation.
"""
struct ReplaceSelectionOperation <: Operation
    path::ReferencePath
end

function evaluate_operation(editor, op::ReplaceSelectionOperation)
    replace_selection!(editor.document, op.path)
end

# Split a non-empty path into (everything-but-last-step, last-step). The prefix is
# rebuilt as a plain skeleton (callers pass an already type-stripped path).
function _split_terminal_step(path::ConcreteReferencePath)
    steps = reference_steps(path)
    (ReferencePath(steps[1:end-1]...), steps[end])
end

# Write `value` into the slot `step` selects on `parent`. A FieldReference names a
# `Cell`-backed field (e.g. `JsonObjectEntry.value`, or a widget's `visible`); a
# RangeReference selects an element of a sequence container (`CellVector`) and
# overwrites it. Shared by `ReplaceReferencedValueOperation` (single-slot writes of either a
# document or a scalar) — terminal-kind dispatch is what unifies the two.
function _write_slot!(parent, step::FieldReference, value)
    f = getfield(parent, Symbol(step.name))
    f isa AbstractCell || error("ReplaceReferencedValueOperation: field $(step.name) of $(typeof(parent)) is not a Cell")
    f[] = value
end

function _write_slot!(parent, step::RangeReference, value)
    parent[step.start + 1] = value
end

# A terminal `RangeReference` whose value is a *vector* of items is a SPLICE:
# replace the half-open element range `[start, stop)` of the sequence container
# with `items` (each wrapped in a `Cell`). Zero-width range ⇒ pure insert; empty
# items ⇒ pure delete; both ⇒ element replacement. This is the folded form of the
# former `CollectionInsertOperation` / `CollectionDeleteOperation` (see
# `insert_elements` / `delete_elements`); a single (non-vector) value still hits the
# element-overwrite method above (the `replace_document` array-element case).
function _write_slot!(parent, step::RangeReference, items::AbstractVector)
    for _ in 1:(step.stop - step.start)
        deleteat!(parent, step.start + 1)
    end
    for (k, item) in enumerate(items)
        insert!(parent, step.start + k, item isa AbstractCell ? item : Cell(item))
    end
end

"""
    ReplaceReferencedValueOperation(document, reference, value)

Set the scalar `value` at `reference` (a `ReferencePath`) resolved against a
root selected by the `document` field:

- **`document !== nothing`** — the root is the carried object, so this works on
  objects that do not live in the document tree (a widget, or a projection's own
  reactive parameter `Cell`s — the controls produced by `ObjectToWidget` edit
  these). The operation is *self-contained* and bubbles up the reader chain
  unchanged.
- **`document === nothing`** — the root is `editor.document` and `reference` is
  rooted there, so container/generic projections reroot the reference as the
  operation flows up (see `reroot_operation` in the sibling `Rerooting.jl` and the default
  `read_intent`). An empty `reference` then means a **whole-root swap** (rebind
  `editor.document`, drop the cached iomap), mirroring `ReplaceDocumentOperation`'s
  empty-path branch.

It is `ReplaceDocumentOperation` generalised: an explicit-or-implicit root + a
reference + a plain value, reusing the same terminal-slot-write split. (Folding
`ReplaceDocumentOperation` and the Group 2–4 single-slot writes into this is the
subject of `plan/done/consolidate-operations-replace.md`.)
"""
struct ReplaceReferencedValueOperation <: Operation
    document::Any
    reference::ReferencePath
    value::Any
end

# Convenience for the common single-field write on a carried root:
# `ReplaceReferencedValueOperation(obj, "field", v)` writes `obj.field = v`. Dispatches by
# the second argument's type (`AbstractString` vs `ReferencePath`), so it never
# collides with the field-by-field constructor above.
ReplaceReferencedValueOperation(document, field::AbstractString, value) =
    ReplaceReferencedValueOperation(document,
        ConcreteReferencePath(FieldReference(field), EmptyReferencePath()), value)

function evaluate_operation(editor, op::ReplaceReferencedValueOperation)
    reference = strip_reference_types(op.reference)
    # `document === nothing` ⇒ the reference is rooted at `editor.document`
    # (where the former `ReplaceDocumentOperation` rooted its path); otherwise the
    # operation carries its own root object (a widget, a projection parameter `Cell`).
    root = op.document === nothing ? editor.document : op.document
    if reference isa EmptyReferencePath
        # Whole-root swap: only meaningful when the root *is* `editor.document`
        # (there is no in-place "replace the object itself" for a carried root).
        # Rebind and ask the editor to drop its cached projection so the next print
        # rebuilds on the new root — a wholesale swap is not reactive (nested swaps
        # write into Cells). `invalidate_projection!` is the editor's own concern
        # (default no-op); this module does not know how the projection is cached.
        op.document === nothing ||
            error("ReplaceReferencedValueOperation: empty reference on a carried root has no slot to write")
        editor.document = op.value
        invalidate_projection!(editor)
        return
    end
    parent_path, terminal = _split_terminal_step(reference)
    parent = parent_path isa EmptyReferencePath ? root :
             evaluate_reference(root, parent_path)
    _write_slot!(parent, terminal, op.value)
end

"""
    replace_document(path, document) -> CompoundOperation

Replace the document at `path` (rooted at `editor.document`) with `document`, then
move the editor selection to `path ⧺ document.selection` so the cursor lands inside
the freshly-created value. The structural analogue of the primitive replace-range
edits — every JSON/XML type-to-replace gesture (`[` → array, `{` → object, …) and
the clipboard cut/paste produce one.

This is the folded form of the former `ReplaceDocumentOperation`: a
`ReplaceReferencedValueOperation(nothing, path, document)` write paired with a trailing
`ReplaceSelectionOperation`, bundled in a `CompoundOperation` so re-rooting prepends
the same steps to both as the operation bubbles up. An empty `path` is a whole-root
swap (the `ReplaceReferencedValueOperation` rebinds `editor.document` and drops the iomap).
"""
function replace_document(path::ReferencePath, document)
    inner_sel = getfield(document, :selection)[]
    inner_sel === nothing && (inner_sel = EmptyReferencePath())
    CompoundOperation(Any[
        ReplaceReferencedValueOperation(nothing, path, document),
        ReplaceSelectionOperation(concat_references(strip_reference_types(path), inner_sel)),
    ])
end

"""
    insert_elements(path, index, items[, selection]; root=nothing) -> operation

Insert each of `items` into the sequence container at `path` (a `CellVector` such
as a JSON array's `.elements`), at the 0-based `index`. Expressed as a splice — a
`ReplaceReferencedValueOperation` whose terminal step is a **zero-width** `RangeReference(index, index)`
and whose value is the item vector. When `selection` is non-`nothing`, a trailing
`ReplaceSelectionOperation` is appended in a `CompoundOperation` to drop the cursor
into the new element (re-rooting prepends the same steps to both members).

`root` defaults to `nothing` (rooted at `editor.document`); pass a carried object
for an identity-rooted splice against a document that is not in the tree.
"""
function insert_elements(path::ReferencePath, index::Integer, items, selection=nothing; root=nothing)
    write = ReplaceReferencedValueOperation(root, append_reference(path, RangeReference(index, index)),
                                   Vector{Any}(items))
    selection === nothing ? write :
        CompoundOperation(Any[write, ReplaceSelectionOperation(selection)])
end

"""
    delete_elements(path, index[, count]; root=nothing) -> operation

Remove `count` (default 1) elements from the sequence container at `path`, starting
at the 0-based `index`. Expressed as a splice — a `ReplaceReferencedValueOperation` whose
terminal step is `RangeReference(index, index+count)` and whose value is the empty
vector (replace the range with nothing). The inverse of `insert_elements`.
"""
delete_elements(path::ReferencePath, index::Integer, count::Integer=1; root=nothing) =
    ReplaceReferencedValueOperation(root, append_reference(path, RangeReference(index, index + count)), Any[])

# ─────────────────────────────────────────────────────────────────────────
# SelectNextInsertionOperation — move the cursor to the next "hole"
#
# An editor-global navigation step: walk `editor.document` in pre-order and move
# the selection to the first Document satisfying `predicate` (a "hole", e.g. an
# insertion placeholder) that comes *after* the currently-selected node, placing
# the cursor at `<hole> ⧺ cursor` (the hole's own char cursor, e.g. `value{0}`).
# It carries no reference of its own, so it bubbles up the reader chain unchanged
# (the pass-through arms in the default `read_intent` and the else-branch of
# `reroot_operation`). A domain gesture supplies the predicate/cursor, so the
# kernel stays domain-agnostic — e.g. a "jump to next hole" key builds
# `SelectNextInsertionOperation(d -> d isa SomeInsertion, @reference value{0})`.
"""
    SelectNextInsertionOperation(predicate[, cursor])

Move the selection to the next hole (a Document for which `predicate` holds) after
the currently-selected node, in document pre-order, and place the cursor at that
hole's `cursor` suffix (default whole-element). Clamps at the last hole.
"""
struct SelectNextInsertionOperation <: Operation
    predicate::Any        # (node::Document) -> Bool ; true marks a hole to land on
    cursor::ReferencePath # suffix appended to the found hole's path (e.g. value{0})
end

SelectNextInsertionOperation(predicate) =
    SelectNextInsertionOperation(predicate, EmptyReferencePath())

function evaluate_operation(editor, op::SelectNextInsertionOperation)
    root = editor.document
    root isa Document || return
    nodes = Tuple{ReferencePath,Any}[]
    _preorder_documents!(root, EmptyReferencePath(), Base.IdSet{Any}(), nodes)
    owner = _selection_owner_node(root, getfield(root, :selection)[])
    cur = 0
    if owner !== nothing
        for (i, (_, nd)) in enumerate(nodes)
            nd === owner && (cur = i; break)
        end
    end
    for j in (cur + 1):length(nodes)
        if op.predicate(nodes[j][2])
            set_selection!(root, concat_references(nodes[j][1], op.cursor))
            return
        end
    end
    return
end

# `child_reference_steps(node)` — open traversal seam. Returns an
# iterable of `(step, child)` pairs naming each direct child of `node`
# reachable by a single reference step. The default walks `fieldnames`
# (FieldReference per field, skipping `selection`); base's Collection.jl
# adds the `CellVector` method that yields RangeReference(i-1, i) per
# element. New container documents override this to name their children.
"""
    child_reference_steps(node) -> iterable of (step, child) pairs

Open traversal seam. The default enumerates struct fields as
`FieldReference` steps, skipping `selection` and any field whose (unwrapped)
value is not a `Document`. Override for container documents whose children
are addressed by index (`CellVector`), by position, etc.
"""
function child_reference_steps end

function child_reference_steps(node)
    pairs = Tuple{Any, Any}[]
    for nm in fieldnames(typeof(node))
        nm === :selection && continue
        val = unwrap_cell(getfield(node, nm))
        val isa Document || continue
        push!(pairs, (FieldReference(string(nm)), val))
    end
    pairs
end

# Pre-order Document walk building set_selection!-compatible paths. Skips
# `selection` and guards cycles/shared substructure by identity.
function _preorder_documents!(node, path::ReferencePath, seen, out)
    node isa Document || return
    node in seen && return
    push!(seen, node)
    push!(out, (path, node))
    for (step, child) in child_reference_steps(node)
        _preorder_documents!(child, append_reference(path, step), seen, out)
    end
    return
end

# The deepest Document a selection anchors at: strip type checkpoints, then drop
# trailing steps until the path resolves to a Document (a `value{k}` char cursor
# resolves to a String, so it is dropped to reach the owning leaf). Empty ⇒ root.
function _selection_owner_node(root, sel)
    sel === nothing && return nothing
    p = strip_reference_types(sel)
    while true
        v = try_evaluate_reference(root, p)
        v isa Document && return v
        p isa EmptyReferencePath && return root
        (p, _) = _split_terminal_step(p)
    end
end

"""
    ToggleCollapseOperation([target])

Operation that flips the `collapsed` field of a single collapsible node.

`target` is the node whose `collapsed` cell should be toggled, or `nothing`.
A `nothing` target is resolved by whichever projection owns the collapse state to
the **innermost** collapsible node containing the current selection, before the
operation propagates back up — so `evaluate_operation` only ever sees a concrete
`target` (a click that already knows the node it hit supplies one directly).

The operation only affects *rendering*: the source document is untouched, so a
selection that pointed inside the just-collapsed subtree simply stops drawing a
cursor until the node is expanded again.
"""
struct ToggleCollapseOperation <: Operation
    target::Any
end

ToggleCollapseOperation() = ToggleCollapseOperation(nothing)

function evaluate_operation(editor, op::ToggleCollapseOperation)
    target = op.target
    target === nothing && return
    target.collapsed = !target.collapsed
end

# The window operations (`OpenWindowOperation`, `OpenPopupOperation`,
# `CloseWindowOperation`, `ResizeWindowOperation`) are the screen domain's
# vocabulary and live with `WindowDocument` in `ScreenDocumentModule`
# (`document/ScreenDocument.jl`), not here.

