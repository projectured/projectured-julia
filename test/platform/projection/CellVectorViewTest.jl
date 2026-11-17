# The view of a list: a list of the views of the elements of its content. The list
# view makes the view of an element at the first read of that element, and the
# view follows its element.

function test_cell_vector_view()
@testset "CellVectorView" begin

leaf(s) = SyntaxLeaf(TextString(s))
leaf_a, leaf_b, leaf_c = leaf("a"), leaf("b"), leaf("c")
list = CellVector(Document[leaf_a, leaf_b, leaf_c])
view = CellVectorView(list)
index_step(i) = RangeReferenceStep(i - 1, i)
# The views that exist, as the pairs of an index and a view.
existing(v) = [(step.stop, child) for (step, child) in child_reference_steps(v)]
# Whether `pairs` holds the indexes and the same views as `expected`, in its order.
same(pairs, expected) = length(pairs) == length(expected) &&
    all(i -> pairs[i][1] == expected[i][1] && pairs[i][2] === expected[i][2], eachindex(pairs))

@testset "A list view is the view of its list" begin
    @test view isa ContentView && view.viewed === list
    @test make_content_view(list) isa CellVectorView && make_content_view(list).viewed === list
    @test is_element_collection(view)
    # A paste asks the owner of a list of any type, and a view owns no place.
    @test find_declared_element_type(view) === Any
    @test !is_admitted_by_declared_type(view, find_declared_element_type(view), SyntaxLeafView(leaf_a))
end

@testset "A read of the length makes no view" begin
    @test length(view) == 3 && !isempty(view)
    @test firstindex(view) == 1 && lastindex(view) == 3 && collect(eachindex(view)) == [1, 2, 3]
    @test isempty(existing(view))
end

@testset "A read of an element makes the view of that element, and no other" begin
    second = view[2]
    @test second isa SyntaxLeafView && second.viewed === leaf_b
    @test same(existing(view), [(2, second)])
    @test view[2] === second
    @test same(existing(view), [(2, second)])
end

@testset "A path with an index step reaches the view of the element" begin
    second = view[2]
    @test try_evaluate_reference(view, Reference(index_step(2)), nothing) === second
    third = try_evaluate_reference(view, Reference(index_step(3)), nothing)
    @test third isa SyntaxLeafView && third.viewed === leaf_c
    @test same(existing(view), [(2, second), (3, third)])
    @test try_evaluate_reference(view, Reference(index_step(4)), nothing) === nothing
end

@testset "The caret of a path goes into the view of the element" begin
    second = view[2]
    in_leaf = strip_reference_types(@reference(second, value{1}))
    caret = concat_references(Reference(index_step(2)), in_leaf)
    replace_selection!(view, caret)
    @test strip_reference_types(get_stored_selection(view)) == caret
    @test strip_reference_types(get_stored_selection(second)) == in_leaf
    @test get_stored_selection(leaf_b) === nothing
    third = view[3]
    set_selection!(view, concat_references(Reference(index_step(3)), in_leaf))
    @test strip_reference_types(get_stored_selection(third)) == in_leaf
    @test get_stored_selection(leaf_c) === nothing
    clear_selection!(view)
end

@testset "The view of an element follows its element" begin
    second = view[2]
    insert!(list, 1, leaf("z"))
    @test length(view) == 4
    @test view[3] === second
    @test any(pair -> pair[1] == 3 && pair[2] === second, existing(view))
    deleteat!(list, 1)
    @test view[2] === second
    deleteat!(list, 1)
    @test view[1] === second && second.viewed === leaf_b
end

@testset "An element that has no view type has no view" begin
    mixed = CellVector(Document[leaf_a, TextString("plain")])
    mixed_view = CellVectorView(mixed)
    @test mixed_view[2] === nothing
    @test isempty(existing(mixed_view))
    @test mixed_view[1] isa SyntaxLeafView
    @test [index for (index, _) in existing(mixed_view)] == [1]
end

