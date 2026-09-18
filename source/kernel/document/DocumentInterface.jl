# Fragment of `DocumentModule` — the document **contract**: the `Document`
# abstract type every document subtypes, and the open generics of its shared
# value protocol and reflection walk. Nothing here carries a body — the trait
# defaults live in `DocumentDefaults.jl`, deep copy in `DocumentCopy.jl`, the
# record shadow-sync in `DocumentSync.jl`, the reflection walk and value-search
# in `DocumentWalk.jl` / `DocumentSearch.jl`, and the `@document` codegen that
# declares most concrete documents in `DocumentMacro.jl`.

"""
    Document

What the editor edits: data with a shape, which a projection can show and a
person can change.

Use it as the type of anything that is content rather than presentation: a
table of results, a chart, a page of a study, a pane tree, a line of text. A
document holds its fields in cells, so a change to one part redraws that part;
it carries its own selection; and a projection turns it into another document,
which is how it reaches a screen.

# Example

    @document struct Note <: Document
        title::String = ""
        body::String = ""
    end

See also `@document`, which declares most of them, `Projection`, which shows
one, and the guide `design/concepts`.

Abstract base type for all document types. Most concrete documents are
declared with the [`@document`](@ref) macro (in the sibling
[`DocumentMacro.jl`](DocumentMacro.jl) fragment), which wraps fields in
reactive `Cell`s and generates the shared value protocol; a hand-written struct
may also subtype `Document` directly.
"""
abstract type Document end

"""
    is_element_collection(document) -> Bool

`true` when a document's children are addressed **by position** (an
`ElementReferenceStep`, i.e. `[i]`) rather than by named field — a 1-D positional
sequence, not a record. A reflection walk keys off this to emit `[i]` element
paths for a collection instead of descending into its internal storage fields,
so it never has to name a concrete collection type. Defaults to `false`
(records, leaves, and 2-D collections all answer `false`); a 1-D positional
collection opts in with its own method.
"""
function is_element_collection end

"""
    get_document_family(x) -> Type
    get_document_family(::Type) -> Type

The **family** a document belongs to: the identity used to decide whether two
documents are the same document — including when they are two different *variant
layouts* of one `@document` schema (the isbits/immutable stem and the native
`mutable struct`, which do not share a type wrapper). Defaults to the type's name
wrapper (`Base.typename(T).wrapper`), so a plain type is its own family; the
`@document` macro overrides it to the schema's **abstract family type**, so every
variant of one schema answers the same family.
"""
function get_document_family end

"""
    get_document_cell_type(x) -> Type
    get_document_cell_type(::Type) -> Type

The **cell layout** of a schema: the parametric struct whose fields hold cells.
Together with [`get_document_native_type`](@ref) this is the layout registry — the way
to ask for a layout without naming a type. Before it existed the only way to reach
a layout was to write its name, which is why a caller that wanted the plain struct
had to spell `MFoo`.

Takes any variant, because every variant of a schema subtypes its family. Defaults
to the type's own name wrapper, so a hand-written document is its own cell layout
and a copy of one rebuilds exactly what it was.
"""
function get_document_cell_type end

"""
    get_document_native_type(x) -> Type | Nothing
    get_document_native_type(::Type) -> Type | Nothing

The **native layout** of a schema: the plain struct whose fields hold the declared
value types with no cell around them. The companion of
[`get_document_cell_type`](@ref).

Returns `nothing` when a schema has no native layout, which is the default and is
what every hand-written document answers. A caller that builds a layout must
handle `nothing` rather than assume the pair is always complete.
"""
function get_document_native_type end

"""
    get_document_schema_name(x) -> Symbol
    get_document_schema_name(::Type) -> Symbol

The **schema's** own name — what the programmer wrote after `struct`. Every
variant of one schema answers it, so it is the name to show a reader.

`nameof` cannot do this job. A coded name is a type's real name and the bare name
is a `const` alias, so `nameof` of a schema that bound its bare name elsewhere
answers the coded one: `nameof(ChainModel)` is `:MChainModel`. A label built that
way reads as the layout rather than the thing.

Defaults to `nameof(T)`, which is right for a hand-written document and for any
schema that left its bare name where it was.
"""
function get_document_schema_name end

