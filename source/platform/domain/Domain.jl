# Fragment of `DomainModule`.
#
# What a document domain *is* — the concept the domain package's JSON, XML, SQL,
# Julia, … are instances of. Two halves:
#
# 1. **The `@domain` macro** — generates a document domain's whole kit from one
#    line: the abstract root (`JsonDocument`), the empty placeholder
#    (`JsonNothing`), the typed-name insertion buffer (`JsonInsertion`), the
#    Insert-key gesture that turns the placeholder into the insertion, and the
#    insertion *traits* that anchor everything below.
#
# 2. **Reflection-based completion** — the candidate list for an insertion is
#    *computed* from the document type tree (`get_insertion_candidates`, memoized on
#    the world counter so a newly defined `@document` type is completable the
#    moment its `struct` is evaluated), the accepted names are *derived* from the
#    type name (`get_insertion_names`: the capitalized type name `JsonString` and the
#    lowercase human-readable form `json string`; prefix-free inside a domain
#    scope), and construction goes through *dispatch* (`make_insertion_document`,
#    zero-arg fallback + per-type cursor/scaffold overrides written with
#    `@insertion`). Nothing is listed or registered.
#
# `complete_insertion` classifies a typed prefix (`:empty` / `:invalid` /
# `:unambiguous` / `:ambiguous`) and computes the completion continuation;
# `resolve_insertion` maps a typed name to the committable type (exact name or
# alias first, then an unambiguous prefix).
# `compute_loaded_subtypes`: `subtypes` WITHOUT InteractiveUtils.
#
# `InteractiveUtils` is the REPL's introspection stdlib — `@which`, `@edit`,
# `@code_native`, `versioninfo` — and its only dependency is `Markdown`. An
# import of it here puts `Markdown` in the closure of every program that reads a
# NED or INI file, because a downstream package that reads those files depends
# on this one. So the one function this package needs is adapted from
# `InteractiveUtils.subtypes` (Julia 1.13), and it uses nothing but Base.
#
# `_collect_named_types` and `_compute_subtypes` are adapted from Julia, under
# its MIT licence, whose notice follows:
#
#   Copyright (c) 2009-2025: Jeff Bezanson, Stefan Karpinski, Viral B. Shah, and
#   other contributors: https://github.com/JuliaLang/julia/contributors
#
#   Permission is hereby granted, free of charge, to any person obtaining a copy
#   of this software and associated documentation files (the "Software"), to
#   deal in the Software without restriction, including without limitation the
#   rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
#   sell copies of the Software, and to permit persons to whom the Software is
#   furnished to do so, subject to the following conditions:
#
#   The above copyright notice and this permission notice shall be included in
#   all copies or substantial portions of the Software.
#
#   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#   FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
#   IN THE SOFTWARE.
#
# The walk over the modules is apart from the selection of one type's subtypes,
# so that a search of a whole type tree, as `_collect_concrete!` makes, reads
# every name of every loaded module once. A walk for each abstract type would
# read every name 485 times under `Document`, and the first key in a name buffer
# would wait seconds for it.

# Every name bound in `m`, in `world` where Julia reads names by world.
@static if VERSION >= v"1.13"
    _collect_module_names(m::Module, world::UInt) = Base.unsorted_names(m; all = true, world)
else
    # Julia 1.12 reads the names of the newest world; `_collect_named_types` checks
    # each one in `world` with `isdefinedglobal`.
    _collect_module_names(m::Module, world::UInt) = Base.unsorted_names(m; all = true)
end

