# The space that a slot gives. The tab page and each slot of a split pane give
# `slot_padding` to what they hold. The first box in the slot takes it outside its
# edge and offers 0 to what it holds, a layout passes it to the children at its
# sides, the frame takes none, and a card gives none to its body.

const _SS_MEASURE = FixedMeasure(10, 18, 6, 0)
const _SS_SPACE = (8, 6, 4, 2)

_ss_projection() = RecursiveProjection(WidgetToGraphics(; measure = _SS_MEASURE,
                                                        text = TextToGraphics(measure = _SS_MEASURE)))

# A bounded offer of 600 by 400 with `space` around the child: a widget takes what
# it needs, so its extent shows the space.
_ss_offer(space) = with_bounded_size(PrinterContext(EmptyReference(), nothing, nothing, Dict{Symbol,Any}());
                                     width = Cell(Int32(600)), height = Cell(Int32(400)), space)

# An exact offer of 600 by 400, as the root of a window gives.
_ss_slot() = PrinterContext(EmptyReference(), Cell(Int32(600)), Cell(Int32(400)), Dict{Symbol,Any}())

_ss_extent(iomap) = (Int(iomap.output.w), Int(iomap.output.h))

_ss_space(iomap) = WidgetModule._get_box_geometry(iomap).space

# The slot padding of the default theme, `(left, top, right, bottom)`.
function _ss_slot_padding()
    inset = get_theme_defaults(WidgetTheme).slot_padding
    (Int(inset.left[]), Int(inset.top[]), Int(inset.right[]), Int(inset.bottom[]))
end

# The IO maps below `iomap` whose input is `document`, found by a walk of the
# child IO maps.
function _ss_find_iomaps(iomap, document)
    found = Any[]
    function visit(node)
        node === nothing && return
        get_iomap_input(node) === document && push!(found, node)
        children = get_child_iomaps(node)
        children === nothing && return
        for child in children
            visit(child)
        end
    end
    visit(iomap)
    found
end

# One widget of each type of the widget dispatch that takes the space as a box.
function _ss_box_samples()
    select = WidgetSelect("a"; options = Any["a", "b"])
    Any[WidgetInsertion(), WidgetLabel("name"), WidgetText("text"), WidgetCheckbox(false; label = "on"),
        WidgetButton("Run"), WidgetLink("link", EmptyReference()), WidgetTooltip("tip"),
        WidgetContextMenu(WidgetLabel("item"), WidgetMenu(Any[WidgetMenuItem("Copy")])),
        WidgetMenu(Any[WidgetMenuItem("Copy")]), WidgetMenuItem("Copy"), WidgetToolbarItem("Go"),
        WidgetComposite(Any[WidgetLabel("held")]), WidgetTitlePane("Title", WidgetLabel("body")),
        WidgetScrollPane(WidgetLabel("held")), WidgetTransformPane(WidgetLabel("held"); size = Point2D(120, 60)),
        WidgetToolbar(Any[WidgetToolbarItem("Go")]), WidgetStatusBar(Any["ready"]),
        WidgetScrollBar(:vertical), WidgetBadge("3"), WidgetIcon(:plus), WidgetSeparator(),
        WidgetCard(; title = "Card", content = WidgetLabel("body")), WidgetSwitch(; label = "on"),
        WidgetProgressBar(0.5), WidgetProgressRing(0.5), WidgetSlider(0.5), WidgetRadioGroup(Any["a", "b"]),
        WidgetAvatar("AB"), WidgetAlert("Alert"), WidgetSkeleton(), WidgetSwatch(color_solarized_blue),
        WidgetHighlight(), WidgetToggle("bold"), WidgetToggleGroup(Any["a", "b"]), select,
        WidgetSpinBox(3), WidgetList(Any["first", "second"]), WidgetOption(select, "a"),
        WidgetTextarea("text"), WidgetAccordion(Any[("Title", "body")]),
        WidgetTable(Any["a"], Any[Any["1"]]), WidgetTree(Any[WidgetTreeNode(nothing, "root")])]
end