"""
    get_document_title(document) -> String or nothing

The name a document carries for itself, or `nothing` when it carries none.

**A title is not a description.** A document's description says what it *is*
right now — "18 runs, running: 12 done, 6 running" — and that sentence changes
as the document does. A title is what the thing is called, and it holds still.
A pane needs the second: a tab that renamed itself as its runs finished would
be a tab nobody could point at.

The default answers `nothing`, so a document that has no name of its own falls
back to its description. **Each slice writes the method for its own documents**,
beside them.

The argument is untyped in the default on purpose: an application writes a method
for its own type, and a default of the same signature would be overwritten rather
than added to.
"""
function get_document_title end

"""
    is_walk_opaque(document) -> Bool

`true` when a document is **opaque** to the reflection walk: its internals are
implementation detail, not addressable document content, so the walk treats it as
a leaf and never descends into it. Defaults to `false`; a document whose
contents are configuration or an implementation detail rather than navigable
structure opts in with its own method.
"""
function is_walk_opaque end

"""
    is_collection_field_type(::Val{name}) -> Bool

`true` when a `@document` field declared with type `name` should receive the
collection-construction sugar — a positional constructor that wraps a raw
`AbstractVector` into that type (`Foo([a, b])` / `Foo(a, b)`). The expansion-time
companion of `is_element_collection`, keyed on the declared type's **symbol** so
the `@document` macro can ask without resolving — or even naming — the type: a
collection type registers `Val{:ItsName}` from the package that defines it (and
must offer a `Type(::AbstractVector)` constructor), so the document layer names no
concrete collection type. Defaults to `false`.
"""
function is_collection_field_type end

"""
    get_cell_layout_field_type(::Val{name}) -> Type | Nothing

The type a `@document` field declared with type `name` takes in the **cell**
layout, when the reactive representation of a value differs from the plain one.
`nothing`, the default, means the declared type is used unchanged.

**This is what lets a declaration state the PLAIN type.** A field written
`params::Vector{NedParam}` is exactly that in the native layout — no cells — while
the cell layout substitutes the reactive collection, so an editor still gets one
cell per element. Before it, a declaration had to name `CellVector` to get the
editor what it needs, and the plain layout then carried cells it had no use for.

Keyed on the declared type's **symbol**, the same way `is_collection_field_type`
is, so the `@document` macro asks without resolving or naming the type: the
reactive collection registers `Val{:Vector}` from the package that defines it, and
the document layer names no concrete collection type. The registered type must
offer a `Type(::AbstractVector)` constructor, since that is how a raw value
becomes one.
"""
function get_cell_layout_field_type end

"""
    copy_document(value)          -> value      # preserve every cell's kind
    copy_document(policy, value)  -> value      # preserve every cell's kind, as `policy` says
    copy_document(K, value)       -> value      # rebuild every cell as kind K

Deep-copy a document subtree, allocating fresh `Cell`s and containers so the
result shares no cell with the source. A value that is not a document, a vector
or a cell is shared, and a policy can share a document it does not descend
into. The one-argument form preserves each cell's kind; the form with a cell
type `K` rebuilds every cell as kind `K` (`ReactiveCell` / `MutableCell` /
`ImmutableCell`). Plain immutable leaves
(strings, numbers, symbols) pass through unchanged.

The form with a [`CopyPolicy`](@ref) is the walk that preserves the kind, steered.
`copy_document(value)` is that walk under [`PlainCopyPolicy`](@ref). A policy
steers it in two ways:

- **A method on the pair.** `copy_document(::MyPolicy, ::MyDocument)` replaces
  one step of the walk and keeps the others, because dispatch selects the most
  specific method. Such a method can rebuild the node with
  [`copy_document_fields`](@ref).
- **The stop hooks.** At each child document the walk asks
  [`is_descendable_for_copy`](@ref), and where it stops,
  [`make_copy_placeholder`](@ref) gives what stands there.
  [`copy_computed_cell`](@ref) copies a cell that computes,
  [`copy_selection_cell`](@ref) copies a document's selection, and
  [`get_copy_memo`](@ref) gives the table that makes a document met twice one
  copy.

A hook refuses the whole copy with a [`DocumentCopyException`](@ref).

The policy comes first, and a cell type never is a policy, so no method of one
form is ambiguous with a method of the other.
"""
function copy_document end

