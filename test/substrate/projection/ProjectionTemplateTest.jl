# Regression for the `@projection_template` import-hygiene fix.
#
# `@projection_template` must register its `print_document` method on the
# *canonical* `ProjectionModule.print_document` generic — the one the
# type-dispatcher calls — regardless of whether the calling module imported
# `print_document` into its own scope. A projection module that imports the
# markers but forgets `print_document` used to silently define a dead local
# generic, and dispatch later failed with a confusing `MethodError`.
#
# This probe module deliberately does NOT import `print_document`.
module _ProjectionTemplateHygieneProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionModule: var"@projection_template"
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf
    import ProjecturedText.TextModule: TextString
    # print_document intentionally NOT imported.

    @document struct ProbeDoc <: Document
        text::String
    end
    ProbeDoc(t::AbstractString) = ProbeDoc(Cell(String(t)), Cell(nothing))

    @projection struct ProbeToLeaf <: Projection end
    @projection_template ProbeToLeaf ProbeDoc (p, doc) -> SyntaxLeaf(TextString("ok"))
end

function test_projection_template_hygiene()
    @testset "ProjectionTemplate import hygiene" begin
        P = _ProjectionTemplateHygieneProbe
        # The macro must not have created a dead local generic in the probe module.
        @test !isdefined(P, :print_document)
        # The template method dispatches via the canonical generic, even though
        # the probe module never imported `print_document`.
        tdp = TypeDispatchingProjection(P.ProbeDoc => P.ProbeToLeaf())
        out = print_document(RecursiveProjection(tdp), P.ProbeDoc("hi")).output
        @test out isa SyntaxLeaf
    end
end

# A fixed-children blueprint, written both ways: with the long positional constructor
# (children stored as a raw Vector) and with the ordinary one (children coerced into a
# CellVector). The engine must walk both — recognising only the raw Vector is what used
# to force every fixed-children template node into the 7-arg positional form, and made
# `SyntaxNode([...])` / `SyntaxConcatenation([...])` reach the printer with their markers
# unresolved (it reads `.content` off a `Bound` and dies).
module _FixedChildrenBlueprintProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection, print_document
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionModule: var"@projection_template", bound
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf, SyntaxNode, SyntaxConcatenation, SyntaxDocument
    import ProjecturedText.TextModule: TextString
    import ProjecturedStyle.StyleModule: font_ubuntu_monospace_regular_20
    import ProjecturedStyle.StyleModule: color_default

    @document struct Pair2 <: Document
        a::String
        b::String
    end

    _leaves(doc) = SyntaxDocument[
        SyntaxLeaf(bound(:a, String, TextString(() -> doc.a, font_ubuntu_monospace_regular_20, color_default))),
        SyntaxLeaf(bound(:b, String, TextString(() -> doc.b, font_ubuntu_monospace_regular_20, color_default)))]

    # The long positional form: children land in the field as a raw Vector.
    @projection struct PairToNode <: Projection end
    @projection_template PairToNode Pair2 (p, doc) ->
        SyntaxNode(nothing, nothing, nothing, _leaves(doc), 0, false, nothing)

    # The form a domain actually wants to write: children coerced into a CellVector.
    @projection struct PairToConcat <: Projection end
    @projection_template PairToConcat Pair2 (p, doc) -> SyntaxConcatenation(_leaves(doc))

    @projection struct PairToKwNode <: Projection end
    @projection_template PairToKwNode Pair2 (p, doc) -> SyntaxNode(_leaves(doc); sep="-")
end

function test_projection_template_fixed_children()
    @testset "ProjectionTemplate fixed children, however the node was built" begin
        P = _FixedChildrenBlueprintProbe
        render_with(proj) = begin
            tdp = TypeDispatchingProjection(P.Pair2 => proj)
            render(print_document(RecursiveProjection(tdp), P.Pair2("hello", "world")).output)
        end
        # All three are the same blueprint; only the constructor differs.
        @test render_with(P.PairToNode())   == "helloworld"   # raw Vector (worked before)
        @test render_with(P.PairToConcat()) == "helloworld"   # CellVector, no chrome
        @test render_with(P.PairToKwNode()) == "hello-world"  # CellVector, with a separator
    end