@testset "A loop gives the view of each element, in the order of the elements" begin
    looped = CellVectorView(CellVector(Document[leaf_a, leaf_b, leaf_c]))
    views = collect(looped)
    @test length(views) == 3 && all(v -> v isa SyntaxLeafView, views)
    @test all(i -> views[i].viewed === (leaf_a, leaf_b, leaf_c)[i], 1:3)
    @test all(i -> looped[i] === views[i], 1:3)
    @test all(map(===, looped[2:3], views[2:3]))
end

@testset "A list view with given views answers them and makes none" begin
    one = SyntaxLeafView(leaf_a)
    given = CellVector(Any[one, nothing])
    given_view = CellVectorView(CellVector(Document[leaf_a, leaf_b]), given)
    @test length(given_view) == 2
    @test given_view[1] === one && given_view[2] === nothing
    @test same(existing(given_view), [(1, one)])
    @test isempty(given_view.kept)
end

end
end

# Read each cell of a drawing, as a paint does: a print computes a part when
# something reads that part.
function _cell_vector_view_read_drawing(x, seen = Base.IdSet{Any}())
    x isa Union{Number, AbstractString, Symbol, Nothing, Function, Module, Type, Char} && return
    x in seen && return
    push!(seen, x)
    if x isa AbstractCell
        _cell_vector_view_read_drawing(x[], seen)
    elseif x isa Union{AbstractVector, Tuple, CellVector}
        foreach(element -> _cell_vector_view_read_drawing(element, seen), x)
    elseif x isa Document && !(x isa ContentView) && !(x isa SyntaxDocument)
        for name in fieldnames(typeof(x))
            _cell_vector_view_read_drawing(getfield(x, name), seen)
        end
    end
    nothing
end

# The names of the cells of `view` that a computation reads.
_cell_vector_view_readers(view) =
    [name for name in fieldnames(typeof(view))
     if getfield(view, name) isa AbstractCell && has_dependent_cells(getfield(view, name))]

function test_cell_vector_view_drop()
@testset "A view goes when nothing reaches it" begin

leaf(s) = SyntaxLeaf(TextString(s))
existing(v) = [(step.stop, child) for (step, child) in child_reference_steps(v)]
indexes(v) = [index for (index, _) in existing(v)]
# Two drops: the first forgets that something asked for a view, and the second
# drops the views that nothing reaches.
settle!(v) = (drop_unreached_views!(v); drop_unreached_views!(v))
measure = FixedMeasure(10, 18, 6, 0)
font = StyleFont("Ubuntu Mono", 20)
text(s) = TextString(s, font, color_white)
stages = ChainingProjection(
    RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    SyntaxNodeView => stages,
]))
make_tree() = begin
    inner = SyntaxNode([SyntaxLeaf(text("x")), SyntaxLeaf(text("y"))]; open = text("("), close = text(")"), sep = text(", "))
    SyntaxNode([SyntaxLeaf(text("ab")), SyntaxLeaf(text("cde")), inner]; open = text("["), close = text("]"), sep = text(", "))
end

@testset "A view that nothing reaches goes, and the next read makes a new view" begin
    list = CellVector(Document[leaf("a"), leaf("b"), leaf("c")])
    view = CellVectorView(list)
    first_view = view[1]
    # A view that something asked for stays for one drop.
    drop_unreached_views!(view)
    @test indexes(view) == [1]
    drop_unreached_views!(view)
    @test isempty(existing(view))
    renewed = view[1]
    @test renewed !== first_view && renewed isa SyntaxLeafView && renewed.viewed === list[1]
    @test has_default_view_state(renewed)
end

@testset "A view that holds a caret stays" begin
    list = CellVector(Document[leaf("a"), leaf("b"), leaf("c")])
    view = CellVectorView(list)
    views = collect(view)
    in_leaf = strip_reference_types(@reference(views[2], value{1}))
    replace_selection!(view, concat_references(Reference(RangeReferenceStep(1, 2)), in_leaf))
    settle!(view)
    @test indexes(view) == [2]
    @test existing(view)[1][2] === views[2]
    clear_selection!(view)
    settle!(view)
    @test isempty(existing(view))
end

@testset "A view with a state that is not the default stays" begin
    node(s) = SyntaxNode([leaf(s)])
    list = CellVector(Document[node("a"), node("b")])
    view = CellVectorView(list)
    folded = view[2]
    folded.collapsed = true
    view[1]
    settle!(view)
    @test indexes(view) == [2] && existing(view)[1][2] === folded
    folded.collapsed = false
    settle!(view)
    @test isempty(existing(view))