# Every type bound under its own name in its own module, among the loaded
# modules and their submodules, filed under the name of its direct supertype.
function _collect_named_types(world::UInt)
    named = Dict{Core.TypeName, Vector{Any}}()
    mods = Base.loaded_modules_array()
    while !isempty(mods)
        m = pop!(mods)
        for s in _collect_module_names(m, world)
            if !Base.isdeprecated(m, s) && Base.invoke_in_world(world, isdefinedglobal, m, s)
                t = Base.invoke_in_world(world, getglobal, m, s)
                dt = isa(t, UnionAll) ? Base.unwrap_unionall(t) : t
                if isa(dt, DataType)
                    if dt.name.name === s && dt.name.module == m
                        push!(get!(Vector{Any}, named, supertype(dt).name), t)
                    end
                elseif isa(t, Module) && nameof(t) === s && parentmodule(t) === m && t !== m
                    t === Base || push!(mods, t)   # Base is parented by Main too
                end
            end
        end
    end
    named
end

# The direct subtypes of `x` in a table of `_collect_named_types`, sorted by name.
function _compute_subtypes(named::Dict{Core.TypeName, Vector{Any}}, @nospecialize(x::Type))
    xt = Base.unwrap_unionall(x)
    if !isabstracttype(x) || !isa(xt, DataType)
        return Type[]
    end
    sts = Vector{Any}()
    for t in get(named, xt.name, ())
        ti = typeintersect(t, x)
        ti != Union{} && push!(sts, ti)
    end
    return permute!(sts, sortperm(map(string, sts)))
end

"""
    compute_loaded_subtypes(T::Type; world) -> Vector{Type}

The direct subtypes of `T` among the loaded modules, sorted by name: what
`InteractiveUtils.subtypes` answers, with no `InteractiveUtils`. It walks every
name of every loaded module, so a caller that searches a whole type tree uses
one walk for all of it.
"""
compute_loaded_subtypes(x::Type; world::UInt = Base.get_world_counter()) =
    _compute_subtypes(_collect_named_types(world), x)


# ── Traits ────────────────────────────────────────────────────────────────────
#
# The dispatch anchors `@domain` emits (and `DocumentNothing`/`DocumentInsertion`
# implement by hand below). They replace every string-naming convention: the
# completion machinery never inspects a type name to decide *behaviour*, only to
# derive display names.

"""
    get_insertion_root(::Type{<:Document}) -> Type

The abstract root whose subtypes an insertion buffer completes over —
`JsonDocument` for `JsonInsertion`, `Document` for the domain-independent
`DocumentInsertion` (the default).
"""
get_insertion_root(::Type) = Document

"""
    get_nothing_document(::Type{<:Document}) -> Type

The placeholder document an insertion aborts back to on Escape. Defaults to
`DocumentNothing`; `@domain` points each domain's insertion at its own
`*Nothing`.
"""
get_nothing_document(::Type) = DocumentNothing

"""
    get_insertion_document(::Type{<:Document}) -> Type

The insertion a `*Nothing` placeholder turns into on the Insert key. Defaults
to `DocumentInsertion`.
"""
get_insertion_document(::Type) = DocumentInsertion

"""
    get_domain_insertion(::Type) -> Type | Nothing

The insertion type belonging to an abstract domain root (`JsonDocument` →
`JsonInsertion`), or `nothing` when the root has none. Used to exclude the
scope's own insertion from its candidate list.
"""
get_domain_insertion(::Type) = nothing

"""
    get_domain_prefix(root::Type) -> String

The type-name prefix stripped for prefix-free matching inside a domain scope
(`JsonDocument` → `"Json"`, so `JsonString` also answers to `String` /
`string`). Empty for the universal root `Document`. The default derives it
from the root's name by dropping a trailing `"Document"`.
"""
function get_domain_prefix(root::Type)
    root === Document && return ""
    n = String(nameof(root))
    endswith(n, "Document") ? n[1:end-length("Document")] : n
end

"""
    get_insertion_aliases(::Type) -> Vector{String}

Extra short names a candidate answers to besides its derived names (`"julia"`
for `JuliaInsertion`). `@domain` emits the lowercase domain name as its
insertion's alias; anything else is a hand-written method.
"""
get_insertion_aliases(::Type) = String[]

# ── Text at the write of an operation ─────────────────────────────────────────