"""
    CopyPolicy

The supertype of what steers [`copy_document`](@ref). A concrete policy is made
for one copy and can carry the state of that copy, such as the memo of
[`get_copy_memo`](@ref).
"""
abstract type CopyPolicy end

"""
    copy_document_fields(policy, document; replacements...) -> Document

Rebuild `document` with each field copied through `copy_document(policy, …)`.
A field named in `replacements` takes the value given instead: a value for a
field that holds a cell is put in a new cell of the same kind, and a cell is
used as it is.

This is the step the walk takes at a document it descends into, and the step a
method for one kind calls when that kind needs one field made by hand.

With a memo, a document that the rebuild meets again inside its own copy stops
the copy with a [`DocumentCopyException`](@ref), and a document it already
copied answers the same copy.
"""
function copy_document_fields end

"""
    is_descendable_for_copy(policy, document) -> Bool
    make_copy_placeholder(policy, document) -> value

The **stop control** of [`copy_document`](@ref) under a policy. The walk asks the
first at each child document, and where the answer is `false` the slot takes
what the second gives: a marker, or `document` itself, which the copy then
shares with the source.

Unlike [`is_descendable_for_sync`](@ref), the question receives the child, so a
policy can stop at a kind. The defaults descend everywhere, and the second
raises an error, because a policy that stops must say what stands there.
"""
function is_descendable_for_copy end
function make_copy_placeholder end

"""
    copy_computed_cell(policy, cell) -> AbstractCell

The copy of a cell that computes. The default is a cell of the same kind that
stores the value the cell has now, so the copy no longer follows what the
thunk reads. A policy that can not accept that throws a
[`DocumentCopyException`](@ref).
"""
function copy_computed_cell end

"""
    copy_selection_cell(policy, cell) -> AbstractCell

The copy of a document's `selection` cell. A selection is view state, and a
projection can wire it to a computation that follows the selection of the
document it prints. So the default is a cell of the same kind that stores the
selection the cell has now, whether it computes or not, and the copy's own
projection wires its own. A policy never refuses a document for its selection.
"""
function copy_selection_cell end

"""
    has_document_duplicate(document) -> Bool
    make_document_duplicate(document) -> Document

A **duplicate** is the copy a person gets when they duplicate a pane: a new
document of the same kind that they control on its own. It owns what the person
controls in it, shares what it reads, and copies no process.

`has_document_duplicate` says whether the kind of `document` has one. A strip
asks it each time it prints a tab, so a method answers from the type and never
walks the tree. The default is `false`.

`make_document_duplicate` makes the duplicate with
`copy_document(DuplicatePolicy(), document)`. It throws a
[`DocumentCopyException`](@ref) when the kind declares no duplicate, or when the
tree holds something the duplicate can not own.

A kind declares its duplicate with `has_document_duplicate(::Kind) = true`, and
the walk copies its fields. A kind that needs one field made by hand also adds
`copy_document(::DuplicatePolicy, ::Kind)`, which can call
[`copy_document_fields`](@ref).
"""
function has_document_duplicate end
function make_document_duplicate end

"""
    get_copy_memo(policy) -> IdDict | Nothing

The table in which [`copy_document_fields`](@ref) records each document it
copies, keyed by the source. `nothing`, the default, records nothing: a document
met twice is copied twice, and a document that holds itself makes the walk
endless.
"""
function get_copy_memo end

