# ═══════════════════════════════════════════════════════════════════════════
# test/projection/CatalogCoverageTest.jl
#
# Is the atomic-document registry actually exhaustive? The directive in
# plan/pending/catalog-all-documents.md says every document type is an atom.
# Nothing checked it, and the answer turned out to be no.
#
# The check does not need a list of what ought to exist: the printers ARE the
# list. Every `print_document(::P, recursion, ::D, ctx)` method declares that
# some projection `P` renders some document type `D`, so the set of `D`s over
# the whole method table is exactly the set of types an atom is owed. Anything
# in it without an atom is a document nobody can print in isolation — untested
# by the catalog, and (see plan/pending/precompile-workloads.md) uncompilable by
# a precompile workload, because a workload can only run what it can construct.
# ═══════════════════════════════════════════════════════════════════════════

# The stem type behind a printer's document parameter: `JuliaFunction` from
# `JuliaFunction{C1,…,C6}`, so a printer declared on the UnionAll and an atom
# built as a concrete instance compare equal.
_coverage_stem(D) = begin
    T = D isa UnionAll ? Base.unwrap_unionall(D) : D
    T isa DataType ? Base.typename(T).wrapper : nothing
end

# A document type of ours — and not one a test package defines for itself. The
# suite's own fixtures (`ProbeDoc`, `Pair2`) have printers and are documents in
# every sense, but they exist only while the tests are loaded; counting them
# would make the answer depend on what happens to be `using`d.
_coverage_ours(T) = begin
    body = T isa UnionAll ? Base.unwrap_unionall(T) : T
    body isa DataType || return false
    root = string(Base.moduleroot(parentmodule(body)))
    (startswith(root, "Projectured") || startswith(root, "Omnet")) && !endswith(root, "Test")
end

# Types a printer names that no atom could ever be: `Array`/`Bool`/`Symbol` and
# friends belong to Base, and an abstract type is a dispatch target rather than
# a thing to instantiate. Both are printed through some concrete document that
# is itself in the set, so nothing is lost by leaving them out.
#
# The third exclusion is the interesting one. A printer's argument is not
# necessarily a *document*: `ReferenceToText` renders a `ConcreteReference` and
# `CellToSyntax` renders a `ReactiveCell`, but a reference is an address into a
# document and a cell is where a document's field is kept. Neither is a thing an
# `AtomicDocument` can hold — the catalog's testers print, read and navigate
# documents — so the set is documents, by subtyping rather than by a list of
# names somebody has to maintain.
function _coverage_wanted()
    want = Set{Any}()
    for m in methods(ProjecturedAll.ProjectionModule.print_document)
        sig = Base.unwrap_unionall(m.sig)
        length(sig.parameters) == 5 || continue
        P, D = sig.parameters[2], sig.parameters[4]
        (P isa DataType && isconcretetype(P)) || continue
        D === Any && continue
        T = _coverage_stem(D)
        (T === nothing || !_coverage_ours(T)) && continue
        body = T isa UnionAll ? Base.unwrap_unionall(T) : T
        (body isa DataType && isabstracttype(body)) && continue
        body <: ProjecturedAll.DocumentModule.Document || continue
        push!(want, T)
    end
    want
end

_coverage_covered() = begin
    have = Set{Any}()
    for a in ProjecturedExample.atomic_documents()
        T = try _coverage_stem(typeof(a.make_document())) catch; nothing end
        T === nothing || push!(have, T)
    end
    have
end

# ── The standing debt ──────────────────────────────────────────────────────
# Every document type below has a printer and no atom — mostly editor-chrome
# widgets (panes, the fault/gesture logs, the evaluator forms, the frame
# plot/statistics overlays, …) that nobody has written a minimal instance for
# yet. Kept as a set rather than skipped silently, so a *different*,
# unregistered type still lands as an unmarked `Fail` at `unregistered ==
# String[]` below — the way `_CATALOG_EDIT_BROKEN` records a failing one.
const _NO_ATOM = Set{String}([
    "AboutPage", "AppearanceDocument", "Assistant", "CommandPalette", "ContextMenuWindowState",
    "DataFrameView", "DragTrackingState", "EvaluatorForm",
    "EvaluatorToplevel", "FaultLog", "FaultReport", "FileSystemChooser",
    "FrameStatistics", "FrameTimeSeries", "GestureLog", "GestureTrackingState", "JuliaToplevel",
    "McpLog", "MessageLog", "ObjectField", "PaneGroup", "PaneSplit", "PaneTree",
    "SelectionInspector", "Settings", "SettingsDocument", "TextGraphics", "TextSpacing",
    "TooltipContent", "TooltipWindowState", "WidgetHighlight",
    "WidgetToolbarItem",
])


"""
    get_catalog_coverage_gap() -> Vector{String}

Document type names that a printer renders and no atom instantiates, sorted.
Exposed so the gap can be inspected from the REPL while it is being closed —
`setdiff(get_catalog_coverage_gap(), …)` is the worklist.
"""
get_catalog_coverage_gap() =
    sort(String[string(nameof(T isa UnionAll ? Base.unwrap_unionall(T) : T))
                for T in setdiff(_coverage_wanted(), _coverage_covered())])

# ── Atoms the natural renderer cannot take ─────────────────────────────────
# `NaturalToGraphics` sends text through `WordWrapping → TextToGraphics`, and
# wrapping is a block-level operation: `WordWrapping` has a method for a
# `TextBlock` and none for a bare span. These three atoms are the span itself,
# which is exactly what makes them worth having — `TextStringToString` and its
# siblings print a span directly — so they are rendered by their own printer in
# the catalog and skipped here rather than being called a defect.
const _NO_NATURAL_RENDER = Set{String}([
    "text/bare_string", "text/bare_newline", "text/bare_line",
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
        format = get_natural_format(typeof(atom.make_document()))
        format !== nothing && has_natural_parser(format)
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
        format = get_natural_format(typeof(document))
        (format !== nothing && has_natural_parser(format)) || return false
        parse_natural_text(format, print_natural_text(document))
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

function test_catalog_coverage()
    @testset "catalog coverage" begin
        wanted = _coverage_wanted()
        @test !isempty(wanted)                 # the method table was actually read
        gap = Set(get_catalog_coverage_gap())

        # A printer written after this list was drawn up, whose document type has
        # no atom, lands here as an unmarked failure. That is the whole check.
        unregistered = sort(collect(setdiff(gap, _NO_ATOM)))
        @test unregistered == String[]

        # And the list cannot outlive the gap: a name still registered after its
        # atom was written is stale and has to go, or the debt reads as larger
        # than it is.
        stale = sort(collect(setdiff(_NO_ATOM, gap)))
        @test stale == String[]

        # And the whole point: nothing is owed.
        # @broken: 32 document types in `_NO_ATOM` have a printer and no atom
        # yet; this stays broken until each one gets a hand-authored atomic
        # document and is removed from that set.
        @test_broken isempty(gap)
    end
end
