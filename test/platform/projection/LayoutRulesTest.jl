# The rules of `documentation/rule/layout-rules.md`, checked for every widget type
# and every layout type, and the worked cases of
# `plan/pending/a-maximum-is-an-edge-that-cuts.md` §3.3.
#
# Each type has a small sample with no authored size and no position, and a kind
# on each axis. The kind says what the type is, and the rule of the kind says what
# it draws in a range `(minimum, maximum)`; `N` is what it draws with no range:
#
# | kind         | exact (S, S) | bounded (0, L) | at least (M, ∅) | bounded (0, l), l < N |
# | ------------ | ------------ | -------------- | --------------- | --------------------- |
# | `:rigid`     | S            | N              | M               | N, and its giver cuts |
# | `:reflowing` | S            | N              | M               | at most l: it wraps   |
# | `:scrolls`   | S            | N              | M               | l, and it scrolls     |
# | `:fills`     | S            | N              | M               | N, and its giver cuts |
# | `:authored`  | N            | N              | N               | N                     |
# | `:overlay`   | N            | N              | N               | l: it caps            |
#
# where S, L and M are more than N. A kind that fills a slot, `:fills` and
# `:scrolls`, takes a slot that is less than N too, and cuts its content there. A type that is not placed alone has a reason
# instead of a sample, and a guard fails for a type that has neither.

_rules_projection() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FixedMeasure(10, 18, 6, 0)).dispatch))

_rules_cell(value) = value === nothing ? nothing : Cell(Int32(value))

# The range `(minimum, maximum)` on `axis`, and no range on the other axis. An
# exact range is one cell for both ends, which is what `get_exact_width` and
# `get_exact_height` read as a slot.
function _rules_context(axis::Symbol, minimum, maximum)
    if minimum !== nothing && minimum == maximum
        slot = _rules_cell(minimum)
        return axis === :width ? with_exact_size(PrinterContext(); width = slot) :
                                 with_exact_size(PrinterContext(); height = slot)
    end
    range = (_rules_cell(minimum), _rules_cell(maximum))
    axis === :width ? with_size_range(PrinterContext(); width = range) :
                      with_size_range(PrinterContext(); height = range)
end

# What `document` draws on `axis` in the range `(minimum, maximum)`.
function _rules_drawn(document, axis::Symbol, minimum, maximum)
    output = print_document(_rules_projection(), nothing, document, _rules_context(axis, minimum, maximum)).output
    axis === :width ? Int(output.w[]) : Int(output.h[])
end

# Words short enough that a text wraps at half of its width.
const _RULES_TEXT = join(fill("word", 12), " ")
_rules_lines(count) = VerticalLayout(Any[WidgetLabel("line $i") for i in 1:count])

