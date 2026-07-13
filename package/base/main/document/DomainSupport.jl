"""
    DomainSupportModule

Per-domain insertion support, in two halves:

1. **The `@domain` macro** — generates a document domain's whole insertion kit
   from one line: the abstract root (`JsonDocument`), the empty placeholder
   (`JsonNothing`), the typed-name insertion buffer (`JsonInsertion`), the
   Insert-key gesture that turns the placeholder into the insertion, and the
   insertion *traits* that anchor everything below.

2. **Reflection-based completion** — the candidate list for an insertion is
   *computed* from the document type tree (`insertion_candidates`, memoized on
   the world counter so a newly defined `@document` type is completable the
   moment its `struct` is evaluated), the accepted names are *derived* from the
   type name (`insertion_names`: the capitalized type name `JsonString` and the
   lowercase human-readable form `json string`; prefix-free inside a domain
   scope), and construction goes through *dispatch* (`make_insertion_document`,
   zero-arg fallback + per-type cursor/scaffold overrides). Nothing is listed
   or registered.

`complete_insertion` classifies a typed prefix (`:empty` / `:invalid` /
`:unambiguous` / `:ambiguous`) and computes the completion continuation;
`resolve_insertion` maps a typed name to the committable type (exact name or
alias first, then an unambiguous prefix).
"""
module DomainSupportModule

import InteractiveUtils: subtypes
import ..GestureModule
import ..DocumentModule: Document, var"@document"
import ..ReferenceModule: Reference, ConcreteReferencePath, FieldReference, RangeReference,
                          EmptyReferencePath
import ..SelectionModule: with_selection
import ..OperationModule: replace_document
import ..GestureModule: GestureBinding, KeyDownPattern, get_document_gesture_bindings_own
import ..DocumentCoreModule: DocumentNothing, DocumentInsertion

export var"@domain",
       insertion_root, nothing_document, insertion_document, domain_prefix,
       domain_insertion, insertable, insertion_aliases, make_insertion_document,
       insertion_names, insertion_candidates, complete_insertion, resolve_insertion,
       insert_document_operation

# ── Traits ────────────────────────────────────────────────────────────────────
#
# The dispatch anchors `@domain` emits (and `DocumentNothing`/`DocumentInsertion`
# implement by hand below). They replace every string-naming convention: the
# completion machinery never inspects a type name to decide *behaviour*, only to
# derive display names.

"""
    insertion_root(::Type{<:Document}) -> Type

The abstract root whose subtypes an insertion buffer completes over —
`JsonDocument` for `JsonInsertion`, `Document` for the domain-independent
`DocumentInsertion` (the default).
"""
insertion_root(::Type) = Document

"""
    nothing_document(::Type{<:Document}) -> Type

The placeholder document an insertion aborts back to on Escape. Defaults to
`DocumentNothing`; `@domain` points each domain's insertion at its own
`*Nothing`.
"""
nothing_document(::Type) = DocumentNothing

"""
    insertion_document(::Type{<:Document}) -> Type

The insertion a `*Nothing` placeholder turns into on the Insert key. Defaults
to `DocumentInsertion`.
"""
insertion_document(::Type) = DocumentInsertion

"""
    domain_insertion(::Type) -> Type | Nothing

The insertion type belonging to an abstract domain root (`JsonDocument` →
`JsonInsertion`), or `nothing` when the root has none. Used to exclude the
scope's own insertion from its candidate list.
"""
domain_insertion(::Type) = nothing

"""
    domain_prefix(root::Type) -> String

The type-name prefix stripped for prefix-free matching inside a domain scope
(`JsonDocument` → `"Json"`, so `JsonString` also answers to `String` /
`string`). Empty for the universal root `Document`. The default derives it
from the root's name by dropping a trailing `"Document"`.
"""
function domain_prefix(root::Type)
    root === Document && return ""
    n = String(nameof(root))
    endswith(n, "Document") ? n[1:end-length("Document")] : n
end

"""
    insertion_aliases(::Type) -> Vector{String}

Extra short names a candidate answers to besides its derived names (`"julia"`
for `JuliaInsertion`). `@domain` emits the lowercase domain name as its
insertion's alias; anything else is a hand-written method.
"""
insertion_aliases(::Type) = String[]

# ── Construction (dispatch, not factory tables) ───────────────────────────────