end

@testset "A view stays when a list view below it keeps a view" begin
    inner_node = SyntaxNode([SyntaxNode([leaf("deep")])])
    list = CellVector(Document[inner_node, leaf("flat")])
    view = CellVectorView(list)
    outer = view[1]
    deep = outer.children[1]
    deep.collapsed = true
    view[2]
    settle!(view)
    @test indexes(view) == [1] && existing(view)[1][2] === outer
    @test existing(outer.children)[1][2] === deep
    deep.collapsed = false
    settle!(view)
    @test isempty(existing(view))
end

@testset "Code that gets a view and then changes it keeps that view" begin
    node(s) = SyntaxNode([leaf(s)])
    list = CellVector(Document[node("a"), node("b")])
    view = CellVectorView(list)
    got = view[1]
    drop_unreached_views!(view)
    got.collapsed = true
    settle!(view)
    @test indexes(view) == [1] && view[1] === got && view[1].collapsed
end

@testset "The view of an element that left the list goes" begin
    node(s) = SyntaxNode([leaf(s)])
    list = CellVector(Document[node("a"), node("b"), node("c")])
    view = CellVectorView(list)
    gone, stays = view[1], view[3]
    gone.collapsed = true
    stays.collapsed = true
    deleteat!(list, 1)
    drop_unreached_views!(view)
    @test length(existing(view)) == 1 && existing(view)[1][1] == 2 && existing(view)[1][2] === stays
    @test !haskey(view.kept, gone.viewed)
end

@testset "A list view with given views drops nothing" begin
    one = SyntaxLeafView(leaf("a"))
    given = CellVector(Any[one])
    given_view = CellVectorView(CellVector(Document[one.viewed]), given)
    settle!(given_view)
    @test given_view[1] === one && isempty(given_view.kept)
end

@testset "A print of a view reads a cell of each view that it shows" begin
    view = SyntaxNodeView(make_tree())
    root = VerticalLayout([view])
    @test isempty(_cell_vector_view_readers(view))
    iomap = print_document(projection, root)
    # A print computes nothing until something reads its drawing.
    @test isempty(existing(view.children))
    _cell_vector_view_read_drawing(iomap.output)
    @test :viewed in _cell_vector_view_readers(view)
    children = existing(view.children)
    @test [index for (index, _) in children] == [1, 2, 3]
    @test all(pair -> :viewed in _cell_vector_view_readers(pair[2]), children)
    nested = existing(children[3][2].children)
    @test length(nested) == 2 && all(pair -> :viewed in _cell_vector_view_readers(pair[2]), nested)
end

@testset "A view that a print shows stays, and it goes after the print goes" begin
    view = SyntaxNodeView(make_tree())
    root = VerticalLayout([view])
    iomap = print_document(projection, root)
    _cell_vector_view_read_drawing(iomap.output)
    shown = [child for (_, child) in existing(view.children)]
    @test length(shown) == 3
    settle!(view.children)
    @test length(existing(view.children)) == 3
    @test all(map(===, [child for (_, child) in existing(view.children)], shown))
    @test length(existing(shown[3].children)) == 2
    iomap = nothing
    GC.gc(); GC.gc()
    settle!(view.children)
    @test isempty(existing(view.children))
end

@testset "A new print of a view drops the view of an element that left its list" begin
    tree = make_tree()
    view = SyntaxNodeView(tree)
    root = VerticalLayout([view])
    iomap = print_document(projection, root)
    _cell_vector_view_read_drawing(iomap.output)
    removed = tree.children[2]
    @test haskey(view.children.kept, removed)
    deleteat!(tree.children, 2)
    # A change of the content updates the cells of the print that exists. The step
    # of the view runs when a print of the view is made, and the drop runs with it.
    iomap = print_document(projection, root)
    _cell_vector_view_read_drawing(iomap.output)
    @test !haskey(view.children.kept, removed)
    @test [index for (index, _) in existing(view.children)] == [1, 2]
    @test existing(view.children)[2][2].viewed === tree.children[2]
end

end
end