# The sample and the kind on the width and on the height of each type, or the
# reason why the type is not placed alone.
const _RULES_KINDS = Dict{Symbol,Any}(
    :WidgetLabel        => (() -> WidgetLabel(_RULES_TEXT), :reflowing, :rigid),
    :WidgetText         => (() -> WidgetText("abc"), :rigid, :rigid),
    :WidgetSpinBox      => (() -> WidgetSpinBox(3), :rigid, :rigid),
    :WidgetList         => (() -> WidgetList(Any["a", "b", "c"]), :rigid, :scrolls),
    :WidgetCheckbox     => (() -> WidgetCheckbox("Check"), :authored, :authored),
    :WidgetButton       => (() -> WidgetButton("Go"), :rigid, :rigid),
    :WidgetLink         => (() -> WidgetLink("Link", EmptyReference()), :rigid, :rigid),
    :WidgetTooltip      => (() -> WidgetTooltip("Tip"), :overlay, :overlay),
    :WidgetContextMenu  => (() -> WidgetContextMenu(WidgetLabel("Target"), WidgetMenu(Any[WidgetMenuItem("Cut")])),
                            :overlay, :overlay),
    :WidgetDialog       => "a dialog is a window of its own",
    :WidgetMenu         => (() -> WidgetMenu(Any[WidgetMenuItem("Cut"), WidgetMenuItem("Copy")]), :overlay, :overlay),
    :WidgetMenuItem     => (() -> WidgetMenuItem("Cut"), :rigid, :rigid),
    :WidgetToolbarItem  => (() -> WidgetToolbarItem("Save"), :rigid, :rigid),
    :WidgetComposite    => (() -> WidgetComposite(Any[WidgetLabel("Inside")]), :rigid, :rigid),
    :WidgetToolbar      => (() -> WidgetToolbar(Any[WidgetToolbarItem("Save")]), :rigid, :rigid),
    :WidgetStatusBar    => (() -> WidgetStatusBar(Any["Ready"]), :rigid, :rigid),
    :WidgetShell        => (() -> WidgetShell(WidgetLabel("Inside")), :fills, :fills),
    :WidgetTitlePane    => (() -> WidgetTitlePane("Title", WidgetLabel("Inside")), :rigid, :rigid),
    :WidgetSplitPane    => (() -> WidgetSplitPane(:horizontal, Any[WidgetLabel("Left"), WidgetLabel("Right")]),
                            :fills, :fills),
    :WidgetTabLabel     => "a tab label is a part of a tabbed pane",
    :WidgetTabPage      => "a tab page is a part of a tabbed pane",
    :WidgetTabbedPane   => (() -> WidgetTabbedPane(Any[("One", WidgetLabel("Inside"))]), :fills, :fills),
    :WidgetScrollPane   => (() -> WidgetScrollPane(_rules_lines(6)), :scrolls, :scrolls),
    :WidgetTransformPane => (() -> WidgetTransformPane(_rules_lines(6); size = Point2D(0, 0)), :scrolls, :scrolls),
    :WidgetScrollBar    => (() -> WidgetScrollBar(:vertical), :fills, :fills),
    :WidgetBadge        => (() -> WidgetBadge("3"), :rigid, :rigid),
    :WidgetIconMark     => "an icon mark is a corner of an icon",
    :WidgetIcon         => (() -> WidgetIcon(:folder), :authored, :authored),
    :WidgetSeparator    => (() -> WidgetSeparator(), :authored, :authored),
    :WidgetCard         => (() -> WidgetCard(; title = "Title", content = _RULES_TEXT), :reflowing, :rigid),
    :WidgetSwitch       => (() -> WidgetSwitch(), :authored, :authored),
    :WidgetProgressBar  => (() -> WidgetProgressBar(0.5), :authored, :authored),
    :WidgetProgressRing => (() -> WidgetProgressRing(0.5), :rigid, :rigid),
    :WidgetSlider       => (() -> WidgetSlider(0.5), :authored, :authored),
    :WidgetRadioGroup   => (() -> WidgetRadioGroup(Any["a", "b"]), :rigid, :rigid),
    :WidgetAvatar       => (() -> WidgetAvatar("AB"), :authored, :authored),
    :WidgetAlert        => (() -> WidgetAlert("Title"; description = _RULES_TEXT), :reflowing, :rigid),
    :WidgetSkeleton     => (() -> WidgetSkeleton(), :authored, :authored),
    :WidgetSwatch       => (() -> WidgetSwatch(StyleColor(0.5, 0.5, 0.5, 1.0)), :authored, :authored),
    :WidgetHighlight    => (() -> WidgetHighlight(), :authored, :authored),
    :WidgetToggle       => (() -> WidgetToggle("B"), :rigid, :rigid),
    :WidgetToggleGroup  => (() -> WidgetToggleGroup(Any["a", "b"]), :rigid, :rigid),
    :WidgetSelect       => (() -> WidgetSelect("Apple"; options = Any["Apple", "Banana"]), :rigid, :rigid),
    :WidgetOption       => "an option is a row of the popup of a select",
    :WidgetTextarea     => (() -> WidgetTextarea("text"), :rigid, :authored),
    :WidgetAccordionItem => "an accordion item is a part of an accordion",
    :WidgetAccordion    => (() -> WidgetAccordion(Any[("Question", "Answer")]), :rigid, :rigid),
    :WidgetTable        => (() -> WidgetTable(Any["a", "b"], Any[Any["1", "2"], Any["3", "4"]]), :scrolls, :scrolls),
    :WidgetTree         => (() -> WidgetTree(Any[WidgetTreeNode(:file, "one"), WidgetTreeNode(:file, "two")]),
                            :scrolls, :scrolls),
    :WidgetInsertion    => "an insertion is a mark that a text puts between its characters",
    :HorizontalLayout   => (() -> HorizontalLayout(Any[WidgetLabel("Left"), WidgetLabel("Right")]; gap = 8), :rigid, :rigid),
    :VerticalLayout     => (() -> VerticalLayout(Any[WidgetLabel("Top"), WidgetLabel("Bottom")]; gap = 8), :rigid, :rigid),
    :GridLayout         => (() -> GridLayout(Any[WidgetLabel("R$(r)C$(c)") for r in 1:2 for c in 1:2], 2), :rigid, :rigid),
    :FlowLayout         => (() -> FlowLayout(Any[WidgetLabel(word) for word in split(_RULES_TEXT)]), :reflowing, :rigid),
    :StackLayout        => (() -> StackLayout(Any[WidgetLabel("Back"), WidgetLabel("Front")]), :rigid, :rigid),
    :ScrollLayout       => (() -> ScrollLayout(; center = WidgetLabel("Center"), left = WidgetLabel("1")), :rigid, :rigid),
    :AnchoredLayout     => "an anchored layout places its entries by the points of its content",
    :ConstraintLayout   => "a constraint layout sizes its children by its solver",
)

