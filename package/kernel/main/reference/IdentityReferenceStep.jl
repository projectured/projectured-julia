# Fragment of `ReferenceModule` — the `IdentityReferenceStep`: stable,
# name-based reference addressing paired with `IdentityDocument`.
#
# Registered as `:structural` and hooked into the `@reference` DSL as the
# `.identity(id)` extension. Resolution runs `search_documents` DFS
# pre-order over the current focus and expects **exactly one match** —
# zero matches is `IdentityDocumentNotFound`, more than one is
# `DuplicateIdentityDocument` (both at resolve time, so a transient
# duplicate mid-edit is tolerated). The step evaluates to the matched
# `IdentityDocument`'s `.content`, so a chain like
# `file("x.jl").identity("host-1").submodules` continues from that
# content into ordinary field navigation.

"""
    IdentityReferenceStep(identity::AbstractString)

Search-based reference step keyed off `IdentityDocument.identity`.
Evaluation runs a DFS pre-order walk over the current focus, finds the
`IdentityDocument` whose `identity == identity`, and yields its
`.content`. Errors on no match (`IdentityDocumentNotFound`) or on more
than one match (`DuplicateIdentityDocument`) — the invariant is exactly
one match at resolve time, checked lazily so a duplicate can appear
transiently mid-edit.
"""
@cell_struct struct IdentityReferenceStep <: ReferenceStep
    identity::String
end

Base.show(io::IO, s::IdentityReferenceStep) = print(io, ".identity(", repr(s.identity), ")")

Base.:(==)(a::IdentityReferenceStep, b::IdentityReferenceStep) = a.identity == b.identity

get_reference_step_kind(::IdentityReferenceStep) = :structural

"""
    IdentityDocumentNotFound(identity)

Thrown by `evaluate_reference_step(::IdentityReferenceStep, …)` when no
`IdentityDocument` with the requested `identity` is reachable from the
current focus.
"""
struct IdentityDocumentNotFound <: Exception
    identity::String
end

Base.showerror(io::IO, e::IdentityDocumentNotFound) =
    print(io, "IdentityDocumentNotFound: no IdentityDocument with identity ",
          repr(e.identity), " in the current focus")

"""
    DuplicateIdentityDocument(identity, count)

Thrown by `evaluate_reference_step(::IdentityReferenceStep, …)` when more
than one `IdentityDocument` with the requested `identity` is reachable
from the current focus.
"""
struct DuplicateIdentityDocument <: Exception
    identity::String
    count::Int
end

Base.showerror(io::IO, e::DuplicateIdentityDocument) =
    print(io, "DuplicateIdentityDocument: ", e.count,
          " IdentityDocuments with identity ", repr(e.identity),
          " in the current focus (expected exactly one)")

evaluate_reference_step(step::IdentityReferenceStep, document) =
    _identity_resolve(step.identity, document)

function _identity_resolve(id::AbstractString, document)
    matches = search_documents(document, x -> x isa IdentityDocument && x.identity == id)
    isempty(matches) && throw(IdentityDocumentNotFound(String(id)))
    length(matches) > 1 && throw(DuplicateIdentityDocument(String(id), length(matches)))
    unwrap_cell(matches[1].content)
end

# ── DSL registrations ────────────────────────────────────────────────────

# `.identity(id)` — argument 1 is an ordinary value expression (the id
# string). Nothing subpath-shaped, so the default answer of `()` is right.

build_reference_step(::Val{:identity}, idex) =
    :($(GlobalRef(@__MODULE__, :IdentityReferenceStep))(String($idex)))

function match_reference_step(::Val{:identity}, hex, argpats, rest_success, bound,
                              gen_value_match, gen_path_match)
    idpat = argpats[1]
    idexpr = :($hex.identity)
    after_id, bound1 = gen_value_match(idexpr, idpat, rest_success, bound)
    ex = quote
        if $hex isa $(GlobalRef(@__MODULE__, :IdentityReferenceStep))
            $after_id
        else
            _nomatch
        end
    end
    return ex, bound1
end