# The widgets of the frame: they reach the edges of their slot and take no space.
_ss_frame_samples() =
    Any[WidgetShell(WidgetLabel("content")), WidgetSplitPane(:horizontal, Any[WidgetLabel("a"), WidgetLabel("b")]),
        WidgetTabbedPane(Any[("One", WidgetLabel("page"))]),
        WidgetDialog("Title", WidgetLabel("content"), Any[WidgetButton("OK")])]

function test_slot_space()
@testset "the space that a slot gives" begin
    projection = _ss_projection()
    print_sample(sample, ctx) = print_document(projection, nothing, sample, ctx)

    @testset "each printer of the widget dispatch takes the space or is a part of the frame" begin
        types = Set{Symbol}(nameof(first(rule)) for rule in WidgetToGraphics(; measure = _SS_MEASURE).dispatch)
        covered = Set{Symbol}(nameof(typeof(sample)) for sample in vcat(_ss_box_samples(), _ss_frame_samples()))
        layouts = Set{Symbol}(nameof(first(rule)) for rule in LayoutToGraphics().dispatch)
        @test setdiff(types, covered, layouts) == Set{Symbol}()
    end

    @testset "a box takes the space outside its edge: $(nameof(typeof(sample)))" for sample in _ss_box_samples()
        bare = print_sample(sample, _ss_offer((0, 0, 0, 0)))
        spaced = print_sample(sample, _ss_offer(_SS_SPACE))
        left, top, right, bottom = _SS_SPACE
        width, height = _ss_extent(bare)
        if sample isa WidgetScrollPane
            # A scroll pane takes the space inside its border, as a part of its padding.
            box, bare_box = WidgetModule._get_box_geometry(spaced), WidgetModule._get_box_geometry(bare)
            @test box.space == (0, 0, 0, 0)
            @test box.padding == bare_box.padding .+ _SS_SPACE
            @test _ss_extent(spaced) == (width + left + right, height + top + bottom)
        elseif sample isa Union{WidgetTree, WidgetList}
            # A tree and a list take the space at the top and at the bottom, and
            # their rows take the side space as their side padding.
            @test _ss_space(spaced) == (0, top, 0, bottom)
            @test _ss_extent(spaced)[2] == height + top + bottom
        elseif sample isa WidgetScrollBar
            @test _ss_space(spaced) == _SS_SPACE
            @test _ss_extent(spaced)[1] == width + left + right
        else
            @test _ss_space(spaced) == _SS_SPACE
            @test _ss_extent(spaced) == (width + left + right, height + top + bottom)
        end
    end

    @testset "the frame takes no space: $(nameof(typeof(sample)))" for sample in _ss_frame_samples()
        @test _ss_space(print_sample(sample, _ss_offer(_SS_SPACE))) == (0, 0, 0, 0)
    end

    @testset "a box offers 0 to what it holds" begin
        held = WidgetLabel("held")
        card = WidgetCard(; title = "Card", content = held)
        iomap = print_sample(card, _ss_offer(_SS_SPACE))
        @test _ss_space(only(_ss_find_iomaps(iomap, held))) == (0, 0, 0, 0)
        pane_held = WidgetLabel("held")
        iomap = print_sample(WidgetScrollPane(pane_held), _ss_offer(_SS_SPACE))
        @test _ss_space(only(_ss_find_iomaps(iomap, pane_held))) == (0, 0, 0, 0)
    end

    @testset "the page of a tab gives the slot padding to what it holds, and a card in it none" begin
        page = WidgetLabel("page")
        iomap = print_sample(WidgetTabbedPane(Any[("One", page)]), _ss_slot())
        label = only(_ss_find_iomaps(iomap, page))
        @test _ss_space(label) == _ss_slot_padding()
        # The text stands the slot padding inside the edges of the page.
        text = only(element for element in label.output.elements if element isa GraphicsText)
        @test (Int(text.x), Int(text.y)) == WidgetModule._get_content_offset(WidgetModule._get_box_geometry(label))
        body = WidgetLabel("body")
        card = WidgetCard(; content = body)
        iomap = print_sample(WidgetTabbedPane(Any[("One", card)]), _ss_slot())
        @test _ss_space(only(_ss_find_iomaps(iomap, card))) == _ss_slot_padding()
        @test _ss_space(only(_ss_find_iomaps(iomap, body))) == (0, 0, 0, 0)
    end

    @testset "each slot of a split pane gives the slot padding" begin
        first_label, second_label = WidgetLabel("a"), WidgetLabel("b")
        iomap = print_sample(WidgetSplitPane(:horizontal, Any[first_label, second_label]), _ss_slot())
        @test _ss_space(only(_ss_find_iomaps(iomap, first_label))) == _ss_slot_padding()
        @test _ss_space(only(_ss_find_iomaps(iomap, second_label))) == _ss_slot_padding()
    end

    @testset "a layout passes the space to the children at its sides" begin
        left, top, right, bottom = _SS_SPACE
        labels = Any[WidgetLabel("a"), WidgetLabel("b"), WidgetLabel("c")]
        iomap = print_sample(VerticalLayout(labels), _ss_offer(_SS_SPACE))
        @test [_ss_space(only(_ss_find_iomaps(iomap, label))) for label in labels] ==
              [(left, top, right, 0), (left, 0, right, 0), (left, 0, right, bottom)]
        labels = Any[WidgetLabel("a"), WidgetLabel("b"), WidgetLabel("c")]
        iomap = print_sample(HorizontalLayout(labels), _ss_offer(_SS_SPACE))
        @test [_ss_space(only(_ss_find_iomaps(iomap, label))) for label in labels] ==
              [(left, top, 0, bottom), (0, top, 0, bottom), (0, top, right, bottom)]
        labels = Any[WidgetLabel("a"), WidgetLabel("b"), WidgetLabel("c"), WidgetLabel("d")]
        iomap = print_sample(GridLayout(labels, 2), _ss_offer(_SS_SPACE))
        @test [_ss_space(only(_ss_find_iomaps(iomap, label))) for label in labels] ==
              [(left, top, 0, 0), (0, top, right, 0), (left, 0, 0, bottom), (0, 0, right, bottom)]
        # The children of a stack overlap, so each one gets the whole space.
        labels = Any[WidgetLabel("a"), WidgetLabel("b")]
        iomap = print_sample(StackLayout(labels), _ss_offer(_SS_SPACE))
        @test [_ss_space(only(_ss_find_iomaps(iomap, label))) for label in labels] == [_SS_SPACE, _SS_SPACE]
        # A flow takes the space around itself.
        labels = Any[WidgetLabel("a"), WidgetLabel("b")]
        bare = print_sample(FlowLayout(labels), _ss_offer((0, 0, 0, 0)))
        spaced = print_sample(FlowLayout(labels), _ss_offer(_SS_SPACE))
        @test [_ss_space(only(_ss_find_iomaps(spaced, label))) for label in labels] == [(0, 0, 0, 0), (0, 0, 0, 0)]
        @test _ss_extent(spaced) == _ss_extent(bare) .+ (left + right, top + bottom)
        # A constraint around a child passes the whole offer on.
        held = WidgetLabel("held")
        iomap = print_sample(LayoutConstraint(held), _ss_offer(_SS_SPACE))
        @test _ss_space(only(_ss_find_iomaps(iomap, held))) == _SS_SPACE
    end

    @testset "a text takes the space as a box, and its readers read the space" begin
        text = TextToGraphics(measure = _SS_MEASURE)
        block = TextBlock(TextLine(TextString("words")))
        bare = print_document(text, nothing, block, _ss_offer((0, 0, 0, 0)))
        spaced = print_document(text, nothing, block, _ss_offer(_SS_SPACE))
        left, top, right, bottom = _SS_SPACE
        @test spaced.space == _SS_SPACE
        @test _ss_extent(spaced) == _ss_extent(bare) .+ (left + right, top + bottom)
        # A press at the start of the word in the canvas puts the caret before the
        # first character, inside the space.
        caret = map_reference_backward(text, spaced, PointReferenceStep(left + 1, top + 1))
        @test caret == map_reference_backward(text, bare, PointReferenceStep(1, 1))
    end
end
end
