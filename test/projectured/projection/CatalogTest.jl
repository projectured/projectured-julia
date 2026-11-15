# ═══════════════════════════════════════════════════════════════════════════
# test/projection/CatalogTest.jl
#
# Run the *existing* example-testers over the generated catalog
# (ProjecturedExample.catalog()). Each tester declares the terminal domain it
# needs; a catalog `Example` carries its `terminal`; applicability is the lookup.
# No new tester logic — this only routes catalog Examples to the right testers,
# so the scattered skip-lists dissolve. See plan/pending/discovered-example-catalog.md.
# ═══════════════════════════════════════════════════════════════════════════

# The testers, the terminals that each applies to and the routing of an example to a
# tester are in `test_catalog_examples` of `ProjecturedPlatformTest`; this file holds the
# known failures of the catalog of this repository and its entry point.

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
    # @catalog-broken the views of a text that hold a document, a highlight and a
    #   filter of a text and the gutter of a line: the same cause, no `recursion`
    #   for the text or the marks that they hold.
    "text/highlighted/", "text/filtered/", "text/gutter/",
    # @catalog-broken bare text spans: `WordWrapping` is block-level and has no
    #   method for a lone `TextString`/`TextLine`.
    "text/bare_string/", "text/bare_line/", "text/bare_spacing/", "text/bare_graphics/",
)
# @catalog-broken widget/link: a click opens the target of the link as a page, and the
#   stand-in editor of the REPL walk holds no pane tree to open it in, so `open_pane!`
#   throws that no pane tree has the focus.
const _CATALOG_EDIT_NO_PANE = ("widget/link/",)
_catalog_edit_broken(name) =
    any(p -> occursin(p, name), _CATALOG_EDIT_NO_PANE) ?
        ((ev, msg) -> occursin("no pane tree has the focus", msg)) :
    any(p -> occursin(p, name), _CATALOG_EDIT_BROKEN) ?
        ((ev, msg) -> occursin("FieldError", msg) || occursin("MethodError", msg) ||
                      occursin("TypeError", msg) || occursin("under-typed", msg) ||
                      occursin("needs a recursion", msg)) : nothing

# Entries whose position-navigation still fails — the seed can't produce a caret, or the walk
# throws (an under-typed @reference / a TypeError in a node's backward map / selection maps).
# @catalog-broken yaml/sequence: graphics Ctrl+Home seed returns nothing (0 states).
# @catalog-broken filesystem/directory: under-typed @reference on the walk.
# @catalog-broken sql/where_filter_condition: TypeError (SyntaxNavigation) on the walk.
# @catalog-broken inspector/selection, projection/fault_report: a view that a person
#   reads and does not edit, so Ctrl+Home finds no caret to seed (0 states).
# @catalog-broken julia/empty: renders to nothing, so there is no caret to seed (0 states).
#   Arguably not a bug — `JuliaEmpty` is the absent return type of a function that
#   declares none, and absent is what it should draw. It is marked rather than
#   skipped because the atom still has to be printed and read like any other, and
#   because "a document that renders empty" is a case the caret motion may one
#   day want an answer for.
# @catalog-broken the layouts, the widget composite, the views of a text that hold
#   a document, the bare text spans and the embed stub: same three causes as the edit set above (no recursion standalone,
#   no block for the wrapper to wrap, no selection field), which leave the walk
#   with no caret to seed.
const _CATALOG_NAV_BROKEN = ("yaml/sequence/", "filesystem/directory/",
                             "sql/where_filter_condition/",
                             "julia/empty/",
                             "layout/", "widget/composite/",
                             "widget/reference_inspector/", "graph/layout/",
                             "text/bare_string/", "text/bare_line/",
                             "text/bare_spacing/", "text/bare_graphics/",
                             "text/highlighted/", "text/filtered/", "text/gutter/",
                             "inspector/selection/", "projection/fault_report/")
# Entries whose PRINTER cannot force its own output. Distinct from the edit set:
# these fail before any gesture, when the walk reads the cells the printer built.
# @catalog-broken layouts / widget composite / graph layout / the views of a text
#   that hold a document: no `recursion` in a single-step projection, so a child
#   has no `print_document` method.
# @catalog-broken text/bare_*: `WordWrapping` is block-level and has no method for
#   a lone span, so the derived `:graphics` variant cannot be forced. The `:text`
#   variant — the one these atoms exist for — prints fine.
const _CATALOG_PRINT_BROKEN = ("layout/", "widget/composite/",
                               "widget/reference_inspector/", "graph/layout/",
                               "text/bare_string/", "text/bare_line/",
                               "text/bare_spacing/", "text/bare_graphics/",
                               "text/highlighted/", "text/filtered/", "text/gutter/")
_catalog_print_broken(name) =
    any(p -> occursin(p, name), _CATALOG_PRINT_BROKEN) ?
        (msg -> occursin("MethodError", msg) || occursin("FieldError", msg) ||
                occursin("TypeError", msg) || occursin("needs a recursion", msg)) : nothing

_catalog_seed_broken(name)   = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? (_errs -> true) : nothing
_catalog_throws_broken(name) = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? (_msg -> true) : nothing
# a per-state caret step whose selection can't re-apply (same broken entries).
_catalog_nav_state_broken(name) = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? ((_p, _msg) -> true) : nothing

# The known failures of the catalog by the kind of tester, as `test_catalog_examples`
# takes them.
const _CATALOG_MARKS = (print = _catalog_print_broken, edit = _catalog_edit_broken,
                        seed = _catalog_seed_broken, throws = _catalog_throws_broken,
                        state = _catalog_nav_state_broken)

"""
    test_catalog(; domain=nothing, document=nothing, terminal=nothing, only_runnable=false,
                   testers=CATALOG_TESTERS)

Run each applicable tester over the discovered example catalog of this repository,
filtered by `domain` / `document` / `terminal` / `only_runnable`, with the known failures
of this file. `test_catalog_examples` decides for each `Example` by its `terminal` field
which testers apply — a `:syntax` pair runs printer/reader/repl but not
position-navigation (which needs a `:graphics` terminal) — so no skip-lists are needed.
"""
function test_catalog(; domain = nothing, document = nothing, terminal = nothing,
                        only_runnable = false, testers = CATALOG_TESTERS)
    test_catalog_examples(catalog(; domain, document, terminal, only_runnable); testers,
                          marks = _CATALOG_MARKS)
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