"""
    make_insertion_document(::Type{T}) -> Document

A fresh document committed for candidate `T`. The fallback is the zero-arg
constructor; per-type methods add cursor placement / scaffolds where the empty
instance is not enough — an empty text leaf, say, wants a caret at position 0
rather than a whole-node selection (see `@with_selection`).
"""
make_insertion_document(::Type{T}) where {T} = T()

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

function _collect_concrete!(out::Vector{Type}, root::Type)
    for T in subtypes(root)
        if isabstracttype(T)
            _collect_concrete!(out, T)
        else
            push!(out, T)
        end
    end
    out
end

# A type that *looks like* an insertion cursor (its name ends in "Insertion")
# is only a candidate when it really is a domain's entry point — its
# `insertion_root` names it back as that root's `domain_insertion`. This keeps
# the `@domain` insertions committable from the top level (they carry the
# traits) while stray per-slice cursors (`ClipboardInsertion`,
# `WidgetInsertion`, …) stay out of the list without per-type opt-outs.
function _is_domain_entry(T::Type)
    endswith(String(nameof(T)), "Insertion") || return true
    domain_insertion(insertion_root(T)) === T
end

"""
    insertion_candidates(root::Type) -> Vector{Type}

Every insertable concrete document type under `root`, computed by reflection
over the type tree — never listed or registered, so a newly defined
`@document` type appears automatically. Memoized on `Base.get_world_counter()`
(any new type/method definition invalidates the cache; otherwise it is one
dictionary lookup). The scope's own insertion (`domain_insertion(root)`) is
excluded — you are already in one — as are insertion cursors that are not
their domain's entry point.
"""
function insertion_candidates(root::Type)
    world = Base.get_world_counter()
    cached = get(_CANDIDATE_CACHE, root, nothing)
    cached !== nothing && cached[1] == world && return cached[2]
    own = domain_insertion(root)
    result = filter!(T -> insertable(T) && T !== own && _is_domain_entry(T),
                     _collect_concrete!(Type[], root))
    _CANDIDATE_CACHE[root] = (world, result)
    result
end

# ── Name derivation ───────────────────────────────────────────────────────────

# "JsonObjectEntry" -> "json object entry"
_camel_words(s::AbstractString) =
    lowercase(replace(s, r"(?<=[a-z0-9])(?=[A-Z])" => " "))

"""
    insertion_names(T; root = Document) -> Vector{String}

The names candidate `T` answers to, derived from its type name: the
capitalized type name (`"JsonString"`), the lowercase human-readable form
(`"json string"`), the same pair with the scope's `domain_prefix` stripped
(`"String"` / `"string"` when `root = JsonDocument`), plus any
`insertion_aliases`.
"""
function insertion_names(T::Type; root::Type = Document)
    base = String(nameof(T))
    names = String[base, _camel_words(base)]
    p = domain_prefix(root)
    if !isempty(p) && startswith(base, p) && length(base) > length(p)
        stripped = base[length(p)+1:end]
        push!(names, stripped, _camel_words(stripped))
    end
    append!(names, insertion_aliases(T))
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
    for T in insertion_candidates(root)
        ns = [n for n in insertion_names(T; root) if startswith(lowercase(n), key)]
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
    resolve_insertion(root, typed) -> Type | Nothing

The committable candidate for the typed buffer: an **exact** name/alias match
wins (so the alias `"julia"` commits `JuliaInsertion` even while it is also a
prefix of other names); otherwise the single candidate of an `:unambiguous`
prefix; otherwise `nothing`.
"""
function resolve_insertion(root::Type, typed::AbstractString)
    key = lowercase(strip(typed))
    isempty(key) && return nothing
    for T in insertion_candidates(root)
        any(lowercase(n) == key for n in insertion_names(T; root)) && return T
    end
    c = complete_insertion(root, typed)
    c.state === :unambiguous ? c.matches[1] : nothing
end

# ── Insert-key gesture (shared by @domain and DocumentNothing) ────────────────

# The char cursor at offset 0 of an insertion's `value` buffer.
const _INSERTION_CURSOR = ConcreteReferencePath(FieldReference("value"),
    ConcreteReferencePath(RangeReference(0, 0), EmptyReferencePath()))

"""
    insert_document_operation(I::Type) -> Operation

