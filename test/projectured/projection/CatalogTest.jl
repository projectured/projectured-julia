# ═══════════════════════════════════════════════════════════════════════════
# test/projection/CatalogTest.jl
#
# Run the *existing* example-testers over the generated catalog
# (ProjecturedExample.catalog()). Each tester declares the terminal domain it
# needs; a catalog `Example` carries its `terminal`; applicability is the lookup.
# No new tester logic — this only routes catalog Examples to the right testers,
# so the scattered skip-lists dissolve. See plan/pending/discovered-example-catalog.md.
# ═══════════════════════════════════════════════════════════════════════════

# The terminal domain each tester needs (nothing = domain-agnostic: works on the
# abstract projection output). Position-navigation seeds and moves the caret by *visual*
# geometry (`Ctrl+Home` → first caret, arrows → spatial steps), which only the graphics
# layer computes — the `:home` seed reader lives in `TextToGraphics`. So it needs a
# `:graphics` terminal: a projection that stops at `:text` has no caret geometry and its
# seed read returns `nothing`. (The manual `text`/`json` examples navigate for the same
# reason — their projections run all the way through `TextToGraphics`.)
_required_terminal(::typeof(test_printer))         = nothing
_required_terminal(::typeof(test_reader))          = nothing
_required_terminal(::typeof(test_repl))            = nothing
_required_terminal(::typeof(test_position_navigation)) = :graphics

_applies(tester, ex::Example) = (r = _required_terminal(tester); r === nothing || r == ex.terminal)

# ── Known-broken registry ──────────────────────────────────────────────────
# Every document type is a catalog atom — including ones whose projection still has a
# bug (a bare compound/leaf exercises paths the big curated examples don't). Such an entry
# stays in the catalog; its failure is the visible TODO, recorded `@test_broken` keyed on
# the specific failing signature so a *different* failure still surfaces as an unmarked
# `Fail` (a regression). Fix the projection, then delete its clause here. Enumerate the
# open bugs with `grep "@catalog-broken"`.
#
# Entries whose reader/repl still fails on an editing/click gesture — the projection bug is
# the @test_broken TODO. Grouped by root cause below; a *different* error class on one of them
# still surfaces as an unmarked Fail (a regression). Fix the projection, drop it from the set.
const _CATALOG_EDIT_BROKEN = (
    # @catalog-broken sql node ChildrenIoMap read_intent has no edit-gesture method
    #   (read_intent MethodError; TypeError / FieldError reprint fallout)
    "sql/comparison/", "sql/select_item/", "sql/from_item/", "sql/join_on_condition/",
    "sql/joined_from_item/", "sql/update_assignment/", "sql/update_statement/",
    "sql/column_definition/", "sql/where_filter_condition/",
    # @catalog-broken under-typed @reference in a node's backward map (on a click)
    "filesystem/directory/",
    # Documents that had no atom until the coverage check asked for one, and so
    # have never been printed or edited standalone before. Three distinct causes,
    # all of them real gaps rather than test artefacts:
    #
    # @catalog-broken layouts and the widget composite: printed through their own
    #   single-step projection there is no `recursion`, so a child cannot be
    #   printed and the child's type has no `print_document` method. Nested under
    #   a parent (how they are always used in anger) the recursion exists and they
    #   are fine — which is exactly why a bare atom was worth adding.
    "layout/", "widget/composite/", "widget/reference_inspector/", "graph/layout/",
    # @catalog-broken bare text spans: `WordWrapping` is block-level and has no
    #   method for a lone `TextString`/`TextNewline`/`TextLine`.
    "text/bare_string/", "text/bare_newline/", "text/bare_line/",
)
_catalog_edit_broken(name) =
    any(p -> occursin(p, name), _CATALOG_EDIT_BROKEN) ?
        ((ev, msg) -> occursin("FieldError", msg) || occursin("MethodError", msg) ||
                      occursin("TypeError", msg) || occursin("under-typed", msg)) : nothing

# Entries whose position-navigation still fails — the seed can't produce a caret, or the walk
# throws (an under-typed @reference / a TypeError in a node's backward map / selection maps).
# @catalog-broken yaml/sequence: graphics Ctrl+Home seed returns nothing (0 states).
# @catalog-broken filesystem/directory: under-typed @reference on the walk.
# @catalog-broken sql/where_filter_condition: TypeError (SyntaxNavigation) on the walk.
# @catalog-broken julia/empty: renders to nothing, so there is no caret to seed (0 states).
#   Arguably not a bug — `JuliaEmpty` is the absent return type of a function that
#   declares none, and absent is what it should draw. It is marked rather than
#   skipped because the atom still has to be printed and read like any other, and
#   because "a document that renders empty" is a case the caret motion may one
#   day want an answer for.
# @catalog-broken the layouts, the widget composite, the bare text spans and the
#   embed stub: same three causes as the edit set above (no recursion standalone,
#   no block for the wrapper to wrap, no selection field), which leave the walk
#   with no caret to seed.
const _CATALOG_NAV_BROKEN = ("yaml/sequence/", "filesystem/directory/",
                             "sql/where_filter_condition/",
                             "julia/empty/",
                             "layout/", "widget/composite/",
                             "widget/reference_inspector/", "graph/layout/",
                             "text/bare_string/", "text/bare_newline/",
                             "text/bare_line/")
