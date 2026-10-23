"""
Tests for the `.pred` notation: a document written as the call that builds it,
and read back from that text.
"""

using Test
using ProjecturedPlatform.SerializationModule
using ProjecturedPlatform.StyleModule: StyleFont, StyleColor
using ProjecturedPlatform.TextModule: TextBlock, TextString
using ProjecturedKernel.DocumentModule: @document

"""
A document that holds an operator, as a document of Julia code holds `:+` or
`:(=)`.
"""
@document struct PredFileOperator
    operator::Symbol
end

"""
A document that holds a name and the folds of a view of it, which are state of
the view and no part of what it says.
"""
@document struct PredFileFolds
    name::String = ""
    folded::Any = String[]
end

ProjecturedKernel.DocumentModule.get_view_state_fields(::Type{<:PredFileFolds}) = (:folded,)

"""
A page of a text format of the tests: lines, which a `.lines` file writes one to a
line.
"""
@document struct PredFileLines
    lines::Vector{String} = String[]
end

"""
A `.lines` file, which holds a [`PredFileLines`](@ref).
"""
@document struct PredFileLinesFile <: FileDocument
    filename::String
    content::Any = nothing
end

SerializationModule.get_file_domain(::Type{<:PredFileLinesFile}) = PredFileLines
SerializationModule.parse_file_content(::Type{<:PredFileLinesFile}, text::AbstractString) =
    PredFileLines(lines = String.(split(text, '\n')))
SerializationModule.emit_text(file::PredFileLinesFile) = join(get_file_content(file).lines, '\n')

"""
A document of the tests that holds a list of other documents.
"""
@document struct PredFileHolder
    name::String = ""
    elements::Any = Any[]
end

function test_pred_file()
@testset "PredFile: a document as the call that builds it" begin

    @testset "a field of view state stays out of the file" begin
        document = PredFileFolds(name = "outline", folded = ["Q1"])
        text = print_pred_text(document)
        @test occursin("outline", text)
        @test !occursin("folded", text) && !occursin("Q1", text)
        loaded = parse_pred_text(text)
        @test loaded.name == "outline" && isempty(loaded.folded)
        @test is_view_state_field(PredFileFolds, :folded)
        @test !is_view_state_field(PredFileFolds, :name)
        @test is_view_state_field(PredFileFolds, :selection)
    end

    @testset "a document of a format that no file writes is written inline, in the text of its format" begin
        register_file_document_type!(".lines", PredFileLinesFile)
        page = PredFileLines(lines = ["one \"two\"", "", "three \"\""])
        holder = PredFileHolder(name = "work", elements = Any[page, PredFileLines(lines = ["x"])])
        text = cut_file_text(PredFile("work.pred", holder))
        @test occursin("lines\"\"\"\n", text)
        @test occursin("\n        one \"two\"\n\n        three ", text)
        loaded = parse_pred_text(text)
        @test loaded.elements[1] isa PredFileLines
        @test loaded.elements[1].lines == page.lines
        @test loaded.elements[2].lines == ["x"]
        @test cut_file_text(PredFile("work.pred", loaded)) == text
        # A text that the indent would change is written with no indent.
        flat = PredFileHolder(elements = Any[PredFileLines(lines = ["  a", "  b"])])
        flat_text = cut_file_text(PredFile("flat.pred", flat))
        @test occursin("lines\"  a\n  b\"", flat_text)
        @test parse_pred_text(flat_text).elements[1].lines == ["  a", "  b"]
        # A carriage return is a text that a tagged string can not hold.
        carriage = PredFileHolder(elements = Any[PredFileLines(lines = ["a\rb"])])
        @test_throws FileCutException cut_file_text(PredFile("r.pred", carriage))
    end

    @testset "a document written inline at two places is one document when the file loads" begin
        register_file_document_type!(".lines", PredFileLinesFile)
        page = PredFileLines(lines = ["shared"])
        holder = PredFileHolder(elements = Any[page, page])
        directory = mktempdir()
        try
            @test save_file!(PredFile("work.pred", holder), directory)
            text = read(joinpath(directory, "work.pred"), String)
            @test count("shared", text) == 1
            @test occursin("node(file(\"work.pred\"), \"elements[1]\")", text)
            loaded = get_file_content(load_file(directory, "work.pred"))
            @test loaded.elements[1] isa PredFileLines
            @test loaded.elements[1] === loaded.elements[2]
        finally
            rm(directory; recursive = true, force = true)
        end
    end

    @testset "a document that a file of its format writes is a marker into that file" begin
        register_file_document_type!(".lines", PredFileLinesFile)
        page = PredFileLines(lines = ["kept"])
        directory = mktempdir()
        try
            project = FileProject(directory, Any[PredFile("work.pred", PredFileHolder(elements = Any[page])),
                                                 PredFileLinesFile("page.lines", page)])
            @test save_project!(project)
            text = read(joinpath(directory, "work.pred"), String)
            @test occursin("file(\"page.lines\")", text)
            @test !occursin("kept", text)
            loaded = load_project(directory, ["work.pred", "page.lines"])
            @test get_file_content(loaded.files[1]).elements[1] === get_file_content(loaded.files[2])
        finally
            rm(directory; recursive = true, force = true)
        end
    end

    @testset "a value document with no keyword form reads back from its fields" begin
        font = StyleFont("DejaVu Sans", 14; weight = 700, italic = true)
        text = print_pred_text(font)
        loaded = parse_pred_text(text)
        @test loaded isa StyleFont
        @test (loaded.family, loaded.size, loaded.weight, loaded.italic) == ("DejaVu Sans", 14, 700, true)
        @test print_pred_text(loaded) == text
    end

    @testset "a symbol reads back, an operator too, and one that can not is refused" begin
        for symbol in (:name, :+, :(=), :(==), :(::), :&&, :->)
            text = sprint(io -> SerializationModule._print_pred_value(io, symbol, "", 0))
            @test SerializationModule._evaluate_pred(Meta.parse(text)) === symbol
        end
        @test_throws FileCutException sprint(io -> SerializationModule._print_pred_value(io, Symbol("a b"), "", 0))
        @test parse_pred_text(print_pred_text(PredFileOperator(:(=)))).operator === :(=)
    end

    @testset "a styled text reads back with its font and its colour" begin
        block = TextBlock(TextLine([TextString("hello", StyleFont("DejaVu Sans", 14), StyleColor(1.0, 0.0, 0.0, 1.0))]))
        text = print_pred_text(block)
        loaded = parse_pred_text(text)
        string = only(only(loaded.elements).elements)
        @test string.content == "hello"
        @test string.font.family == "DejaVu Sans"
        @test string.font_color.red == 1.0
        @test print_pred_text(loaded) == text
    end

end
end
