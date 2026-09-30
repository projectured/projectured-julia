# The YAML parser: what it reads, and what it declines to guess.
#
# The parser is deliberately partial (see YamlModule): block mappings and
# sequences, flow collections, the scalar kinds, comments and a leading `---`.
# The cases it does NOT support must fail loudly rather than misread, because a
# document that parsed wrong is worse than one that did not parse — so the
# unsupported constructs are asserted too.

using Test

"""
    test_yaml_parser()

Scalars, block and flow collections, nesting, comments, and the constructs the
parser refuses.
"""
function test_yaml_parser()
@testset "parse_yaml" begin

    @testset "scalars" begin
        @test parse_yaml("null") isa YamlNull
        @test parse_yaml("~") isa YamlNull
        @test parse_yaml("true").value == true
        @test parse_yaml("false").value == false
        @test parse_yaml("42").value == 42
        @test parse_yaml("-7").value == -7
        @test parse_yaml("2.5").value ≈ 2.5
        @test parse_yaml("hello").value == "hello"
        @test parse_yaml("'quoted'").value == "quoted"
        @test parse_yaml("\"double\"").value == "double"
        # A quoted number stays a string: the quotes are the type, not the digits.
        @test parse_yaml("'42'") isa YamlString
    end

    @testset "block mapping" begin
        m = parse_yaml("a: 1\nb: two")
        @test m isa YamlMapping
        @test length(m.entries) == 2
        @test m.entries[1].key == "a"
        @test m.entries[1].value.value == 1
        @test m.entries[2].value.value == "two"
    end

    @testset "block sequence" begin
        s = parse_yaml("- 1\n- 2\n- 3")
        @test s isa YamlSequence
        @test length(s.elements) == 3
        @test [e.value for e in s.elements] == [1, 2, 3]
    end

    @testset "nesting by indentation" begin
        m = parse_yaml("outer:\n  inner: 1\n  list:\n    - a\n    - b")
        @test m isa YamlMapping
        inner = m.entries[1].value
        @test inner isa YamlMapping
        @test inner.entries[1].key == "inner"
        list = inner.entries[2].value
        @test list isa YamlSequence
        @test length(list.elements) == 2
    end

    @testset "sequence of mappings" begin
        s = parse_yaml("- name: a\n  n: 1\n- name: b\n  n: 2")
        @test s isa YamlSequence
        @test length(s.elements) == 2
        @test s.elements[1] isa YamlMapping
        @test s.elements[1].entries[1].value.value == "a"
        @test s.elements[2].entries[2].value.value == 2
    end

    @testset "flow collections — YAML is a JSON superset" begin
        s = parse_yaml("[1, 2, 3]")
        @test s isa YamlSequence
        @test length(s.elements) == 3
        m = parse_yaml("{a: 1, b: 2}")
        @test m isa YamlMapping
        @test length(m.entries) == 2
    end

    @testset "comments and the document marker" begin
        m = parse_yaml("---\n# a comment\na: 1   # trailing\n")
        @test m isa YamlMapping
        @test length(m.entries) == 1
        @test m.entries[1].value.value == 1
    end

    @testset "unsupported constructs are misread, not refused" begin
        # The parser's own docstring says it "raises or misreads rather than
        # guessing". These two misread, and that is worth pinning down: a file
        # using either loads as something, with nothing to tell the reader it
        # was not understood.

        # An anchor lands in the scalar text, so `&x 1` becomes the string
        # "&x 1" and the alias becomes the string "*x".
        anchored = parse_yaml("a: &x 1\nb: *x")
        @test anchored.entries[1].value isa YamlString
        @test anchored.entries[1].value.value == "&x 1"
        @test anchored.entries[2].value.value == "*x"
        # @broken: an anchor should raise rather than load as its own source text
        @test_broken anchored.entries[1].value isa YamlNumber

        # A tab indent parses without complaint. YAML forbids tabs for
        # indentation precisely because the width is not defined.
        @test parse_yaml("a:\n\tb: 1") isa YamlMapping
        # @broken: a tab indent should raise; YAML forbids it and the width is undefined
        @test_broken (try parse_yaml("a:\n\tb: 1"); false catch; true end)
    end

end # @testset "parse_yaml"
end # test_yaml_parser