# Why a check of a type fails today, or `nothing`: the step of the plan that fixes it.
function _rules_broken(name::Symbol, kind::Symbol, axis::Symbol, check::Symbol)
    name === :WidgetTransformPane && check !== :bounded_more &&
        return "a transform pane with no size draws 0, and it stops at no maximum: step 6"
    kind === :scrolls && (check === :bounded_less || (check === :at_least_more && name === :WidgetTree)) &&
        return "a part that can scroll takes its content between its minimum and its maximum: step 6"
    nothing
end

# Every concrete type of the platform below `root`, by name. A `@document` type
# `Foo` has a native twin `MFoo`, which is the same type and is left out; so is a
# style, a `…Style`, which holds the colors of a widget and is not placed.
function _rules_leaf_types(root)
    names = Set{Symbol}(nameof(Base.unwrap_unionall(type)) for type in compute_concrete_subtypes(root)
                        if Base.moduleroot(parentmodule(type)) === ProjecturedPlatform)
    filter(name -> !(startswith(String(name), "M") && Symbol(String(name)[2:end]) in names) &&
                   !endswith(String(name), "Style"), names)
end

# The drawn extents of one sample on one axis, by the name of the check.
function _rules_measure(make, axis::Symbol)
    natural = _rules_drawn(make(), axis, nothing, nothing)
    more = natural + 200
    less = max(natural ÷ 2, 1)
    (natural = natural, more = more, less = less,
     exact_more = _rules_drawn(make(), axis, more, more),
     bounded_more = _rules_drawn(make(), axis, 0, more),
     at_least_more = _rules_drawn(make(), axis, more, nothing),
     bounded_less = _rules_drawn(make(), axis, 0, less),
     exact_less = _rules_drawn(make(), axis, less, less))
end

# What the rule of `kind` expects for each check, from the drawn extent with no range.
function _rules_expected(kind::Symbol, m)
    n = m.natural
    kind === :authored && return (exact_more = ==(n), bounded_more = ==(n), at_least_more = ==(n),
                                  bounded_less = ==(n), exact_less = ==(n))
    kind === :overlay && return (exact_more = ==(n), bounded_more = ==(n), at_least_more = ==(n),
                                 bounded_less = ==(m.less), exact_less = ==(m.less))
    stretched = (exact_more = ==(m.more), bounded_more = ==(n), at_least_more = ==(m.more))
    kind === :rigid && return (; stretched..., bounded_less = ==(n), exact_less = ==(n))
    kind === :reflowing && return (; stretched..., bounded_less = <=(m.less), exact_less = ==(m.less))
    kind === :scrolls && return (; stretched..., bounded_less = ==(m.less), exact_less = ==(m.less))
    kind === :fills && return (; stretched..., bounded_less = ==(n), exact_less = ==(m.less))
    error("no rule for the kind $kind")
end

function _rules_check_type(name::Symbol, make, kinds)
    for (axis, kind) in zip((:width, :height), kinds)
        m = _rules_measure(make, axis)
        for (check, expected) in pairs(_rules_expected(kind, m))
            drawn = getfield(m, check)
            reason = _rules_broken(name, kind, axis, check)
            @testset "$name $axis $kind $check" begin
                if reason === nothing
                    expected(drawn) || @info "layout rule" name axis kind check drawn m.natural m.more m.less
                    @test expected(drawn)
                else
                    # @broken: the reason names the step of the plan that fixes it.
                    @test_broken expected(drawn)
                end
            end
        end
    end