end

# A child list that depends on an optional field. The builder writes it as a thunk,
# so the node has a slot for the note only while the note is there.
module _ConditionalChildrenProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection, print_document
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionModule: var"@projection_template"
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf, SyntaxConcatenation
    import ProjecturedText.TextModule: TextString
    import ProjecturedStyle.StyleModule: font_ubuntu_monospace_regular_20
    import ProjecturedStyle.StyleModule: color_default

    @document struct Word <: Document
        text::String
    end
    Word(text::AbstractString) = Word(Cell(String(text)), Cell(nothing))

    @document struct Labelled <: Document
        name::String
        note::Union{Word,Nothing}
    end

    _text(content) = TextString(content, font_ubuntu_monospace_regular_20, color_default)

    @projection struct WordToLeaf <: Projection end
    @projection_template WordToLeaf Word (p, doc) ->
        SyntaxLeaf(bound(:text, String, _text(() -> doc.text)))

    @projection struct LabelledToConcat <: Projection end
    @projection_template LabelledToConcat Labelled (p, doc) ->
        SyntaxConcatenation(() -> doc.note === nothing ?
            Any[ SyntaxLeaf(bound(:name, String, _text(() -> doc.name))) ] :
            Any[ SyntaxLeaf(bound(:name, String, _text(() -> doc.name))),
                 SyntaxLeaf(_text(": ")), project(:note) ])
end

function test_projection_template_conditional_children()
    @testset "ProjectionTemplate child list that a thunk computes" begin
        P = _ConditionalChildrenProbe
        projection = RecursiveProjection(TypeDispatchingProjection(
            P.Labelled => P.LabelledToConcat(), P.Word => P.WordToLeaf()))
        doc = P.Labelled("x", P.Word("y"))
        iomap = print_document(projection, doc)
        @test render(iomap.output) == "x: y"
        @test length(get_syntax_children(iomap.output)) == 3
        # Each write reaches the output of the same IoMap, with no new print.
        doc.note = nothing
        @test render(iomap.output) == "x"
        @test length(get_syntax_children(iomap.output)) == 1
        doc.note = P.Word("z")
        @test render(iomap.output) == "x: z"
        @test length(get_syntax_children(iomap.output)) == 3
        doc.note.text = "zz"
        @test render(iomap.output) == "x: zz"
        # A slot that the first print did not have appears with its value.
        bare = P.Labelled("v", nothing)
        bare_iomap = print_document(projection, bare)
        @test render(bare_iomap.output) == "v"
        bare.note = P.Word("w")
        @test render(bare_iomap.output) == "v: w"
    end
end

# A template node whose child projection has the 4-argument reader and no other. A
# key at the child reaches that reader, with the `recursion` that printed the child.
module _GestureDescentProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ReferenceModule: Reference, EmptyReference
    import ProjecturedKernel.IntentModule: Intent
    import ProjecturedKernel.IoMapModule: SimpleIoMap
    import ProjecturedKernel.OperationModule: ReplaceSelectionOperation
    import ProjecturedKernel.ProjectionModule: Projection, print_document, read_intent
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionModule: var"@projection_template"
    import ProjecturedCollection.CollectionModule: CellVector
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf, SyntaxNode
    import ProjecturedText.TextModule: TextString

    @document struct Item <: Document
        text::String
    end
    Item(text::AbstractString) = Item(Cell(String(text)), Cell(nothing))

    @document struct Shelf <: Document
        items::CellVector
    end

    # The recursion that the last read of an item received.
    const RECEIVED_RECURSION = Ref{Any}(nothing)

    @projection struct ItemToLeaf <: Projection end
    print_document(p::ItemToLeaf, recursion, item::Item, ctx) =
        SimpleIoMap(p, item, SyntaxLeaf(TextString(item.text)))
    function read_intent(::ItemToLeaf, recursion, change::Intent, iomap)
        RECEIVED_RECURSION[] = recursion
        Intent(change.gesture, ReplaceSelectionOperation(EmptyReference()))
    end

    @projection struct ShelfToNode <: Projection end
    @projection_template ShelfToNode Shelf (p, doc) -> SyntaxNode(collection(:items))
