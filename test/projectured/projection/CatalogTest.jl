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
    #   filter of a text, the view of a text and the gutter of a line: the same cause,
    #   no `recursion` for the text or the marks that they hold.
    "text/highlighted/", "text/filtered/", "text/view/", "text/gutter/",
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
                             "text/highlighted/", "text/filtered/", "text/view/", "text/gutter/",
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
                               "text/highlighted/", "text/filtered/", "text/view/", "text/gutter/")
_catalog_print_broken(name) =
    any(p -> occursin(p, name), _CATALOG_PRINT_BROKEN) ?
        (msg -> occursin("MethodError", msg) || occursin("FieldError", msg) ||
                occursin("TypeError", msg) || occursin("needs a recursion", msg)) : nothing

_catalog_seed_broken(name)   = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? (_errs -> true) : nothing
_catalog_throws_broken(name) = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? (_msg -> true) : nothing
# a per-state caret step whose selection can't re-apply (same broken entries).
_catalog_nav_state_broken(name) = any(p -> occursin(p, name), _CATALOG_NAV_BROKEN) ? ((_p, _msg) -> true) : nothing

# The known failures of the click test, by signature, as `find_part_click_mark` takes
# them: a kind of `classify_part_click_failure`, or a text of the line, and the
# examples where it is known. Each comment names the cause; a failure of another
# signature, or in another example, is a failure. Enumerate them with
# `grep "@click-broken"`.
const _CATALOG_CLICK_MARKS = (
    # @click-broken a plain click on a text that is no control does nothing: the view
    #   maps the point to no part, or to the part that was selected, such as a badge in
    #   the title of a card or a text that a view computes
    :plain_does_nothing => (
        "arrangement/document/natural", "assistant/work/natural",
          "backgroundwork/log/natural", "conversation/evaluator_form/natural",
          "explorer/explorer/natural", "fileformat/open_file_list/natural",
          "math/assignment/natural", "math/big_operator/natural",
          "math/binary_operation/natural", "math/case/natural", "math/cases/natural",
          "math/derivative/natural", "math/differential/natural", "math/function/natural",
          "math/matrix/natural", "math/parenthesized/natural", "math/radical/natural",
          "math/symbol/natural", "math/unary_operation/natural",
          "navigator/navigator/natural", "pivot/part_table/natural",
          "research/analysis/natural", "research/answer/natural",
          "research/decision/natural", "research/evidence/natural",
          "research/experiment/natural", "research/hypothesis/natural",
          "research/map/natural", "research/question/natural", "research/result/natural",
          "research/source/natural", "research/study/natural", "rst/section/natural",
          "systemprocess/tree/natural", "task/group/natural", "task/group_list/natural",
          "task/stream/natural", "task/task/natural", "widget/card/natural",
          "widget/choice_list/natural", "widget/dialog/natural",
          "widget/insertion/natural", "widget/select/natural", "widget/shell/natural",
          "widget/spin_box/natural", "widget/split_pane/natural",
          "widget/status_bar/natural", "widget/title_pane/natural",
          "widget/toggle_group/natural", "widget/tooltip/natural",
          "workflow/decision/natural", "workflow/entry/natural", "workflow/list/natural",
          "workflow/step/natural", "workflow/workflow/natural", "workplan/plan/natural",
    ),
    # @click-broken the caret of a plain click lies outside the innermost part that drew
    #   the text
    :plain_caret_outside => (
        "syntax/leaf/natural", "text/view/natural",
    ),
    # @click-broken an Alt+click on a text gives a whole part and no caret, because the
    #   view draws the text from a value that no field holds, such as a label that the
    #   view computes, a tick of an axis or a glyph that a view adds
    :alt_no_caret => (
        "arrangement/document/natural", "assistant/agent_work/natural",
          "assistant/work/natural", "backgroundwork/log/natural",
          "conversation/evaluator_form/natural", "conversation/evaluator_toplevel/natural",
          "explorer/explorer/natural", "fileformat/open_file_list/natural",
          "link/url/natural", "math/assignment/natural", "math/big_operator/natural",
          "math/binary_operation/natural", "math/case/natural", "math/cases/natural",
          "math/derivative/natural", "math/differential/natural", "math/function/natural",
          "math/matrix/natural", "math/parenthesized/natural", "math/radical/natural",
          "math/symbol/natural", "math/unary_operation/natural",
          "navigator/navigator/natural", "pivot/table/natural", "research/map/natural",
          "rst/section/natural", "statistics/frame_statistics/natural",
          "task/group/natural", "task/group_list/natural", "widget/card/natural",
          "widget/dialog/natural", "widget/insertion/natural", "widget/option/natural",
          "widget/radio_group/natural", "widget/select/natural", "widget/shell/natural",
          "widget/spin_box/natural", "widget/split_pane/natural",
          "widget/status_bar/natural", "widget/title_pane/natural",
          "widget/toggle/natural", "widget/tooltip/natural", "workflow/list/natural",
          "workplan/plan/natural",
    ),
    # @click-broken the caret of an Alt+click lies outside the innermost part that drew
    #   the text
    :alt_caret_outside => (
        "explorer/explorer/natural", "syntax/leaf/natural", "systemprocess/tree/natural",
          "text/view/natural", "tree/tree/natural", "widget/tabbed_pane/natural",
          "workplan/plan/natural",
    ),
    # @click-broken the caret of an Alt+click has no drawn image, because the forward
    #   map of the view takes no caret in that text
    :alt_caret_not_drawn => (
        "explorer/explorer/natural", "fileformat/open_file_list/natural",
          "mcplog/log/natural", "pivot/table/natural", "widget/choice_list/natural",
          "widget/text/natural", "widget/textarea/natural", "workflow/step/natural",
    ),
    # @click-broken an Alt+double click selects a part around the innermost part that
    #   drew the point, because the view names a whole row, card or page there
    :double_outside => (
        "arrangement/document/natural", "backgroundwork/log/natural",
          "book/paragraph/natural", "explorer/explorer/natural", "graph/graph/natural",
          "graphics/canvas/natural", "graphics/rect/natural", "pane/group/natural",
          "pane/split/natural", "research/map/natural", "systemprocess/tree/natural",
          "task/group/natural", "text/view/natural", "tree/tree/natural",
          "widget/dialog/natural", "widget/split_pane/natural",
          "widget/tabbed_pane/natural", "widget/title_pane/natural",
          "workplan/plan/natural",
    ),
    # @click-broken an Alt+double click selects a part that does not hold the caret of
    #   the Alt+click
    :double_not_caret_part => (
        "book/paragraph/natural", "fileformat/view/natural", "pivot/part_table/natural",
          "pivot/table/natural", "rst/directive_option/natural",
          "statistics/frame_statistics/natural",
    ),
    # @click-broken a whole part that a view drew shows no ring or band when an
    #   Alt+double click selects it, because a part that a projection step names draws
    #   no mark (the plan "a projection step evaluates to what it names")
    :double_not_drawn => (
        "assistant/list/natural", "assistant/terminal_command/natural",
          "backgroundwork/log/natural", "explorer/dashboard/natural",
          "explorer/explorer/natural", "explorer/search/natural",
          "explorer/section/natural", "fileformat/open_file_list/natural",
          "fileformat/view/natural", "filesystem/directory/natural",
          "filesystem/file/natural", "formula/environment/natural", "graph/graph/natural",
          "help/entry/natural", "math/fraction/natural", "mcplog/log/natural",
          "pane/group/natural", "pane/split/natural", "pivot/part_table/natural",
          "pivot/table/natural", "roster/roster/natural",
          "statistics/frame_statistics/natural", "task/execution/natural",
          "task/group/natural", "task/group_list/natural", "task/task/natural",
          "tooltip/content/natural", "widget/choice_list/natural", "widget/dialog/natural",
          "widget/menu/natural", "widget/menu_item/natural", "widget/scroll_pane/natural",
          "widget/shell/natural", "widget/split_pane/natural",
          "widget/tabbed_pane/natural", "widget/toolbar/natural",
          "widget/toolbar_item/natural", "widget/transform_pane/natural",
          "workflow/list/natural", "workspace/folder/natural",
    ),
    # @click-broken a move names another part than the Alt+double click selects, because
    #   the view names the part under the pointer by a rule of its own, such as a scroll
    #   bar or the edge of a column of a data frame, which have no part in the view
    :move_differs => (
        "appearance/appearance/natural", "assistant/agent_work/natural",
          "assistant/work/natural", "backgroundwork/log/natural", "book/paragraph/natural",
          "explorer/explorer/natural", "filesystem/directory/natural",
          "graph/graph/natural", "mcplog/log/natural", "pane/group/natural",
          "pane/split/natural", "pivot/part_table/natural", "pivot/table/natural",
          "research/map/natural", "research/study/natural", "roster/roster/natural",
          "statistics/frame_statistics/natural", "task/group/natural",
          "task/group_list/natural", "task/stream/natural", "task/task/natural",
          "widget/dialog/natural", "widget/scroll_pane/natural",
          "widget/split_pane/natural", "widget/tabbed_pane/natural",
          "widget/title_pane/natural", "widget/toggle_group/natural",
          "workflow/journal/natural", "workflow/list/natural", "workplan/plan/natural",
          "workspace/folder/natural",
    ),
    # @click-broken the document has no forward image in the window, so the walk presses
    #   no element
    :no_image => (
        "arrangement/chips/natural", "assistant/assistant/natural", "book/book/natural",
          "book/chapter/natural", "book/list/natural", "filesystem/chooser/natural",
          "inspector/selection/natural", "markdown/image/natural", "markdown/text/natural",
          "pivot/chart_cell/natural", "rst/text/natural", "settings/settings/natural",
          "statistics/frame_time_series/natural", "terminal/terminal/natural",
          "widget/reference_inspector/natural", "workspace/explorer/natural",
          "workspace/workspace/natural",
    ),
    # @click-broken the natural view of the example draws no element in the window, so
    #   the walk presses none: an empty part of Julia code draws nothing by design; the
    #   other four are not studied
    :no_element => (
        "collection/list_node/natural", "julia/empty/natural", "julia/insertion/natural",
          "math/space/natural", "widget/progress_ring/natural",
    ),
    # @click-broken a press takes the document out of the editor, so the walk stops
    #   there; not studied
    :press_removes_document => (
        "arrangement/document/natural",
    ),
    # @click-broken the natural view of a screen document draws a canvas, and the walk
    #   reads the windows of a screen
    "throws FieldError: type ProjecturedPlatform.GraphicsModule.GraphicsCanvas has no field `windows`" => (
        "widget/screen_document/natural",
    ),
    # @click-broken the natural view of a lone span or a gutter of a text wraps it in
    #   WordWrapping, which prints only a block, so the example does not build
    "throws MethodError: no method matching print_document(::ProjecturedPlatform.TextModule.WordWrapping" => (
        "text/bare_graphics/natural", "text/bare_line/natural",
          "text/bare_spacing/natural", "text/bare_string/natural", "text/gutter/natural",
    ),
)
_catalog_click_broken(name) = find_part_click_mark(_CATALOG_CLICK_MARKS, name)