end

# A scroll area of `width × height` whose content grows on its height.
_rules_growing_area(content; width = 600, height = 300) =
    WidgetScrollPane(content; size = Point2D(width, height), grows = (width = false, height = true))

# What each child of the layout inside `area` draws, as (width, height).
function _rules_inner_extents(area)
    ctx = PrinterContext(EmptyReference(), Cell(Int32(1000)), Cell(Int32(1000)), Dict{Symbol,Any}())
    inner = print_document(_rules_projection(), nothing, area, ctx).content_iomap
    [(Int(last(e).output.w[]), Int(last(e).output.h[])) for e in getfield(inner, :child_iomaps)[]]
end

# What each child of `layout` draws on `axis` in the range `(minimum, maximum)` there.
function _rules_child_extents(layout, axis::Symbol, minimum, maximum)
    iomap = print_document(_rules_projection(), nothing, layout, _rules_context(axis, minimum, maximum))
    [axis === :width ? Int(last(e).output.w[]) : Int(last(e).output.h[])
     for e in getfield(iomap, :child_iomaps)[]]
end

# A lazy list of `count` rows of three labels, counting the rows that a walk builds.
function _rules_lazy_rows(count::Int, built::Ref{Int})
    function make_node(i)
        built[] += 1
        node = ListNode(Any[WidgetLabel("r$(i) c$(c)") for c in 1:3])
        set_cell_computation!(getfield(node, :next), () -> begin
            i < count || return nothing
            following = make_node(i + 1)
            set_cell_value!(getfield(following, :prev), node)
            following
        end)
        node
    end
    make_node(1)
end

"""
    test_layout_rules()

Every widget type and every layout type draws by the rule of its kind in each
range, and a guard fails for a type with no kind. The worked cases: a window that
cuts or scrolls, a column and a row that share a maximum alike and a minimum
alike, a part that fills in a scroll area, the detail of a task, a table of a
list in an area that grows, and a lazy grid in an area that grows.
"""
function test_layout_rules()
@testset "layout rules" begin
@testset "every widget type and every layout type has a kind" begin
    types = union(_rules_leaf_types(WidgetDocument), _rules_leaf_types(LayoutDocument))
    without_kind = setdiff(types, keys(_RULES_KINDS))
    without_type = setdiff(keys(_RULES_KINDS), types)
    isempty(without_kind) || @info "types with no kind: " * join(sort!(collect(without_kind)), " ")
    isempty(without_type) || @info "kinds with no type: " * join(sort!(collect(without_type)), " ")
    @test isempty(without_kind)
    @test isempty(without_type)
end

@testset "each type draws by the rule of its kind" begin
    for name in sort!(collect(keys(_RULES_KINDS)))
        entry = _RULES_KINDS[name]
        entry isa String && continue
        (make, width_kind, height_kind) = entry
        _rules_check_type(name, make, (width_kind, height_kind))
    end
end

# A fixed part A of 192 (8 lines) and a part B that can scroll, with 384 (16 lines).
window_parts() = Any[_rules_lines(8), WidgetScrollPane(_rules_lines(16))]

@testset "a window that cuts: B takes what A leaves, and scrolls" begin
    for (window, expected) in ((300, 108), (250, 58))
        (a, b) = _rules_child_extents(VerticalLayout(window_parts()), :height, window, window)
        @test a == 192
        # @broken: a part that can scroll stops at its maximum: step 6.
        @test_broken b == expected
    end
end

@testset "a window that scrolls: B keeps its content, and the window scrolls" begin
    for window in (300, 250)
        (a, b) = _rules_inner_extents(_rules_growing_area(VerticalLayout(window_parts()); height = window))
        @test (a[2], b[2]) == (192, 384)
    end
end