end

function test_projection_template_gesture_descent()
    @testset "ProjectionTemplate reads a key at a child with its 4-argument reader" begin
        P = _GestureDescentProbe
        projection = RecursiveProjection(TypeDispatchingProjection(
            P.Shelf => P.ShelfToNode(), P.Item => P.ItemToLeaf()))
        shelf = P.Shelf(CellVector([P.Item("a"), P.Item("b")]), nothing)
        iomap = print_document(projection, shelf)
        set_selection!(shelf, @reference(shelf, items[2]))
        key = KeyDown(:x, ModifierKeys(); time = 0.0)
        answer = read_intent(projection, nothing, Intent(key), iomap)
        @test answer.operation isa ReplaceSelectionOperation
        @test strip_reference_types(answer.operation.path) ==
              Reference(FieldReferenceStep("items"), ElementReferenceStep(2))
        @test P.RECEIVED_RECURSION[] === projection
    end
end

# A mixed node, a heading leaf with the items spliced after it, and a sectioned
# node, one wrapper for each field that has entries.
module _ReconciledChildrenProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection, print_document
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionModule: var"@projection_template"
    import ProjecturedCollection.CollectionModule: CellVector
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf, SyntaxNode
    import ProjecturedText.TextModule: TextString
    import ProjecturedStyle.StyleModule: font_ubuntu_monospace_regular_20
    import ProjecturedStyle.StyleModule: color_default

    @document struct Item <: Document
        text::String
    end
    Item(text::AbstractString) = Item(Cell(String(text)), Cell(nothing))

    @document struct Group <: Document
        name::String
        items::CellVector
    end

    @document struct Sheet <: Document
        rows::CellVector
        notes::CellVector
    end

    _text(content) = TextString(content, font_ubuntu_monospace_regular_20, color_default)

    @projection struct ItemToLeaf <: Projection end
    @projection_template ItemToLeaf Item (p, doc) ->
        SyntaxLeaf(bound(:text, String, _text(() -> doc.text)))

    @projection struct GroupToNode <: Projection end
    @projection_template GroupToNode Group (p, doc) ->
        SyntaxNode(nothing, nothing, nothing,
                   Any[ SyntaxLeaf(bound(:name, String, _text(() -> doc.name))),
                        collection(:items) ],
                   0, false, nothing)

    @projection struct SheetToNode <: Projection end
    @projection_template SheetToNode Sheet (p, doc) ->
        SyntaxNode(sections([(:rows, outs -> SyntaxNode(outs)),
                             (:notes, outs -> SyntaxNode(outs))]))
end

function test_projection_template_reconciled_children()
    @testset "ProjectionTemplate keeps the child IoMaps of mixed and sections nodes" begin
        P = _ReconciledChildrenProbe
        projection = RecursiveProjection(TypeDispatchingProjection(
            P.Group => P.GroupToNode(), P.Sheet => P.SheetToNode(),
            P.Item => P.ItemToLeaf()))
        make_items(texts) = CellVector([P.Item(text) for text in texts])

        # An insert into the spliced collection prints the new element only.
        group = P.Group("g", make_items(["a", "b"]), nothing)
        iomap = print_document(projection, group)
        before = copy(iomap.child_iomaps.coll[])
        push!(group.items, P.Item("c"))
        after = iomap.child_iomaps.coll[]
        @test length(after) == 3
        @test after[1] === before[1] && after[2] === before[2]
        @test occursin("c", render(iomap.output))

        # An insert into one section keeps the entries of that section and of the other.
        sheet = P.Sheet(make_items(["r1", "r2"]), make_items(["n1"]), nothing)
        iomap = print_document(projection, sheet)
        rows = copy(iomap.child_iomaps[1].entries)
        notes = copy(iomap.child_iomaps[2].entries)
        push!(sheet.rows, P.Item("r3"))
        after_rows = iomap.child_iomaps[1].entries
        @test length(after_rows) == 3
        @test after_rows[1] === rows[1] && after_rows[2] === rows[2]
        @test iomap.child_iomaps[2].entries[1] === notes[1]
        @test occursin("r3", render(iomap.output))
    end
