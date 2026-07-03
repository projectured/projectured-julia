"""
    VersioningModule

Object-versioning document types. A generic, domain-neutral overlay that lets
**any** document subtree carry multiple versions of itself.

Versioning has exactly two levels:

- `VersionedObject` — the container that *has versions*: a `versions` list (a
  `CellVector` of `ObjectVersion`s, newest-first by convention) plus the active
  selection `criterion` (a `VersionCriterion`).
- `ObjectVersion` — one *value object* (the actual domain document for this
  version) together with its `VersionProperties` (metadata: when, who, where).

`VersionProperties` is itself a document so it is inspectable/editable/
projectable (and could later be versioned too). All its fields are optional —
a version can be anonymous.

The wrapper is *optional* (a subtree is versioned only if wrapped) and
*recursive* (the value object may itself contain `VersionedObject`s nested
anywhere within it; each resolves independently). The matching elimination
projection (`VersioningToAnyProjectionModule`) selects one version by criterion
and projects that version's value object in place of the wrapper.

This mirrors `ClipboardModule` structurally: a wrapper document holding a
payload, eliminated by a projection that decides which child becomes the output.
"""
module VersioningModule

import ..CellModule: Cell
import ..DocumentApiModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export VersioningDocument, VersionCriterion, VersionCriterionLatest, VersionCriterionIndex,
       VersionCriterionByAuthor, VersionCriterionAsOf, VersionCriterionPredicate, select_version

# ── Abstract base ─────────────────────────────────────────────────────────────

abstract type VersioningDocument <: Document end

# ── VersionProperties ─────────────────────────────────────────────────────────

"""
    VersionProperties(; timestamp=nothing, author=nothing, origin=nothing, label=nothing, selection=nothing)

Version metadata. A document so it is itself inspectable/editable/projectable.
All fields optional — a version can be anonymous.

- `timestamp` — e.g. a `DateTime`, or `nothing`.
- `author` — who created it (string / user object / `nothing`).
- `origin` — where it came from (host, file, session, `nothing`).
- `label` — optional human name / tag for the version.
"""
@document struct VersionProperties <: VersioningDocument
    timestamp::Any        # e.g. DateTime, or nothing
    author::Any           # who created it (string / user object / nothing)
    origin::Any           # where it came from (host, file, session, nothing)
    label::Any            # optional human name / tag for the version
    selection::Reference
end

VersionProperties(; timestamp=nothing, author=nothing, origin=nothing,
                    label=nothing, selection=nothing) =
    VersionProperties(Cell(timestamp), Cell(author), Cell(origin),
                      Cell(label), Cell(selection))

# ── ObjectVersion ─────────────────────────────────────────────────────────────

"""
    ObjectVersion(value; properties=VersionProperties(), selection=nothing)
    ObjectVersion(value; timestamp=…, author=…, origin=…, label=…, selection=nothing)

The second level: one `value` object (the actual domain document for this
version) together with its `properties`. The keyword form builds the
`VersionProperties` for you when no explicit `properties` document is supplied.
"""
@document struct ObjectVersion <: VersioningDocument
    value::Document            # the actual domain document for this version
    properties::VersionProperties
    selection::Reference
end

ObjectVersion(value; properties=nothing, timestamp=nothing, author=nothing,
                origin=nothing, label=nothing, selection=nothing) =
    ObjectVersion(Cell(value),
                  Cell(properties === nothing ?
                       VersionProperties(timestamp=timestamp, author=author,
                                         origin=origin, label=label) :
                       properties),
                  Cell(selection))

# ── VersionedObject ───────────────────────────────────────────────────────────

"""
    VersionedObject(versions; criterion=VersionCriterionLatest(), selection=nothing)
    VersionedObject(value::Document; criterion=…, …)

The first level: many `ObjectVersion`s (newest-first by convention) plus the
active selection `criterion`. The single-`value` form wraps `value` in one
initial `ObjectVersion`.
"""
@document struct VersionedObject <: VersioningDocument
    versions::CellVector       # Vector{ObjectVersion}, newest-first by convention
    criterion::Any             # a VersionCriterion; selects the active version
    selection::Reference
