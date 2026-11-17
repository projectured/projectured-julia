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