The operation the Insert key emits on a `*Nothing` placeholder: replace it (∅,
rerooted by the enclosing projections) with a fresh insertion `I`, cursor
pre-placed at the start of its `value` buffer.
"""
insert_document_operation(::Type{I}) where {I} =
    replace_document(EmptyReferencePath(), with_selection(I(), _INSERTION_CURSOR))

_insert_gesture_binding(::Type{I}, tag::String) where {I} = GestureBinding(
    KeyDownPattern(:insert, nothing, nothing),
    (doc, event) -> insert_document_operation(I),
    (doc, sel) -> true,
    "Insert a new " * (isempty(tag) ? "" : tag * " ") * "document",
    isempty(tag) ? "document" : tag)

# ── The universal domain: DocumentNothing / DocumentInsertion ─────────────────
#
# Hand-written in DocumentCore (they carry custom label constants), but they
# implement the same traits, so the shared gestures and the reflection treat
# the domain-independent insertion identically.

insertion_root(::Type{<:DocumentInsertion}) = Document
nothing_document(::Type{<:DocumentInsertion}) = DocumentNothing
insertion_document(::Type{<:DocumentNothing}) = DocumentInsertion
domain_insertion(::Type{Document}) = DocumentInsertion
insertable(::Type{<:DocumentNothing}) = false
insertable(::Type{<:DocumentInsertion}) = false

get_document_gesture_bindings_own(::Type{DocumentNothing}) =
    GestureBinding[_insert_gesture_binding(DocumentInsertion, "")]

# ── @domain ───────────────────────────────────────────────────────────────────

"""
    @domain Json
    @domain Julia root = JuliaDocument nothing = JuliaNothing insertion = JuliaInsertion

Generate a document domain's insertion kit from its name:

- `abstract type JsonDocument <: Document end` (exported),
- `@document struct JsonNothing <: JsonDocument` — the empty placeholder,
- `@document struct JsonInsertion <: JsonDocument` — the typed-name buffer
  (`value::String = ""`),
- the Insert-key gesture turning the placeholder into the insertion (cursor in
  the buffer),
- the traits wiring it all: `domain_prefix`, `domain_insertion`,
  `insertion_root`, `nothing_document`, `insertion_document`, the lowercase
  domain name as the insertion's alias, and the placeholder's `insertable`
  opt-out.

Each `root = X` / `nothing = X` / `insertion = X` option **adopts** an existing
type instead of generating one (only its traits and gestures are emitted); the
option's type must already be defined at the `@domain` call site. Escape from
an insertion is *not* generated per domain — the shared insertion gestures
abort to `nothing_document(typeof(ins))()` generically.

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
        push!(out.args, esc(Expr(:export, root_sym)))
    end
    if gen_nothing
        # `struct XNothing <: XDocument; selection::Reference = nothing; end`,
        # run through the @document macro function (its expansion is fully
        # escaped, so it resolves at this call site). Field types are spliced
        # as objects, so the caller needs no extra imports.
        ndef = Expr(:struct, false, Expr(:(<:), nothing_sym, root_sym),
                    Expr(:block, Expr(:(=), Expr(:(::), :selection, Reference), :nothing)))
        push!(out.args, var"@document"(__source__, __module__, ndef))
        push!(out.args, esc(Expr(:macrocall, GlobalRef(Core, Symbol("@doc")), __source__,
            "`@domain $prefix`-generated empty placeholder: the absence of a " *
            "$prefix document. Insert turns it into a `$insertion_sym`.", nothing_sym)))
    end
    if gen_insertion
        idef = Expr(:struct, false, Expr(:(<:), insertion_sym, root_sym),
                    Expr(:block,
                         Expr(:(=), Expr(:(::), :value, String), ""),
                         Expr(:(=), Expr(:(::), :selection, Reference), :nothing)))
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
        :($M.domain_prefix(::Type{<:$root}) = $prefix),
        :($M.domain_insertion(::Type{<:$root}) = $ins),
        :($M.insertion_root(::Type{<:$ins}) = $root),
        :($M.nothing_document(::Type{<:$ins}) = $noth),
        :($M.insertion_document(::Type{<:$noth}) = $ins),
        :($M.insertion_aliases(::Type{<:$ins}) = [$tag]),
        :($M.insertable(::Type{<:$noth}) = false),
        # The Insert-key gesture on the placeholder. Same registry seam as
        # `@gestures` (a method, not a mutable table, so it survives
        # precompilation), emitted directly to avoid nesting that macro.
        :($GestureModule.get_document_gesture_bindings_own(::Type{$noth}) =
              $(GestureBinding)[$(_insert_gesture_binding)($ins, $tag)]),
    ))
    out
end

end # module
