# ═══════════════════════════════════════════════════════════════════════════
# test/projection/CatalogCoverageTest.jl
#
# Is the atomic-document registry actually exhaustive? The directive in
# plan/pending/catalog-all-documents.md says every document type is an atom.
# Nothing checked it, and the answer turned out to be no.
#
# The check does not need a list of what ought to exist: the printers ARE the
# list (`find_catalog_coverage_gap` and `test_atom_coverage` of
# `ProjecturedPlatformTest` read the method table of `print_document`). Anything
# in it without an atom is a document nobody can print in isolation — untested
# by the catalog, and (see plan/pending/precompile-workloads.md) uncompilable by
# a precompile workload, because a workload can only run what it can construct.
# ═══════════════════════════════════════════════════════════════════════════

# The roots of the modules whose printers the atoms of this repository cover.
const _COVERAGE_ROOTS = ("Projectured", "Omnet")

# ── The standing debt ──────────────────────────────────────────────────────
# Every document type below has a printer and no atom. The view of a data frame
# holds a `DataFrame`, and the catalog loads no package of the DataFrames adapter,
# so no atom of the catalog can make one. Kept as a set rather than skipped
# silently, so a *different*, unregistered type still lands as an unmarked `Fail`
# at `unregistered == String[]` below — the way `_CATALOG_EDIT_BROKEN` records a
# failing one.
const _NO_ATOM = Set{String}([
    "DataFrameView", "DataFrameViewRow",
    # @broken: these types have a printer and no atom yet; on main 2026-11-20, not studied
    "AppearanceColors", "AppearanceScale", "DashboardCard", "GitCommit", "GitCommitRange",
    "GitFileChange", "GitFileRevision", "RecordTable", "ThemeGroup",
])


"""
    get_catalog_coverage_gap() -> Vector{String}

Document type names that a printer renders and no atom instantiates, sorted.
Exposed so the gap can be inspected from the REPL while it is being closed —
`setdiff(get_catalog_coverage_gap(), …)` is the worklist.
"""
get_catalog_coverage_gap() =
    find_catalog_coverage_gap(ProjecturedExample.atomic_documents(); roots = _COVERAGE_ROOTS)

# ── Atoms the natural renderer cannot take ─────────────────────────────────
# `NaturalToGraphics` sends text through `WordWrapping → TextToGraphics`, and
# wrapping is a block-level operation: `WordWrapping` has a method for a
# `TextBlock` and none for a bare span. The `bare_*` atoms and the gutter of a
# line are the span or the part itself, which is exactly what makes them worth
# having — `TextStringToString` and its siblings print a span directly — so they
# are rendered by their own printer in the catalog and skipped here rather than
# being called a defect.
const _NO_NATURAL_RENDER = Set{String}([
    "text/bare_string", "text/bare_line", "text/bare_spacing", "text/bare_graphics",
    "text/gutter",
])

"""
    test_natural_renders_every_atom()

The precompile workload swallows a failing atom, because a workload must not
fail a build. This is where that failure is meant to surface instead: every atom
has to survive `NaturalToGraphics`, the renderer an editor actually puts on
screen, or the workload is compiling less than it appears to.

`_NO_NATURAL_RENDER` names the ones the natural renderer legitimately has no
route for; anything else that fails, fails here.
"""
function test_natural_renders_every_atom()
    @testset "every atom renders naturally" begin
        atoms = ProjecturedExample.atomic_documents()
        renders(a) = precompile_atoms([a]) == 1
        failed = Set(_round_trip_name(a) for a in atoms if !renders(a))
        @test sort(collect(setdiff(failed, _NO_NATURAL_RENDER))) == String[]
        @test sort(collect(setdiff(_NO_NATURAL_RENDER, failed))) == String[]
    end
end

# Does this atom's domain declare a natural text format with a parser behind it?
# Domains without one (text, primitive, book…) are not round-trip candidates and
# are not failures.
function _round_trip_eligible(atom)
    try
        format = find_natural_file_format(atom.make_document())
        format !== nothing && hasmethod(parse_document_string, Tuple{typeof(format), String})
    catch
        false
    end
end

# ── Atoms that are fragments, not documents ────────────────────────────────
# A natural format parses a *file*, and several atoms are deliberately smaller
# than one: a column name is not a statement, an attribute is not a root element,
# `"key": value` is not a JSON document. Rendering them is right and re-reading
# them is not, so they are named here rather than counted.
#
# An atom that stops round-tripping and is NOT named here fails unmarked, which
# is the point; and a name here that starts round-tripping is asserted stale.
const _NO_ROUND_TRIP = Set{String}([
    # Sub-document fragments: correct to render, meaningless to re-parse alone.
    "json/object_entry", "xml/text", "xml/attribute",
    "julia/interpolation", "julia/where_parameters",
    "sql/all_columns", "sql/column_name", "sql/table_name", "sql/scalar_value",
    "sql/comparison", "sql/select_item", "sql/and", "sql/or", "sql/not",
    "sql/where_filter_condition", "sql/where_clause", "sql/from_item",
    "sql/from_clause", "sql/join_on_condition", "sql/join_using_condition",
    "sql/raw_expression", "sql/raw_condition", "sql/joined_from_item",
    "sql/subquery_from_item", "sql/column_definition", "sql/update_assignment",
    "sql/column_reference", "sql/table_expression",
    # These two are whole statements and still do not re-parse — the SQL parser
    # reads SELECT and rejects INSERT/UPDATE with "not a parseable statement".
    # A parser gap rather than a fragment, and the only entry here that names a
    # bug rather than a category.
    "sql/insert_statement", "sql/update_statement",
])

_round_trip_name(atom) = string(atom.domain) * "/" * atom.name

function _round_trips(atom)
    try
        document = atom.make_document()
        format = find_natural_file_format(document)
        (format !== nothing && hasmethod(parse_document_string, Tuple{typeof(format), String})) ||
            return false
        parse_document_string(format, print_natural_text(document))
        true
    catch
        false
    end
end

"""
    test_natural_round_trips_every_atom()

The reading half. An atom whose domain declares a natural format has to render
to text and parse back, or the parser workload is compiling a path nobody walks.

Failure is legitimate for an atom smaller than a file, so those are named in
`_NO_ROUND_TRIP` rather than counted. Anything else that fails, fails here.
"""
function test_natural_round_trips_every_atom()
    @testset "every atom round-trips through its natural format" begin
        atoms = ProjecturedExample.atomic_documents()
        eligible = filter(_round_trip_eligible, atoms)
        @test !isempty(eligible)              # the format registry was read at all

        failed = Set(_round_trip_name(a) for a in eligible if !_round_trips(a))
        @test sort(collect(setdiff(failed, _NO_ROUND_TRIP))) == String[]
        @test sort(collect(setdiff(_NO_ROUND_TRIP, failed))) == String[]

        # And the workload really does exercise the rest, rather than skipping
        # everything and reporting a tidy zero.
        @test precompile_atom_parsers(atoms) == length(eligible) - length(failed)
    end
end

"""
    test_catalog_coverage()

Assert that each document type with a printer has an atom in the catalog of this
repository, except the types of `_NO_ATOM`.
"""
test_catalog_coverage() =
    test_atom_coverage(ProjecturedExample.atomic_documents(); roots = _COVERAGE_ROOTS, no_atom = _NO_ATOM)