# Rule 3 of the seam `convert_to_declared_type`: text that an operation writes into
# a place that the text does not fit becomes the insertion of the domain of the
# document that owns the place, to be parsed later, when the declared type of the
# place admits that insertion. A document of no domain owns `DocumentInsertion`.
function DocumentModule.convert_to_declared_type(owner::Document, declared_type::Type,
                                                 value::AbstractString; name = nothing)
    value isa declared_type && return value
    insertion = something(get_domain_insertion(typeof(owner)), DocumentInsertion)
    insertion <: declared_type && return insertion(String(value))
    invoke(DocumentModule.convert_to_declared_type, Tuple{Any, Type, Any},
           owner, declared_type, value; name)
end

# ── Construction (dispatch, not factory tables) ───────────────────────────────

"""
    make_insertion_document(::Type{T}) -> Document

A fresh document committed for candidate `T`. The fallback is the zero-arg
constructor; per-type methods (write them with `@insertion`) add cursor
placement / scaffolds where the empty instance is not enough — an empty text
leaf, say, wants a caret at position 0 rather than a whole-node selection (see
`@selected`).
"""
make_insertion_document(::Type{T}) where {T} = T()

"""
    @insertion JsonString = @selected JsonString("") value{0}
    @insertion JuliaFunction = make_julia_scaffold("function")

The document a committed insertion of `JsonString` becomes: one
`make_insertion_document` method, emitted fully qualified, so a domain declares
its insertion factories without importing the generic it extends. The type
matches its subtypes too (`::Type{<:JsonString}`).
"""
macro insertion(ex)
    (ex isa Expr && ex.head === :(=) && length(ex.args) == 2) ||
        error("@insertion expects `T = expr`, e.g. `@insertion JsonBool = JsonBool(false)`, got `$ex`")
    T, body = ex.args
    M = @__MODULE__
    :($M.make_insertion_document(::Type{<:$(esc(T))}) = $(esc(body)))
end

const _MAKE_FALLBACK = which(make_insertion_document, Tuple{Type{Document}})

# `hasmethod(T, Tuple{})` cannot see *required keyword arguments* — a
# `@document` type with a non-defaulted field still has a zero-positional-arg
# keyword constructor that throws `UndefKeywordError` (`JsonString()`). So
# probe the constructor once; the probe only runs from the world-age-memoized
# candidate enumeration.
function _zero_arg_constructible(::Type{T}) where {T}
    hasmethod(T, Tuple{}) || return false
    try
        T()
        true
    catch
        false
    end
end

"""
    insertable(::Type{T}) -> Bool

Whether `T` belongs in a completion candidate list: it is zero-arg
constructible or has a specific `make_insertion_document` method. `@domain`
opts its `*Nothing` placeholders out; anything else opts out with a one-line
method.
"""
insertable(::Type{T}) where {T} =
    which(make_insertion_document, Tuple{Type{T}}) !== _MAKE_FALLBACK ||
    _zero_arg_constructible(T)

# ── Candidate enumeration (reflection, world-age memoized) ────────────────────

const _CANDIDATE_CACHE = Dict{Type, Tuple{UInt, Vector{Type}}}()

# Every concrete type under `root`, depth first, each level in the order of
# `subtypes`. `named` is the table of `_collect_named_types`, made once for the
# whole tree.
function _collect_concrete!(out::Vector{Type}, root::Type,
                            named::Dict{Core.TypeName, Vector{Any}})
    for T in _compute_subtypes(named, root)
        if isabstracttype(T)
            _collect_concrete!(out, T, named)
        else
            push!(out, T)
        end
    end
    out
end

const _CONCRETE_CACHE = Dict{Type, Tuple{UInt, Vector{Type}}}()

