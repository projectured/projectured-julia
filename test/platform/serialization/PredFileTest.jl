"""
Tests for the `.pred` notation: a document written as the call that builds it,
and read back from that text.
"""

using Test
using ProjecturedPlatform.SerializationModule
using ProjecturedPlatform.StyleModule: StyleFont, StyleColor
using ProjecturedPlatform.TextModule: TextBlock, TextString
using ProjecturedPlatform.WidgetModule: WidgetTable, WidgetLabel, WidgetScrollPane
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
    disk::FileDiskState = FileDiskState()
end

SerializationModule.get_file_domain(::Type{<:PredFileLinesFile}) = PredFileLines
SerializationModule.parse_file_content(::Type{<:PredFileLinesFile}, text::AbstractString) =
    PredFileLines(lines = String.(split(text, '\n')))
SerializationModule.emit_text(file::PredFileLinesFile) = join(get_file_content(file).lines, '\n')

"""
A page of lines and a view of them, a document that is state of the view and no
part of what the page says.
"""
@document struct PredFileViewedLines
    lines::Vector{String} = String[]
    view::Any = nothing
end

ProjecturedKernel.DocumentModule.get_view_state_fields(::Type{<:PredFileViewedLines}) = (:view,)

"""
A `.viewed` file, which holds a [`PredFileViewedLines`](@ref).
"""
@document struct PredFileViewedLinesFile <: FileDocument
    filename::String
    content::Any = nothing
    disk::FileDiskState = FileDiskState()
end

