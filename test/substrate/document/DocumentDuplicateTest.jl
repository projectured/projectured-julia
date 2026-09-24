# The duplicate each substrate kind declares: an empty tab, a primitive, a widget,
# a layout and a collection. Each kind answers `has_document_duplicate` from its
# type, and `make_document_duplicate` gives a copy that the original does not
# follow. A kind that holds an action refuses, and says why.
function test_document_duplicate()
@testset "Document duplicate" begin

# The reason a refusal gives, or `nothing` when the duplicate is made.
function _refusal(document)
    try
        make_document_duplicate(document)
        nothing
    catch e
        e isa DocumentCopyException || rethrow()
        e.reason
    end
end

_label(text) = WidgetLabel(Point2D(0, 0), text)

@testset "an empty tab duplicates into another empty tab" begin
    empty = DocumentNothing()
    @test has_document_duplicate(empty)
    duplicate = make_document_duplicate(empty)
    @test duplicate isa DocumentNothing
    @test duplicate !== empty
end

@testset "a primitive is copied, and the copy is its own" begin
    text = PrimitiveString("hello")
    @test has_document_duplicate(text)
    duplicate = make_document_duplicate(text)
    @test duplicate.value == "hello"
    set_cell_value!(getfield(duplicate, :value), "changed")
    @test text.value == "hello"
end

@testset "a widget is copied" begin
    label = _label("one")
    @test has_document_duplicate(label)
    duplicate = make_document_duplicate(label)
    @test duplicate isa WidgetLabel
    @test duplicate.content == "one"
    @test getfield(duplicate, :content) !== getfield(label, :content)
end

@testset "a layout holds the duplicates of its children" begin
    layout = HorizontalLayout(Any[_label("left"), _label("right")])
    duplicate = make_document_duplicate(layout)
    @test length(duplicate.children) == 2
    @test duplicate.children[2].content == "right"
    @test duplicate.children[1] !== layout.children[1]
    @test duplicate.children !== layout.children
end

@testset "a button shares its command, which every control that shows it shares" begin
    button = WidgetButton(Point2D(0, 0), Point2D(40, 20), "Run"; action = _ -> nothing)
    card = WidgetCard(Point2D(0, 0); title = "card", content = button)
    @test has_document_duplicate(card)
    duplicate = make_document_duplicate(card)
    @test duplicate.content !== button
    @test duplicate.content.action === button.action
end

@testset "a widget that holds a bare function refuses" begin
    field = WidgetText(Point2D(0, 0), "12"; validator = make_numeric_validator())
    card = WidgetCard(Point2D(0, 0); title = "card", content = field)
    @test occursin("action", _refusal(card))
end

@testset "a list keeps its selection in a duplicate, and not in a plain copy" begin
    list = CellVector(Any[PrimitiveString("a"), PrimitiveString("b")])
    set_cell_value!(getfield(list, :selection),
                    extend_reference(EmptyReference(), ElementReferenceStep(2)))
    duplicate = make_document_duplicate(list)
    @test duplicate[2].value == "b"
    @test duplicate[1] !== list[1]
    @test getfield(duplicate, :selection)[] == getfield(list, :selection)[]
    @test getfield(copy_document(list), :selection)[] === nothing
end

@testset "a list whose selection a projection computes is copied" begin
    list = CellVector(Any[PrimitiveString("a")])
    set_cell_computation!(getfield(list, :selection), () -> nothing)
    duplicate = make_document_duplicate(list)
    @test duplicate isa CellVector
    @test !is_computed_cell(getfield(duplicate, :selection))
end

@testset "the plain copy of a mutable list still takes a value of any type" begin
    list = copy_document(MutableCell, CellVector(Any[1, 2]))
    copied = copy_document(list)
    push!(copied, "three")
    @test length(copied) == 3
    @test length(list) == 2
end

@testset "a list met twice is one duplicate, and a list that holds itself refuses" begin
    inner = CellVector(Any[PrimitiveString("a")])
    duplicate = make_document_duplicate(CellVector(Any[inner, inner]))
    @test duplicate[1] === duplicate[2]
    @test duplicate[1] !== inner
    looped = CellVector(Any[nothing])
    looped[1] = looped
    @test occursin("back-link", _refusal(looped))
end

@testset "a matrix and a linked list declare no duplicate" begin
    @test !has_document_duplicate(CellMatrix(["a" "b"]))
    @test !has_document_duplicate(ListNode(1))
    @test has_document_duplicate(CellTable(1, 1))
end

@testset "a computed list refuses" begin
    source = PrimitiveString("x")
    list = CellVector(@computation Any[source])
    @test occursin("computes", _refusal(list))
end

end # testset
end # function