"""
    compute_concrete_subtypes(root::Type) -> Vector{Type}

Every concrete type under `root` in the loaded modules and their submodules,
depth first, each level in the order of its names. A type counts when it is
bound under its own name in its own module.

The walk reads every name of every loaded module, so the answer is memoized on
`Base.get_world_counter()`: a new type or method makes the next call walk again.
The answer is shared by every caller, so copy it before a change.
"""
function compute_concrete_subtypes(root::Type)
    world = Base.get_world_counter()
    cached = get(_CONCRETE_CACHE, root, nothing)
    cached !== nothing && cached[1] == world && return cached[2]
    result = _collect_concrete!(Type[], root, _collect_named_types(world))
    _CONCRETE_CACHE[root] = (world, result)
    result
end

# A type that *looks like* an insertion cursor (its name ends in "Insertion")
# is only a candidate when it really is a domain's entry point — its
# `get_insertion_root` names it back as that root's `get_domain_insertion`. This keeps
# the `@domain` insertions committable from the top level (they carry the
# traits) while stray per-slice cursors (`ClipboardInsertion`,
# `WidgetInsertion`, …) stay out of the list without per-type opt-outs.
function _is_domain_entry(T::Type)
    endswith(String(nameof(T)), "Insertion") || return true
    get_domain_insertion(get_insertion_root(T)) === T
end

# A native mutable-layout struct (`MFoo`) is the same document as its stem (`Foo`)
# — they share a `get_document_family` — just a different variant layout. Reflection
# over *document types* must see one type per schema, so we skip the concrete
# layout variants: a concrete type whose family is not its own name-wrapper is a
# variant of another schema, not a document type in its own right. (The stem is a
# UnionAll, so `isconcretetype` is false and it stays; a hand-written document is
# its own family via the fallback, so it stays too.)
_is_layout_variant(T::Type) =
    isconcretetype(T) && get_document_family(T) !== Base.typename(T).wrapper

"""
    get_insertion_candidates(root::Type) -> Vector{Type}

Every insertable concrete document type under `root`, computed by reflection
over the type tree — never listed or registered, so a newly defined
`@document` type appears automatically. Memoized on `Base.get_world_counter()`
(any new type/method definition invalidates the cache; otherwise it is one
dictionary lookup). The scope's own insertion (`get_domain_insertion(root)`) is
excluded — you are already in one — as are insertion cursors that are not
their domain's entry point.
"""
function get_insertion_candidates(root::Type)
    world = Base.get_world_counter()
    cached = get(_CANDIDATE_CACHE, root, nothing)
    cached !== nothing && cached[1] == world && return cached[2]
    own = get_domain_insertion(root)
    # `insertable` goes last: it probes the constructor and compiles a method for
    # each type, and a layout variant or a stray insertion cursor needs neither.
    result = filter(T -> T !== own && !_is_layout_variant(T) && _is_domain_entry(T) && insertable(T),
                    compute_concrete_subtypes(root))
    _CANDIDATE_CACHE[root] = (world, result)
    result
end

# ── Name derivation ───────────────────────────────────────────────────────────

# "JsonObjectEntry" -> "json object entry"
_camel_words(s::AbstractString) =
    lowercase(replace(s, r"(?<=[a-z0-9])(?=[A-Z])" => " "))

"""
    get_insertion_names(T; root = Document) -> Vector{String}

The names candidate `T` answers to, derived from its type name: the
capitalized type name (`"JsonString"`), the lowercase human-readable form
(`"json string"`), the same pair with the scope's `get_domain_prefix` stripped
(`"String"` / `"string"` when `root = JsonDocument`), plus any
`get_insertion_aliases`.
"""
function get_insertion_names(T::Type; root::Type = Document)
    base = String(nameof(T))
    names = String[base, _camel_words(base)]
    p = get_domain_prefix(root)
    if !isempty(p) && startswith(base, p) && length(base) > length(p)
        stripped = base[length(p)+1:end]
        push!(names, stripped, _camel_words(stripped))
    end
    append!(names, get_insertion_aliases(T))
    unique!(names)
end

# ── Completion semantics ──────────────────────────────────────────────────────