SerializationModule.get_file_domain(::Type{<:PredFileViewedLinesFile}) = PredFileViewedLines
SerializationModule.emit_text(file::PredFileViewedLinesFile) = join(get_file_content(file).lines, '\n')

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

    @testset "a save leaves out a document that a field of view state holds" begin
        page = PredFileViewedLines(lines = ["one", "two"], view = PredFileHolder(name = "view"))
        @test cut_file_text(PredFileViewedLinesFile("page.viewed", page)) == "one\ntwo"
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
            @test occursin("node(file(\"page.lines\"), \"\")", text)
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

    @testset "a table of computed rows of strings and numbers reads back with the same cells" begin
        headers = ["protocol", "N", "G"]
        rows = [Any["pure", 5.0, 0.5], Any["slotted", 6, "0.25"]]
        table = WidgetTable(headers, rows)
        text = print_pred_text(table)
        loaded = parse_pred_text(text)
        @test loaded isa WidgetTable
        @test [header.content for header in loaded.column_headers] == headers
        @test [[cell.content for cell in row] for row in loaded.cells] ==
              [["pure", "5.0", "0.5"], ["slotted", "6", "0.25"]]
        @test print_pred_text(loaded) == text
        @test !occursin("scroll_position", text)
    end

    @testset "a file saved alone writes a file that it holds as file(…), relative to its folder" begin
        root = mktempdir()
        try
            directory = joinpath(root, "work")
            mkpath(directory)
            outside = TextFile(joinpath(root, "other", "notes.txt"), "far")
            holder = PredFileHolder(name = "work", elements = Any[TextFile("notes.txt", "hello"), outside])
            @test save_file!(PredFile("work.pred", holder), directory)
            text = read(joinpath(directory, "work.pred"), String)
            @test occursin("file(\"notes.txt\")", text)
            @test occursin("file(\"../other/notes.txt\")", text)
            @test !occursin("hello", text) && !occursin("far", text)
            # The save writes no held file.
            @test readdir(directory) == ["work.pred"]
            @test !ispath(joinpath(root, "other"))
            # A held file with an absolute name gives the same text.
            absolute = PredFileHolder(name = "work",
                                      elements = Any[TextFile(joinpath(directory, "notes.txt"), "hello"), outside])
            @test cut_file_text(PredFile("work.pred", absolute), directory) == text
        finally
            rm(root; recursive = true, force = true)
        end
    end

    @testset "a file saved alone walks the content of a scroll pane, a positional argument of its call" begin
        held = TextFile("notes.txt", "hello")
        text = cut_file_text(PredFile("card.pred", PredFileHolder(elements = Any[WidgetScrollPane(held)])), mktempdir())
        @test occursin(r"WidgetScrollPane\(\s*file\(\"notes.txt\"\)", text)
        @test !occursin("hello", text)
    end

    @testset "a file saved alone refuses a held file with no name, and says where it is held" begin
        directory = mktempdir()
        try
            holder = PredFileHolder(name = "work", elements = Any[TextFile("", "draft")])
            result = @test_logs (:error, r"with no name at elements\[1\].*Save as") save_file!(
                PredFile("work.pred", holder), directory)
            @test result === false
            @test isempty(readdir(directory))
        finally
            rm(directory; recursive = true, force = true)
        end
    end

    @testset "a file saved alone with an absolute name names itself relative to its folder" begin
        register_file_document_type!(".lines", PredFileLinesFile)
        page = PredFileLines(lines = ["shared"])
        directory = mktempdir()
        try
            path = joinpath(directory, "work.pred")
            @test save_file!(PredFile(path, PredFileHolder(elements = Any[page, page])), directory)
            text = read(path, String)
            @test occursin("node(file(\"work.pred\"), \"elements[1]\")", text)
            loaded = get_file_content(load_file(directory, "work.pred"))
            @test loaded.elements[1] isa PredFileLines
            @test loaded.elements[2] === loaded.elements[1]
        finally
            rm(directory; recursive = true, force = true)
        end
    end

    @testset "splice_held_files! gives each whole file(…) the answer of find_file" begin
        asked = String[]
        answers = Dict("/work/sub/a.txt" => TextFile("/work/sub/a.txt", "one"),
                       "/work/b/c.txt" => TextFile("/work/b/c.txt", "two"))
        find_file = path -> (push!(asked, path); get(answers, path, nothing))
        a_leaf = () -> SerializationModule.PredReference("file(\"a.txt\")")
        node_leaf = SerializationModule.PredReference("node(file(\"a.txt\"), \"elements[1]\")")
        gone_leaf = SerializationModule.PredReference("file(\"gone.txt\")")
        holder = PredFileHolder(name = "h", elements = Any[a_leaf(), a_leaf(), node_leaf,
                                SerializationModule.PredReference("file(\"../b/c.txt\")"), gone_leaf,
                                (picture = a_leaf(), count = 3), (a_leaf(), 4)])
        content = splice_held_files!(holder, "/work/sub", find_file)
        @test content === holder
        elements = holder.elements
        # A whole file(…) takes the answer, and two slots of one path hold one object.
        @test elements[1] === answers["/work/sub/a.txt"]
        @test elements[2] === elements[1]
        # A node(…) stays, and so does a file that find_file does not know.
        @test elements[3] === node_leaf
        @test elements[5] === gone_leaf
        # A path with .. is asked as the absolute path against the base folder.
        @test elements[4] === answers["/work/b/c.txt"]
        # A slot in a named tuple and in a tuple takes its answer.
        @test elements[6].picture === elements[1] && elements[6].count == 3
        @test elements[7][1] === elements[1] && elements[7][2] == 4
        # find_file is asked once for each path.
        @test sort(asked) == ["/work/b/c.txt", "/work/sub/a.txt", "/work/sub/gone.txt"]
        # A content that is a whole file(…) is the answer.
        @test splice_held_files!(a_leaf(), "/work/sub", find_file) === answers["/work/sub/a.txt"]
        # An answer nothing keeps every leaf, and a content that holds none stays as it is.
        kept = PredFileHolder(name = "k", elements = Any[a_leaf()])
        splice_held_files!(kept, "/work/sub", path -> nothing)
        @test kept.elements[1] isa SerializationModule.PredReference
        @test splice_held_files!("plain text", "/work/sub", find_file) == "plain text"
    end

    @testset "a held file in a tuple or a named tuple is a reference, and the load gives the file back" begin
        directory = mktempdir()
        try
            record = (number = 1, picture = TextFile("p.txt", "pixels"), note = "first")
            pair = (2, TextFile("q.txt", "other"))
            nested = (meta = (picture = TextFile("p.txt", "pixels"),),)
            holder = PredFileHolder(name = "ledger", elements = Any[record, pair, nested])
            @test save_file!(PredFile("ledger.pred", holder), directory)
            text = read(joinpath(directory, "ledger.pred"), String)
            @test occursin("(number = 1, picture = file(\"p.txt\"), note = \"first\")", text)
            @test occursin("(2, file(\"q.txt\"))", text)
            @test occursin("(meta = (picture = file(\"p.txt\"),),)", text)
            @test !occursin("pixels", text) && !occursin("other", text)
            @test readdir(directory) == ["ledger.pred"]
            write(joinpath(directory, "p.txt"), "pixels")
            write(joinpath(directory, "q.txt"), "other")
            project = load_project(directory, ["ledger.pred"]; follow = true)
            @test length(project.files) == 3
            loaded = get_file_content(project.files[1]).elements
            @test loaded[1].number == 1 && loaded[1].note == "first"
            @test loaded[1].picture isa TextFile && get_filename(loaded[1].picture) == "p.txt"
            @test loaded[2][1] == 2 && loaded[2][2] isa TextFile && get_filename(loaded[2][2]) == "q.txt"
            # Two places of one path hold one file.
            @test loaded[3].meta.picture === loaded[1].picture
            # A load of the file alone keeps each reference, and saves it back unchanged.
            alone = load_file(directory, "ledger.pred")
            @test get_file_content(alone).elements[1].picture isa SerializationModule.PredReference
            @test cut_file_text(alone, directory) == text
        finally
            rm(directory; recursive = true, force = true)
        end
    end

end
end