end

# A template leaf whose bound value is in a field that is not named `value`: the
# output leaf holds its text in `label`.
module _ValueFieldProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection, print_document
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionModule: var"@projection_template"
    import ProjecturedSyntax.SyntaxModule: SyntaxNode
    import ProjecturedText.TextModule: TextString
    import ProjecturedStyle.StyleModule: font_ubuntu_monospace_regular_20
    import ProjecturedStyle.StyleModule: color_default

    @document struct Named <: Document
        x::String
    end
    Named(x::AbstractString) = Named(Cell(String(x)), Cell(nothing))

    @document struct Badge <: Document
        label::Any
    end

    _text(content) = TextString(content, font_ubuntu_monospace_regular_20, color_default)

    @projection struct NamedToNode <: Projection end
    @projection_template NamedToNode Named (p, doc) ->
        SyntaxNode(nothing, nothing, nothing,
                   Any[ Badge(bound(:x, String, _text(() -> doc.x)), nothing) ],
                   0, false, nothing)
end

function test_projection_template_value_field()
    @testset "ProjectionTemplate maps a bound leaf through the field that holds it" begin
        P = _ValueFieldProbe
        projection = RecursiveProjection(TypeDispatchingProjection(P.Named => P.NamedToNode()))
        named = P.Named("hello")
        iomap = print_document(projection, named)
        caret = @reference(named, x{1})
        shown = map_reference_forward(iomap.projection, iomap, caret)
        @test strip_reference_types(shown) ==
              Reference(FieldReferenceStep("children"), ElementReferenceStep(1),
                        FieldReferenceStep("label"), PositionReferenceStep(1))
        back = map_reference_backward(iomap.projection, iomap, shown)
        @test strip_reference_types(back) == strip_reference_types(caret)
        # The leaf shows the caret of its input in the same field.
        set_selection!(named, caret)
        badge = iomap.output.children[1]
        @test strip_reference_types(get_stored_selection(badge)) ==
              Reference(FieldReferenceStep("label"), PositionReferenceStep(1))
    end
end

# A node of each wiring kind that makes its children as the input changes: a
# token list that a thunk computes, a mixed node, a node of sections and a child
# list that a thunk computes.
module _TemplateWiringsProbe
    import ProjecturedKernel.DocumentModule: Document, var"@document"
    import ProjecturedKernel.CellModule: Cell, Computation
    import ProjecturedKernel.ReferenceModule: Reference
    import ProjecturedKernel.ProjectionModule: Projection, print_document
    import ProjecturedKernel.ProjectionModule: var"@projection"
    import ProjecturedKernel.ProjectionModule: var"@projection_template"
    import ProjecturedCollection.CollectionModule: CellVector
    import ProjecturedSyntax.SyntaxModule: SyntaxLeaf, SyntaxNode, SyntaxConcatenation
    import ProjecturedText.TextModule: TextString
    import ProjecturedStyle.StyleModule: font_ubuntu_monospace_regular_20
    import ProjecturedStyle.StyleModule: color_default

    @document struct Word <: Document
        text::String
    end
    Word(text::AbstractString) = Word(Cell(String(text)), Cell(nothing))

    @document struct Group <: Document
        name::String
        items::CellVector
    end

    @document struct Sheet <: Document
        rows::CellVector
        notes::CellVector
    end

    @document struct Labelled <: Document
        name::String
        note::Union{Word,Nothing}
    end

    _text(content) = TextString(content, font_ubuntu_monospace_regular_20, color_default)

    @projection struct WordToLeaf <: Projection end
    @projection_template WordToLeaf Word (p, doc) ->
        SyntaxLeaf(bound(:text, String, _text(() -> doc.text)))

    # One bound token between two brackets.
    @projection struct WordToTokens <: Projection end
    @projection_template WordToTokens Word (p, doc) ->
        SyntaxNode(tokens(() -> Any[
            SyntaxLeaf(_text("<")),
            SyntaxLeaf(bound(:text, String, _text(() -> doc.text))),
            SyntaxLeaf(_text(">"))]))

    @projection struct GroupToNode <: Projection end
    @projection_template GroupToNode Group (p, doc) ->
        SyntaxNode(nothing, nothing, nothing,
                   Any[ SyntaxLeaf(bound(:name, String, _text(() -> doc.name))),
                        collection(:items) ],
                   0, false, nothing)

    @projection struct SheetToNode <: Projection end
    @projection_template SheetToNode Sheet (p, doc) ->
        SyntaxNode(sections([(:rows, outs -> SyntaxNode(outs)),
                             (:notes, outs -> SyntaxNode(outs))]))

    @projection struct LabelledToConcat <: Projection end
    @projection_template LabelledToConcat Labelled (p, doc) ->
        SyntaxConcatenation(() -> doc.note === nothing ?
            Any[ SyntaxLeaf(bound(:name, String, _text(() -> doc.name))) ] :
            Any[ SyntaxLeaf(bound(:name, String, _text(() -> doc.name))),
                 SyntaxLeaf(_text(": ")), project(:note) ])