# Candidates (with their matching names) whose lowercase name starts with the
# lowercase typed text. No stripping: the typed buffer is matched verbatim, so
# a trailing space participates ("json " matches "json string" but not
# "JsonString").
function _matching(root::Type, typed::AbstractString)
    key = lowercase(typed)
    matches = Tuple{Type, Vector{String}}[]
    for T in get_insertion_candidates(root)
        ns = [n for n in get_insertion_names(T; root) if startswith(lowercase(n), key)]
        isempty(ns) || push!(matches, (T, ns))
    end
    matches
end

# The case-insensitive longest common prefix of `names` beyond the first `k`
# characters, rendered in the first name's own case. Names are derived from
# Julia identifiers (+ spaces), so plain byte indexing is safe.
function _common_continuation(names::Vector{String}, k::Int)
    stop = length(names[1])
    lead = lowercase(names[1])
    for n in names[2:end]
        ln = lowercase(n)
        m = min(stop, length(ln))
        i = 0
        while i < m && lead[i+1] == ln[i+1]
            i += 1
        end
        stop = i
    end
    stop <= k ? "" : names[1][k+1:stop]
end

"""
    complete_insertion(root, typed) -> (; state, continuation, matches)

Classify the typed buffer against `root`'s candidates:

- `:empty` — blank buffer; neutral.
- `:invalid` — no candidate name starts with `typed`; render the buffer red.
- `:unambiguous` — exactly one candidate matches; render the buffer green and
  `continuation` (the matching names' common remainder) as the pale hint.
- `:ambiguous` — several candidates match; render green without a hint.
  `continuation` still carries the matching names' longest common remainder,
  which Tab uses for partial completion.

`matches` is the candidate types (deduped — one candidate may match through
several of its names).
"""
function complete_insertion(root::Type, typed::AbstractString)
    isempty(strip(typed)) && return (state = :empty, continuation = "", matches = Type[])
    ms = _matching(root, typed)
    isempty(ms) && return (state = :invalid, continuation = "", matches = Type[])
    allnames = String[n for (_, ns) in ms for n in ns]
    continuation = _common_continuation(allnames, length(typed))
    (state = length(ms) == 1 ? :unambiguous : :ambiguous,
     continuation = continuation,
     matches = Type[T for (T, _) in ms])
end

"""
    name_completion(insertion) -> (; state, hint, extension)

The default completion policy for an insertion buffer: name completion over the
reflected candidates of the insertion's own domain.

- `state` — `:empty` / `:invalid` / `:ambiguous` / `:unambiguous`, which a
  projection paints the buffer with.
- `hint` — the pale continuation drawn after the typed text, and only when the
  prefix is unambiguous.
- `extension` — what Tab appends: the matching names' common remainder, which on
  an ambiguous prefix is the partial completion the hint does not show.

It is the reading of [`complete_insertion`](@ref) that a projection wants, and it
belongs beside it: nothing in it is about syntax, and a composer that draws its
own chooser needs it without needing a syntax tree.
"""
function name_completion(insertion)
    c = complete_insertion(get_insertion_root(typeof(insertion)),
                           something(insertion.value, ""))
    (state = c.state,
     hint = c.state === :unambiguous ? c.continuation : "",
     extension = c.continuation)
end

"""
    resolve_insertion(root, typed) -> Type | Nothing

The committable candidate for the typed buffer: an **exact** name/alias match
wins (so the alias `"julia"` commits `JuliaInsertion` even while it is also a
prefix of other names); otherwise the single candidate of an `:unambiguous`
prefix; otherwise `nothing`.
"""
function resolve_insertion(root::Type, typed::AbstractString)
    key = lowercase(strip(typed))
    isempty(key) && return nothing
    for T in get_insertion_candidates(root)
        any(lowercase(n) == key for n in get_insertion_names(T; root)) && return T
    end
    c = complete_insertion(root, typed)
    c.state === :unambiguous ? c.matches[1] : nothing
end

# ── Insert-key gesture (shared by @domain and DocumentNothing) ────────────────