"""
    sync_document!(shadow, source) -> shadow

Update the writable `shadow` document to match `source`, writing a shadow cell
**only when its value changed** — so the downstream reactive graph sees a
*minimal* invalidation set, not a wholesale rebuild. `shadow` may be any
writable kind (`ReactiveCell` or `MutableCell`); `source` may be any kind.

Both shapes are handled: a **record** (children are named fields) syncs
field-by-field, and a **positional collection** (`is_element_collection`) syncs
its elements by index through the vector protocol.

The shadow must be a **cell layout**, and the source may be either layout. A
native tree holds no cells, so nothing in it can invalidate a reader and it is
not a shadow. Syncing into one raises an error the moment a child has to be
built. `source` may be a native document: a rebuilt child converts to the
shadow's layout, which is what [`copy_document`](@ref) does for a kind.
"""
function sync_document! end

"""
    is_descendable_for_sync(policy, depth, slot) -> Bool
    sync_element_limit(policy, source, shadow) -> Int
    make_unsynced_placeholder(policy, source, current) -> value

The **bound** on a sync or a copy. `sync_document!`/`copy_document` consult these
at every child; the default policy (`nothing`) answers "descend", "take them all"
and never reaches the third, so an un-policed walk is the whole walk.

A policy that answers otherwise makes the walk stop, and
`make_unsynced_placeholder` supplies what stands where it stopped — a marker the
policy's owner understands. That keeps the marker's *type* out of this layer:
the walk knows only that something goes in the slot.

`depth` is the child's depth (1 for a root's children). `slot` is what occupies
it now — including a placeholder the policy itself put there, which is how a
policy recognises "already stopped here" and how a consumer's request to go
deeper reaches the walk. `make_unsynced_placeholder` likewise receives `current` so a
policy can hand back the placeholder already standing there rather than a fresh
one, leaving the shadow's identity alone.

`sync_element_limit` is given the whole source and shadow rather than counts,
because how many elements to keep depends on what the shadow already holds —
including whether its trailing placeholder was flagged — and that is the
policy's own bookkeeping, not this layer's.

Unbounded defaults in `DocumentDefaults.jl`.
"""
function is_descendable_for_sync end
function sync_element_limit end
function make_unsynced_placeholder end

"""
    get_wrapped_document(node)

The document that `node` stands for.

Use it where code needs the document itself and may have been handed a
transparent wrapper around it: a history, a version list, a clipboard slice. The
default answers `node`, so a caller that names this asks a question every
document can answer, and a wrapper adds one method.

A wrapper is transparent on the screen — its projection prints what it holds and
answers that output — but it is a real node in the tree, so anything that reads
the tree rather than the picture meets it. Saving a file is the case this exists
for: the file holds the document, not the history of it.

# Example

    write_document_file(get_wrapped_document(tab.content), tab.filename)

See also `copy_document` and `replace_wrapped_document!`.
"""
function get_wrapped_document end

"""
    replace_wrapped_document!(node, document) -> node

Put `document` where `node` stood, and answer what belongs there now.

Use it where a document is replaced rather than edited — a file re-read from
disk. The default answers `document`, so the caller stores that in place of
`node` and the wrapper, if there was one, is gone. A wrapper that must survive
the replacement writes `document` into itself, deals with whatever state it kept
about the old one, and answers itself.

# Example

    tab.content = replace_wrapped_document!(tab.content, read_document_file(tab.filename))

See also `get_wrapped_document`.
"""
function replace_wrapped_document! end

"""
    search_documents(obj, predicate; include_selection=false, maxdepth=64, raw=false) -> Vector
    search_documents(obj, query::Union{AbstractString,Regex}; …)                      -> Vector

Walk any object and return the matching nodes, **each at most once** even when a
node is shared. A `String` (substring) or `Regex` matches leaf nodes by their
string form. By default the result is **document-scoped**: a scalar match folds
up to the nearest enclosing `Document`; pass `raw=true` to return the exact
matched value.
"""
function search_documents end