end

# A caret mapped into the output of `iomap` and back, with no type checkpoints,
# or `nothing` where a map has no image.
function _map_template_caret_round_trip(iomap, caret)
    shown = map_reference_forward(iomap.projection, iomap, caret)
    shown === nothing && return nothing
    back = map_reference_backward(iomap.projection, iomap, shown)
    back === nothing ? nothing : strip_reference_types(back)
end

function test_projection_template_wirings()
    @testset "ProjectionTemplate wirings follow an edit through the same IoMap" begin
        P = _TemplateWiringsProbe
        projection = RecursiveProjection(TypeDispatchingProjection(
            P.Group => P.GroupToNode(), P.Sheet => P.SheetToNode(),
            P.Labelled => P.LabelledToConcat(), P.Word => P.WordToLeaf()))
        make_words(texts) = CellVector([P.Word(text) for text in texts])

        @testset "a token list" begin
            bracketed = RecursiveProjection(
                TypeDispatchingProjection(P.Word => P.WordToTokens()))
            word = P.Word("a")
            iomap = print_document(bracketed, word)
            @test render(iomap.output) == "<a>"
            word.text = "bc"
            @test render(iomap.output) == "<bc>"
            caret = @reference(word, text{1})
            @test _map_template_caret_round_trip(iomap, caret) ==
                  strip_reference_types(caret)
        end

        @testset "a mixed node" begin
            group = P.Group("g", make_words(["a", "b"]), nothing)
            iomap = print_document(projection, group)
            @test render(iomap.output) == "gab"
            group.name = "h"
            group.items[2].text = "z"
            deleteat!(group.items, 1)
            @test render(iomap.output) == "hz"
            push!(group.items, P.Word("c"))
            @test render(iomap.output) == "hzc"
            caret = @reference(group, items[2].text{0})
            @test _map_template_caret_round_trip(iomap, caret) ==
                  strip_reference_types(caret)
        end

        @testset "a node of sections" begin
            sheet = P.Sheet(make_words(["r"]), make_words(["n"]), nothing)
            iomap = print_document(projection, sheet)
            @test render(iomap.output) == "rn"
            # A section with no entries has no wrapper.
            deleteat!(sheet.notes, 1)
            @test length(get_syntax_children(iomap.output)) == 1
            sheet.rows[1].text = "x"
            @test render(iomap.output) == "x"
            push!(sheet.notes, P.Word("m"))
            @test length(get_syntax_children(iomap.output)) == 2
            @test render(iomap.output) == "xm"
            caret = @reference(sheet, notes[1].text{1})
            @test _map_template_caret_round_trip(iomap, caret) ==
                  strip_reference_types(caret)
        end

        @testset "a child list that a thunk computes" begin
            labelled = P.Labelled("x", nothing)
            iomap = print_document(projection, labelled)
            @test render(iomap.output) == "x"
            labelled.note = P.Word("y")
            labelled.name = "w"
            @test render(iomap.output) == "w: y"
            caret = @reference(labelled, note.text{1})
            @test _map_template_caret_round_trip(iomap, caret) ==
                  strip_reference_types(caret)
        end
    end
end