# The char cursor at offset 0 of an insertion's `value` buffer.
const _INSERTION_CURSOR = ConcreteReference(FieldReferenceStep("value"),
    ConcreteReference(RangeReferenceStep(0, 0), EmptyReference()))

"""
    insert_document_operation(I::Type) -> Operation

The operation the Insert key emits on a `*Nothing` placeholder: replace it (∅,
rerooted by the enclosing projections) with a fresh insertion `I`, cursor
pre-placed at the start of its `value` buffer.
"""
insert_document_operation(::Type{I}) where {I} =
    make_replace_document_operation(EmptyReference(),
                                     set_selection!(I(), _INSERTION_CURSOR))

"""
    replace_selected_document(document, replacement) -> Operation

Replace the document the caret **names** with `replacement` — the type-to-replace
gesture every domain spells the same way (`n` for null, `[` for an array).

"Names" is the whole content of this verb: a caret on a projection-introduced token —
a bracket, a placeholder — names the node it was printed for, not a node of its own,
so it normalizes to ∅ (see [`normalize_named_node_reference`](@ref)). `replacement` carries its
own cursor, so nothing else needs placing.
"""
replace_selected_document(document, replacement) =
    make_replace_document_operation(
        normalize_named_node_reference(get_selection(document)), replacement)

"""
    append_insertion_operation(document, field::Symbol, T::Type) -> Operation

Append a fresh `T` to `document`'s `field` collection and leave the cursor where that
`T` says it goes.

The cursor is not a parameter because it is not a choice: `make_insertion_document(T)`
already carries the selection its `@insertion` factory declared — `XmlText` opens at
`content{0}`, `XmlAttribute` at `name{0}`, a bare placeholder like `JsonInsertion` at
no position at all, meaning "selected whole". Appending concatenates that embedded
selection onto the new element's path, so the eight hand-written appenders across
JSON / YAML / XML — each of which re-derived the very cursor its own insertion factory
had already declared — are one call.
"""
function append_insertion_operation(document, field::Symbol, ::Type{T}) where {T}
    inserted = make_insertion_document(T)
    n = length(getproperty(document, field))
    # Annotate the field path against the document (it exists); the new element cannot
    # be annotated that way — it is not in the document yet — so its terminal type
    # checkpoint comes from the insertion itself.
    field_path = annotate_reference_types(document,
        ConcreteReference(FieldReferenceStep(String(field)), EmptyReference()))
    element_path = concat_references(field_path,
        ConcreteReference(ElementReferenceStep(n + 1),
                              EmptyReference(get_reference_node_type(inserted))))
    inner = get_selection(inserted)
    cursor = inner === nothing ? element_path : concat_references(element_path, inner)
    make_insert_elements_operation(field_path, n + 1, Any[inserted]; selection = cursor)
end

"""
    move_to_field(document, selection; from, to) -> Operation | Nothing

Move the cursor from inside `document`'s `from` field to its sibling `to` field —
JSON/YAML's Tab (key → value) and XML's `=` (attribute name → value). `nothing` when
the caret is not in a `from` field.

Where in `to` the cursor lands is decided by what `to` *is*, not by an argument: a
child document is named whole (there is no text to be inside of), a primitive text
field takes a caret at its start. That is exactly the difference the three hand-written
versions encoded by hand — JSON and YAML landed on `.value` whole because it is a
`Document`, XML on `value{0}` because it is a `String`.
"""
move_to_field(document; from::Symbol, to::Symbol) =
    move_to_field(document, get_selection(document); from, to)

function move_to_field(document, selection; from::Symbol, to::Symbol)
    prefix = _prefix_before_field(selection, String(from))
    prefix === nothing && return nothing
    target = annotate_reference_types(document,
        concat_references(prefix, ConcreteReference(FieldReferenceStep(String(to)),
                                                        EmptyReference())))
    value = try_evaluate_reference(document, target)
    value === nothing && return nothing
    cursor = value isa Document ? target :
        annotate_reference_types(document, extend_reference(target, PositionReferenceStep(0)))
    ReplaceSelectionOperation(cursor)