# The atoms whose click walk does not end in the memory of a worker.
# @click-broken task/stream_lines: the walk of 200 points needs 9 GiB (step 1 of the
#   plan "a click reaches the innermost part in every view").
const _CATALOG_CLICK_ENDLESS = ("task/stream_lines/natural",)

# The known failures of the catalog by the kind of tester, as `test_catalog_examples`
# takes them.
const _CATALOG_MARKS = (print = _catalog_print_broken, edit = _catalog_edit_broken,
                        seed = _catalog_seed_broken, throws = _catalog_throws_broken,
                        state = _catalog_nav_state_broken, click = _catalog_click_broken)

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
                        only_runnable = false, testers = CATALOG_TESTERS, only = nothing, skip = nothing)
    test_catalog_examples(select_by_name(catalog(; domain, document, terminal, only_runnable);
                                         only, skip); testers,
                          marks = _CATALOG_MARKS)
end

# The groups of domains of the parts of the click test of the catalog, each about ten
# minutes of a walk in a process alone (2026-11-26). One more part takes every other
# domain, so a new domain has its part.
const _CATALOG_CLICK_GROUPS = (
    ("appearance",),
    ("widget", "pane", "layout", "tooltip", "dragging", "dragtracking", "gesture", "gesturetracking"),
    ("fsm", "process"),
    ("julia", "rst", "xml", "json", "yaml", "syntax"),
    ("sql", "graph", "dbcatalog", "database", "markdown"),
    ("research", "assistant", "conversation", "task", "workflow"),
)