@testset "a column and a row share a range with a maximum alike" begin
    part(policy) = LayoutConstraint(WidgetScrollPane(WidgetLabel("part")); policy...)
    row = HorizontalLayout(Any[part((; width = Fixed(100))), part((; width = Fill))])
    @test _rules_child_extents(row, :width, 0, 300) == [100, 200]
    column = VerticalLayout(Any[part((; height = Fixed(100))), part((; height = Fill))])
    # @broken: a column shares only an exact height: step 5.
    @test_broken _rules_child_extents(column, :height, 0, 300) == [100, 200]
end

@testset "a column and a row share a minimum alike" begin
    part(policy) = LayoutConstraint(WidgetScrollPane(WidgetLabel("part")); policy...)
    row(policies...) = HorizontalLayout(Any[part(policy) for policy in policies])
    column(policies...) = VerticalLayout(Any[part(policy) for policy in policies])
    # Less content than the minimum: the part that fills takes the rest of it.
    @test _rules_child_extents(row((; width = Fixed(100)), (; width = Fill)), :width, 300, nothing) == [100, 200]
    @test _rules_child_extents(column((; height = Fixed(100)), (; height = Fill)), :height, 300, nothing) == [100, 200]
    # More content than the minimum: the part that fills keeps its content.
    content = (_rules_drawn(part((;)), :width, nothing, nothing), _rules_drawn(part((;)), :height, nothing, nothing))
    @test _rules_child_extents(row((; width = Fixed(400)), (; width = Fill)), :width, 300, nothing) == [400, content[1]]
    @test _rules_child_extents(column((; height = Fixed(400)), (; height = Fill)), :height, 300, nothing) == [400, content[2]]
    # On the cross axis, a part that fills takes at least the minimum.
    @test _rules_child_extents(row((; height = Fill)), :height, 300, nothing) == [300]
    @test _rules_child_extents(column((; width = Fill)), :width, 300, nothing) == [300]
end

@testset "a part that fills, in a scroll area" begin
    function column(lines)
        VerticalLayout(Any[_rules_lines(lines),
                           LayoutConstraint(WidgetScrollPane(WidgetLabel("fills")); height = Fill),
                           WidgetLabel("footer")])
    end
    # Short content: the part fills the rest of the view of 300.
    short = _rules_inner_extents(_rules_growing_area(column(2)))
    @test sum(e[2] for e in short) == 300
    # Long content: the column is as tall as its content, so the area scrolls to the footer.
    long = _rules_inner_extents(_rules_growing_area(column(40)))
    @test long[1][2] == 960
    @test sum(e[2] for e in long) >= 960 + 24
end

@testset "the detail of a task: the text gives up height, and the table keeps its minimum" begin
    table = WidgetTable(Any["a", "b"], Any[Any["$i", "$(i * i)"] for i in 1:30])
    detail = VerticalLayout(Any[WidgetScrollPane(_rules_lines(12)),
                                LayoutConstraint(table; height = Fill, min_height = 120)]; gap = 6)
    (text, rows) = _rules_child_extents(detail, :height, 400, 400)
    # @broken: a part that can scroll stops at its maximum: step 6.
    @test_broken text == 400 - 6 - 120
    @test_broken text + 6 + rows <= 400
end

@testset "a table of a list is as tall as the view of an area that fits or grows" begin
    columns = Any[WidgetTableColumn(; policy = Fixed(120)), WidgetTableColumn(; policy = Fixed(80))]
    for grows in (false, true)
        table = WidgetTable(; column_headers = Any["name", "value"],
                            cells = ListNode(make_widget_table_row(Any["a", "b"])), columns)
        area = WidgetScrollPane(table; size = Point2D(400, 200), grows = (width = false, height = grows))
        ctx = PrinterContext(EmptyReference(), Cell(Int32(1000)), Cell(Int32(1000)), Dict{Symbol,Any}())
        @test Int(print_document(_rules_projection(), nothing, area, ctx).content_iomap.output.h[]) == 200
    end
end

@testset "a lazy grid in an area that grows builds the rows that show" begin
    built = Ref(0)
    grid = GridLayout(_rules_lazy_rows(10_000_000, built), 3;
                      column_policies = Any[Fixed(90), Fixed(90), Fixed(90)])
    print_document(_rules_projection(), nothing, _rules_growing_area(grid; width = 400, height = 200),
                   PrinterContext(EmptyReference(), Cell(Int32(1000)), Cell(Int32(1000)), Dict{Symbol,Any}()))
    @test built[] < 30
end
end
end