end

# The path down to (but not including) the step naming `field` — the enclosing element,
# whose sibling field the caret is moving to. `nothing` if no such step is on the path,
# including when there is no caret at all.
_prefix_before_field(::Nothing, field) = nothing
_prefix_before_field(path::EmptyReference, field) = nothing
function _prefix_before_field(path::ConcreteReference, field)
    h = path.head
    h isa FieldReferenceStep && h.name == field && return EmptyReference(path.type)
    rest = _prefix_before_field(path.tail, field)
    rest === nothing && return nothing
    ConcreteReference(path.type, h, rest)
end

_insert_gesture_binding(::Type{I}, tag::String) where {I} =
    GestureBinding(KeyDownPattern(:insert),
                   (doc, event) -> insert_document_operation(I);
                   description = "Insert a new " * (isempty(tag) ? "" : tag * " ") * "document",
                   domain = isempty(tag) ? "document" : tag)

# ── The universal domain: DocumentNothing / DocumentInsertion ─────────────────
#
# Hand-written in DocumentCore (they carry custom label constants), but they
# implement the same traits, so the shared gestures and the reflection treat
# the domain-independent insertion identically.

get_insertion_root(::Type{<:DocumentInsertion}) = Document
get_nothing_document(::Type{<:DocumentInsertion}) = DocumentNothing
get_insertion_document(::Type{<:DocumentNothing}) = DocumentInsertion
get_domain_insertion(::Type{Document}) = DocumentInsertion
insertable(::Type{<:DocumentNothing}) = false
insertable(::Type{<:DocumentInsertion}) = false

get_document_gesture_bindings_own(::Type{DocumentNothing}) =
    GestureBinding[_insert_gesture_binding(DocumentInsertion, "")]

# ── @domain ───────────────────────────────────────────────────────────────────

