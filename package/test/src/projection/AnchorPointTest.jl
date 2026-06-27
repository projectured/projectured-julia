# Anchor resolution: `anchor_point` reuses `map_reference_forward` to resolve a
# document reference to the anchor widget's absolute graphics position. The forward
# image of a positioned widget is a `PointReference`; each container shifts only a
# coordinate result by where it placed the child (paths stay paths). Self-contained
# per projection, so widgets nest in any container and vice versa. Ground truth is
# walked directly from the output canvas tree.
function test_anchor_point()
@testset "anchor_point (forward-map to graphics coords)" begin

# Symbols resolve from the enclosing `ProjecturedTest` module's `using Projectured`
# / `using ProjecturedExample`; `Cell` is referenced fully-qualified.
proj = make_layout_projection_example()
mkbtn(w, h, label) = WidgetButton(Point2D(0, 0), Point2D(w, h), label;
                                  border=Inset(1, 1, 1, 1), padding=Inset(4, 4, 8, 8))

_gv(c, s) = (v = getfield(c, s); Int(v isa Projectured.ReactiveModule.Cell ? v[] : v))

# Absolute top-left of the canvas reached by descending `elements[idx]` for each
# index in `path` (1-based), summing every canvas origin along the way.
function abs_top_left(root::GraphicsCanvas, path)
    x = 0; y = 0; c = root
    for idx in path
        c = c.elements[idx]
        c isa Cell && (c = c[])
        x += _gv(c, :x); y += _gv(c, :y)
    end
    (x, y)
end

# children[i] (1-based i) as a document reference.
cref(steps...) = foldr((s, acc) -> ConcreteReferencePath(s, acc), steps; init=EmptyReferencePath())
child(i) = (FieldReference("children"), RangeReference(i - 1, i))
elem(i)  = (FieldReference("elements"), RangeReference(i - 1, i))
field(name) = (FieldReference(name),)

@testset "buttons in a VerticalLayout" begin
    doc = VerticalLayout(Any[mkbtn(120, 40, "A"), mkbtn(160, 50, "B"), mkbtn(100, 30, "C")];
                         gap=12, horizontal_align=:left)
    iomap = projection_print(proj, doc)
    for i in 1:3
        # Output: layout canvas -> wrapper(i) -> button canvas, i.e. elements[i]/elements[1].
        truth = abs_top_left(iomap.output, (i, 1))
        @test anchor_point(iomap, cref(child(i)...)) == truth
    end
    # An unresolvable reference yields nothing.
    @test anchor_point(iomap, cref(child(9)...)) === nothing
end

@testset "buttons in a WidgetComposite" begin
    doc = WidgetComposite(Point2D(0, 0), Any[mkbtn(80, 24, "x"), mkbtn(90, 26, "y")])
    iomap = projection_print(proj, doc)
    for i in 1:2
        truth = abs_top_left(iomap.output, (i, 1))
        @test anchor_point(iomap, cref(elem(i)...)) == truth
    end
end

@testset "composition across container types (layout > composite > button)" begin
    inner = WidgetComposite(Point2D(0, 0), Any[mkbtn(70, 22, "p"), mkbtn(70, 22, "q")])
    doc = VerticalLayout(Any[inner, mkbtn(100, 30, "tail")]; gap=8, horizontal_align=:left)
    iomap = projection_print(proj, doc)
    # children[1] = composite: layout-wrapper -> composite canvas -> composite-wrapper -> button.
    truth1 = abs_top_left(iomap.output, (1, 1, 1, 1))
    @test anchor_point(iomap, cref(child(1)..., elem(1)...)) == truth1
    truth2 = abs_top_left(iomap.output, (1, 1, 2, 1))
    @test anchor_point(iomap, cref(child(1)..., elem(2)...)) == truth2
end

# Step 4c: a horizontal WidgetMenu lays items left-to-right and forward-maps each
# `elements[i]` to its placed position, so a menu-bar entry's submenu anchor
# resolves.
@testset "menu-bar entries in a horizontal WidgetMenu" begin
    bar = WidgetMenu(Any[WidgetMenuItem("File"), WidgetMenuItem("Edit"), WidgetMenuItem("Help")];
                     orientation = :horizontal)
    iomap = projection_print(proj, bar)
    xs = Int[]; ys = Int[]
    for i in 1:3
        # menu canvas -> item wrapper(i) -> item canvas: elements[i]/elements[1].
        truth = abs_top_left(iomap.output, (i, 1))
        @test anchor_point(iomap, cref(elem(i)...)) == truth
        push!(xs, truth[1]); push!(ys, truth[2])
    end
    @test xs[1] < xs[2] < xs[3]      # laid out left-to-right
    @test ys[1] == ys[2] == ys[3]    # on a single row
    @test anchor_point(iomap, cref(elem(9)...)) === nothing
end

# Step 4c: the same entry resolves through a WidgetShell whose `menu_bar` is the
# horizontal menu — the shell descends `.menu_bar`, the menu descends `elements[i]`.
@testset "a menu-bar entry resolves through a WidgetShell" begin
    bar = WidgetMenu(Any[WidgetMenuItem("File"; submenu = WidgetMenu(Any[WidgetMenuItem("New")])),
                         WidgetMenuItem("Edit"),
                         WidgetMenuItem("Help")]; orientation = :horizontal)
    content = WidgetComposite(Point2D(0, 0), Any[mkbtn(80, 24, "x")])
    shell = WidgetShell(content; menu_bar = bar, size = Point2D(600, 400))
    iomap = projection_print(proj, shell)
    # Shell canvas: [background rect, menu_bar wrapper, …]. The menu-bar entry is
    # menu_bar-wrapper(2) -> menu canvas(1) -> item wrapper(i) -> item canvas(1).
    for i in 1:3
        truth = abs_top_left(iomap.output, (2, 1, i, 1))
        @test anchor_point(iomap, cref(field("menu_bar")..., elem(i)...)) == truth
    end
end

end # @testset
end # function
