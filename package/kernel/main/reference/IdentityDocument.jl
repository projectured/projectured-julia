# Fragment of `ReferenceModule` — the `IdentityDocument`: a two-field wrapper
# whose `identity` tag is what stable, name-based reference addressing keys off.
#
# Paired at the reference layer with `IdentityReferenceStep`, which searches
# the current focus DFS pre-order for the `IdentityDocument` whose
# `identity` matches and yields its `.content`. Wrapping a subtree in an
# `IdentityDocument` is what makes a fragment reference into a file survive
# structural edits: the reference names the identity, not a positional path,
# so an edit that moves the subtree around inside the file does not
# invalidate the reference.

"""
    IdentityDocument(identity::AbstractString, content)

A stable-identity wrapper document. Anywhere a document tree needs a node
that a cross-file reference can point at by a name that survives structural
moves, wrap the node in an `IdentityDocument`: the `identity` field carries
the tag, `content` carries the wrapped node, and an
`IdentityReferenceStep(identity)` in a reference chain resolves to `content`
regardless of where the wrapper now sits.

Duplicate identities within a single reference-resolution scope are an
error at resolve time (see the `IdentityReferenceStep` step), so a
transient duplicate mid-edit is tolerated but a stored reference will
never silently pick one of two matches.
"""
@document struct IdentityDocument <: Document
    identity::String
    content::Any = nothing
end
