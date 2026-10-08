function test_object_field_to_syntax()

_ofs_server() = FormServer("gateway", 4, true, Any["alpha", "beta"], nothing)

_ofs_tag_path(i) = extend_reference(ConcreteReference(FieldReferenceStep("tags"), EmptyReference()),
                                    ElementReferenceStep(i))

# The ObjectField entry stands in front of ObjectToSyntax's own table. Without
# it the `Any` row would dispatch to ObjectNodeToSyntaxNode and dump the whole
# object and its reference path.
_ofs_stage() = RecursiveProjection(TypeDispatchingProjection(vcat(
    Pair{Type,Any}[ObjectField => ObjectFieldToSyntax()],
    ObjectToSyntax(open_delimiter = "{", close_delimiter = "}").dispatch)))

function _ofs_render(doc)
    seq = ChainingProjection(_ofs_stage(),
                             RecursiveProjection(SyntaxToText(indent_size = 2)),
                             RecursiveProjection(TextToString()))
    out = print_document(seq, seq, doc, PrinterContext()).output
    join((rstrip(l) for l in split(out, '\n')), '\n')
end

@testset "ObjectFieldToSyntax names the field and prints the value" begin

    srv = _ofs_server()
    @test _ofs_render(ObjectField(srv, "name")) == "name \"gateway\""
    @test _ofs_render(ObjectField(srv, "capacity")) == "capacity 4"
    @test _ofs_render(ObjectField(srv, "enabled")) == "enabled true"

end # @testset

@testset "each kind of value in an object takes the role of its kind" begin

    role(name) = resolve_theme_color(ColorRole(name), Appearance())
    rule(type) = only(rule for rule in ObjectToSyntax().dispatch if first(rule) === type)[2]
    @test rule(Nothing).style.color == role(:null_literal)
    @test rule(Bool).style.color == role(:boolean_literal)
    @test rule(Number).style.color == role(:number_literal)
    @test rule(Symbol).style.color == role(:symbol_literal)
    @test rule(AbstractString).value.color == role(:string_literal)
    @test rule(Char).value.color == role(:character_literal)

end # @testset

@testset "a step that names no field leaves the value alone" begin

    srv = _ofs_server()
    # An index makes a poor label, so the element prints as its value and the
    # caller puts a label beside it.
    @test _ofs_render(ObjectField(srv, _ofs_tag_path(2))) == "\"beta\""

end # @testset

@testset "the node is a name leaf beside the value" begin

    srv = _ofs_server()
    stage = _ofs_stage()
    out = print_document(stage, stage, ObjectField(srv, "name"), PrinterContext()).output
    @test out isa SyntaxNode
    @test length(out.children) == 2
    @test out.children[1] isa SyntaxLeaf
    @test out.children[1].value.content == "name"
    @test out.children[2] isa SyntaxLeaf
    @test out.children[2].value.content == "gateway"

end # @testset

@testset "the value repaints when the object is written" begin

    srv = _ofs_server()
    stage = _ofs_stage()
    iomap = print_document(stage, stage, ObjectField(srv, "name"), PrinterContext())
    @test iomap.output.children[2].value.content == "gateway"

    srv.name = "gw2"
    @test iomap.output.children[2].value.content == "gw2"

end # @testset

@testset "fields of two objects stack into one node" begin

    srv = _ofs_server()
    cli = FormServer("laptop", 1, false, Any["x"], nothing)
    rendered = _ofs_render(Any[ObjectField(srv, "name"), ObjectField(cli, "name")])
    @test rendered == "{\n  name \"gateway\"\n  name \"laptop\"\n}"

end # @testset

end # test_object_field_to_syntax