"""
    @domain Json
    @domain Julia root = JuliaDocument nothing = JuliaNothing insertion = JuliaInsertion

Generate a document domain's insertion kit from its name:

- `abstract type JsonDocument <: Document end`, the domain's root — **exported**
  from the calling module, so a domain never re-exports its own root by hand
  (adopted roots are exported too),
- `@document struct JsonNothing <: JsonDocument` — the empty placeholder,
- `@document struct JsonInsertion <: JsonDocument` — the typed-name buffer
  (`value::String = ""`),
- the Insert-key gesture turning the placeholder into the insertion (cursor in
  the buffer),
- the traits wiring it all: `get_domain_prefix`, `get_domain_insertion`,
  `get_insertion_root`, `get_nothing_document`, `get_insertion_document`, the lowercase
  domain name as the insertion's alias, and the placeholder's `insertable`
  opt-out.

Each `root = X` / `nothing = X` / `insertion = X` option **adopts** an existing
type instead of generating one (only its traits and gestures are emitted); the
option's type must already be defined at the `@domain` call site. Escape from
an insertion is *not* generated per domain — the shared insertion gestures
abort to `get_nothing_document(typeof(ins))()` generically.

Candidates whose empty instance needs a cursor or a scaffold declare it with
the companion `@insertion` macro.

Not generated (layering): the domain's projection-table entries for the two
new types — add `XNothing`/`XInsertion` lines to the domain's `ToSyntax` table.
"""
macro domain(name, opts...)
    name isa Symbol ||
        error("@domain expects a domain name, e.g. `@domain Json`, got `$name`")
    prefix = String(name)
    root_sym      = Symbol(prefix, "Document")
    nothing_sym   = Symbol(prefix, "Nothing")
    insertion_sym = Symbol(prefix, "Insertion")
    gen_root = gen_nothing = gen_insertion = true
    for o in opts
        (o isa Expr && o.head === :(=) && o.args[1] isa Symbol && o.args[2] isa Symbol) ||
            error("@domain options are `root = T` / `nothing = T` / `insertion = T`, got `$o`")
        k, v = o.args
        if k === :root
            root_sym = v; gen_root = false
        elseif k === :nothing
            nothing_sym = v; gen_nothing = false
        elseif k === :insertion
            insertion_sym = v; gen_insertion = false
        else
            error("@domain: unknown option `$k`")
        end
    end

    M = @__MODULE__
    root, noth, ins = esc(root_sym), esc(nothing_sym), esc(insertion_sym)
    out = Expr(:block)

    if gen_root
        push!(out.args, :(abstract type $root <: $Document end))
        # The root is what a reader looks for first — "the documents of this
        # domain" — so it says what it is, as the placeholder and the insertion
        # below do.
        push!(out.args, esc(Expr(:macrocall, GlobalRef(Core, Symbol("@doc")), __source__,
            "    $root_sym\n\n" *
            "Every document of the $prefix domain.\n\n" *
            "Use it to write a function or a projection that takes any $prefix " *
            "document, whatever kind it is, and to ask whether a value belongs to " *
            "this domain.\n\n" *
            "# Example\n\n" *
            "    is_$(lowercase(prefix))(document) = document isa $root_sym\n\n" *
            "See also `$nothing_sym`, the empty one, and `$insertion_sym`, the one a " *
            "person types a name into.",
            root_sym)))
    end
    # The root is the domain's public name, so it is exported either way —
    # generated here, or adopted with `root = X` and defined at the call site.
    push!(out.args, esc(Expr(:export, root_sym)))
    if gen_nothing
        # `struct XNothing <: XDocument end` — a placeholder holds nothing but its
        # selection, and `@document` injects that. Run through the `@document` macro
        # function (its expansion is fully escaped, so it resolves at this call site).
        ndef = Expr(:struct, false, Expr(:(<:), nothing_sym, root_sym), Expr(:block))
        push!(out.args, var"@document"(__source__, __module__, ndef))
        push!(out.args, esc(Expr(:macrocall, GlobalRef(Core, Symbol("@doc")), __source__,
            "`@domain $prefix`-generated empty placeholder: the absence of a " *
            "$prefix document. Insert turns it into a `$insertion_sym`.", nothing_sym)))
    end
    if gen_insertion
        idef = Expr(:struct, false, Expr(:(<:), insertion_sym, root_sym),
                    Expr(:block, Expr(:(=), Expr(:(::), :value, String), "")))
        push!(out.args, var"@document"(__source__, __module__, idef))
        # A fully-defaulted @document struct gets no positional constructors;
        # generate the `XInsertion("prefix")` convenience by hand.
        push!(out.args, :($(esc(insertion_sym))(value::AbstractString) =
            $(esc(insertion_sym))(String(value), nothing)))
        push!(out.args, esc(Expr(:macrocall, GlobalRef(Core, Symbol("@doc")), __source__,
            "`@domain $prefix`-generated insertion: a typed-name buffer completing " *
            "over the `$root_sym` candidates (prefix-free); Enter commits, Escape " *
            "aborts to `$nothing_sym`.", insertion_sym)))
    end

    tag = lowercase(prefix)
    append!(out.args, (
        :($M.get_domain_prefix(::Type{<:$root}) = $prefix),
        :($M.get_domain_insertion(::Type{<:$root}) = $ins),
        :($M.get_insertion_root(::Type{<:$ins}) = $root),
        :($M.get_nothing_document(::Type{<:$ins}) = $noth),
        :($M.get_insertion_document(::Type{<:$noth}) = $ins),
        :($M.get_insertion_aliases(::Type{<:$ins}) = [$tag]),
        :($M.insertable(::Type{<:$noth}) = false),
        # The Insert-key gesture on the placeholder. Same registry seam as
        # `@gestures` (a method, not a mutable table, so it survives
        # precompilation), emitted directly to avoid nesting that macro.
        :($GestureBindingModule.get_document_gesture_bindings_own(::Type{$noth}) =
              $(GestureBinding)[$(_insert_gesture_binding)($ins, $tag)]),
    ))
    out
end