end

VersionedObject(versions::AbstractVector; criterion=VersionCriterionLatest(),
                  selection=nothing) =
    VersionedObject(CellVector(Cell[Cell(v) for v in versions]),
                    Cell(criterion), Cell(selection))

VersionedObject(value::Document; criterion=VersionCriterionLatest(),
                  timestamp=nothing, author=nothing, origin=nothing,
                  label=nothing, selection=nothing) =
    VersionedObject([ObjectVersion(value; timestamp=timestamp, author=author,
                                   origin=origin, label=label)];
                    criterion=criterion, selection=selection)

# ── Version criteria ──────────────────────────────────────────────────────────
# An abstract type with concrete subtypes (the `DocumentLocator<Mode>` pattern):
# `select_version` dispatches on the concrete criterion, so new selection modes
# are added without touching the projection.

abstract type VersionCriterion end

"""
    VersionCriterionLatest()

Select the newest version. By the newest-first convention this is the first
element of `versions`.
"""
struct VersionCriterionLatest <: VersionCriterion end

"""
    VersionCriterionIndex(index)

Explicit pin: select the version at the 1-based `index`.
"""
struct VersionCriterionIndex <: VersionCriterion
    index::Int
end

"""
    VersionCriterionByAuthor(author)

Select the newest version whose `properties.author` equals `author`.
"""
struct VersionCriterionByAuthor <: VersionCriterion
    author::Any
end

"""
    VersionCriterionAsOf(timestamp)

Select the newest version whose `properties.timestamp` is `≤ timestamp`.
"""
struct VersionCriterionAsOf <: VersionCriterion
    timestamp::Any
end

"""
    VersionCriterionPredicate(predicate)

Select the newest version whose `properties` satisfies `predicate(properties)`.
"""
struct VersionCriterionPredicate <: VersionCriterion
    predicate::Any
end

# ── select_version ────────────────────────────────────────────────────────────

"""
    select_version(vo::VersionedObject) -> Union{Nothing, Tuple{Int, ObjectVersion}}

Resolve `vo`'s active version by dispatching on `vo.criterion`. Returns the
chosen 1-based `(index, version)` (the index is needed for reference mapping),
or `nothing` when no version matches (the projection then emits a
`DocumentNothing`, mirroring `ClipboardSlice`'s empty-slice fallback).

Versions are stored newest-first, so "newest" means the lowest matching index.
"""
function select_version(vo::VersionedObject)
    _select_version(vo.criterion, vo.versions)
end

# Latest: the first (newest) version, when any.
function _select_version(::VersionCriterionLatest, versions)
    isempty(versions) && return nothing
    (1, versions[1])
end

# Index: explicit 1-based pin, bounds-checked.
function _select_version(c::VersionCriterionIndex, versions)
    (c.index < 1 || c.index > length(versions)) && return nothing
    (c.index, versions[c.index])
end

# By author: newest version whose properties.author matches (lowest index).
function _select_version(c::VersionCriterionByAuthor, versions)
    for i in 1:length(versions)
        v = versions[i]
        v.properties.author == c.author && return (i, v)
    end
    nothing
end

# As-of: newest version with a non-nothing timestamp ≤ the cutoff (lowest index).
function _select_version(c::VersionCriterionAsOf, versions)
    for i in 1:length(versions)
        v = versions[i]
        ts = v.properties.timestamp
        ts !== nothing && ts <= c.timestamp && return (i, v)
    end
    nothing
end

# Predicate: newest version whose properties satisfy f (lowest index).
function _select_version(c::VersionCriterionPredicate, versions)
    for i in 1:length(versions)
        v = versions[i]
        c.predicate(v.properties) && return (i, v)
    end
    nothing
end

end # module