"""
    make_catalog_click_parts() -> Vector{TestPart}

The parts of the suite that run [`test_catalog_clicks`](@ref): one for each group of
`_CATALOG_CLICK_GROUPS`, and one for every other domain.
"""
function make_catalog_click_parts()
    pattern(domains) = Regex("^(" * join(domains, "|") * ")/")
    parts = [TestPart(() -> test_catalog_clicks(; only = pattern(group));
                      name = "test_catalog_clicks($(join(group, ", ")))", level = :slow, limit = 1800)
             for group in _CATALOG_CLICK_GROUPS]
    others = pattern(Iterators.flatten(_CATALOG_CLICK_GROUPS))
    push!(parts, TestPart(() -> test_catalog_clicks(; skip = others);
                          name = "test_catalog_clicks(other domains)", level = :slow, limit = 1800))
    parts
end

"""
    test_catalog_clicks(; only = nothing, skip = nothing)

The click test (`test_part_click`) over the variant of the app, `:natural`, of each
atom of the catalog: a plain click, an Alt+click, an Alt+double click and a move on
each drawn element reach the innermost part, with the known failures of this file.
The suite runs it in parts, each over a group of domains, so each part ends in its
limit.
"""
function test_catalog_clicks(; only = nothing, skip = nothing)
    examples = select_by_name(catalog(; terminal = :natural, natural = true); only, skip)
    @testset "CatalogClicks" begin
        test_catalog_examples(filter(example -> !(example.name in _CATALOG_CLICK_ENDLESS), examples);
                              testers = (test_part_click,), marks = _CATALOG_MARKS)
        for example in examples
            example.name in _CATALOG_CLICK_ENDLESS || continue
            @testset "$(example.name)" begin
                @test_broken false
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
function test_catalog_typeins(; domain = :text, only = nothing, skip = nothing)
    @testset "CatalogTypeins" begin
        for ex in select_by_name(catalog(; domain = domain, terminal = :graphics); only, skip)
            test_typein(ex.name, ex.make_document(), ex.make_projection())
        end
    end
end