# Entries whose PRINTER cannot force its own output. Distinct from the edit set:
# these fail before any gesture, when the walk reads the cells the printer built.
# @catalog-broken layouts / widget composite / graph layout: no `recursion` in a
#   single-step projection, so a child has no `print_document` method.
# @catalog-broken text/bare_*: `WordWrapping` is block-level and has no method for
#   a lone span, so the derived `:graphics` variant cannot be forced. The `:text`
#   variant — the one these atoms exist for — prints fine.
const _CATALOG_PRINT_BROKEN = ("layout/", "widget/composite/",
                               "widget/reference_inspector/", "graph/layout/",
                               "text/bare_string/", "text/bare_newline/",
                               "text/bare_line/")
_catalog_print_broken(name) =
    any(p -> occursin(p, name), _CATALOG_PRINT_BROKEN) ?
        (msg -> occursin("MethodError", msg) || occursin("FieldError", msg) ||
                occursin("TypeError", msg)) : nothing

_catalog_seed_broken(name)   = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? (_errs -> true) : nothing
_catalog_throws_broken(name) = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? (_msg -> true) : nothing
# a per-state caret step whose selection can't re-apply (same broken entries).
_catalog_nav_state_broken(name) = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? ((_p, _msg) -> true) : nothing

# Route one Example to a tester, threading its known-broken signatures. printer has no
# known breaks; reader/repl take an event predicate; position-navigation takes seed/throws.
_run_catalog_tester(::typeof(test_position_navigation), ex::Example) =
    test_position_navigation(ex.name, ex.make_document(), ex.make_projection();
                             seed_broken=_catalog_seed_broken(ex.name),
                             throws_broken=_catalog_throws_broken(ex.name),
                             broken=_catalog_nav_state_broken(ex.name))
_run_catalog_tester(::typeof(test_printer), ex::Example) =
    test_printer(ex.name, ex.make_document(), ex.make_projection();
                 broken=_catalog_print_broken(ex.name))
_run_catalog_tester(::typeof(test_reader), ex::Example) =
    test_reader(ex.name, ex.make_document(), ex.make_projection(); broken=_catalog_edit_broken(ex.name))
_run_catalog_tester(::typeof(test_repl), ex::Example) =
    test_repl(ex.name, ex.make_document(), ex.make_projection(); broken=_catalog_edit_broken(ex.name))
_run_catalog_tester(tester, ex::Example) = tester(ex)

const _CATALOG_TESTERS = (test_printer, test_reader, test_repl, test_position_navigation)

"""
    test_catalog(; domain=nothing, document=nothing, terminal=nothing, only_runnable=false,
                   testers=(test_printer, test_reader, test_repl, test_position_navigation))

Run each applicable tester over the discovered example catalog, filtered by
`domain` / `document` / `terminal` / `only_runnable`. Applicability is decided per
`Example` by its `terminal` field — a `:syntax` pair runs printer/reader/repl but not
position-navigation (which needs a `:graphics` terminal) — so no skip-lists are needed.
"""
function test_catalog(; domain = nothing, document = nothing, terminal = nothing,
                        only_runnable = false, testers = _CATALOG_TESTERS)
    @testset "Catalog" begin
        for ex in catalog(; domain = domain, document = document,
                            terminal = terminal, only_runnable = only_runnable)
            @testset "$(ex.name)" begin
                for tester in testers
                    _applies(tester, ex) && _run_catalog_tester(tester, ex)
                end
            end
        end
    end
end

"""
    test_catalog_typeins(; domain=:text)

Run `test_typein` (the character insert/backspace/delete round-trip at every caret)
over the `:graphics` variant of each atomic document in `domain` — the one tester
`test_catalog`'s set omits, because most domains route their leaf edits through
domain-specific readers already covered by the curated `test_typeins`. The text
atoms render straight through `TextToGraphics`, so every caret is a real editable
text cursor; this asserts each atom types cleanly under the default text projection.
"""
function test_catalog_typeins(; domain = :text)
    @testset "CatalogTypeins" begin
        for ex in catalog(; domain = domain, terminal = :graphics)
            test_typein(ex.name, ex.make_document(), ex.make_projection())
        end
    end
end
