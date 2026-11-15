"""
Tests for `FileFormat` and its seams: a format that this file declares, the
defaults of the seams, the read and the make of a file in a format, and the
searches over the formats of the session.
"""

using Test
using ProjecturedPlatform.SerializationModule
using ProjecturedKernel.DocumentModule: @document

"The documents of the tally format of this test."
abstract type TallyDocument <: Document end

"A count, which a tally file writes as that many strokes `|`."
@document struct TallyCount <: TallyDocument
    count::Int = 0
end

"The leaf where a tally file refers to another file: the body of the marker."
@document struct TallyReference <: TallyDocument
    marker::String = ""
end

"The file of the tally format."
@document struct TallyFile <: FileDocument
    filename::String
    content::Document = TallyCount()
    disk::FileDiskState = FileDiskState()
end

"The tally format: a count as strokes, in a file `.tally` or `.tly`."
struct TallyFileFormat <: FileFormat end

"A format whose file a program writes and a person only reads, chosen by its opener."
struct TallyLogFileFormat <: FileFormat end

"A format that declares `.tly` too, while the test of two such formats runs."
struct TallyCopyFileFormat <: FileFormat end

"A type with a field, which is no format, so no search finds it."
struct TallyFieldFileFormat <: FileFormat
    name::String
end

SerializationModule.get_file_format_extensions(::TallyFileFormat) = (".tally", ".tly")
SerializationModule.get_file_format_domain(::TallyFileFormat) = TallyDocument

function SerializationModule.parse_document_string(::TallyFileFormat, string::AbstractString)
    text = strip(string)
    marker = parse_marker_text(text)
    marker === nothing ? TallyCount(count = count(==('|'), text)) : TallyReference(marker = marker)
end

SerializationModule.make_document_string(::TallyFileFormat, document::TallyCount) =
    repeat("|", document.count)
SerializationModule.make_document_string(::TallyFileFormat, leaf::TallyReference) =
    make_marker_text(leaf.marker)
SerializationModule.make_reference_leaf(::TallyFileFormat, marker::AbstractString) =
    TallyReference(marker = String(marker))
SerializationModule.find_reference_marker(leaf::TallyReference) = leaf.marker
SerializationModule.get_file_type(::TallyFileFormat) = TallyFile
SerializationModule.get_file_format(::TallyFile) = TallyFileFormat()

SerializationModule.get_file_format_extensions(::TallyLogFileFormat) = ()
SerializationModule.get_file_format_domain(::TallyLogFileFormat) = TallyDocument
SerializationModule.is_editable_file_format(::TallyLogFileFormat) = false
SerializationModule.read_file_content(::TallyLogFileFormat, path::AbstractString) =
    TallyCount(count = length(first(eachline(path))))
SerializationModule.is_written_in_file(::TallyLogFileFormat, ::TallyCount, name::Symbol) = false
SerializationModule.is_written_inline(::TallyLogFileFormat, ::TallyReference) = true
SerializationModule.is_file_domain_node(::TallyLogFileFormat, ::Integer) = true

SerializationModule.get_file_format_extensions(::TallyFieldFileFormat) = (".tally-field",)

function test_file_format()
@testset "FileFormat: a format and its seams" begin

    @testset "a format declares its extensions, its domain, its parser and its string" begin
        format = TallyFileFormat()
        @test format === TallyFileFormat()
        @test get_file_format_extensions(format) == (".tally", ".tly")
        @test get_file_format_domain(format) === TallyDocument
        document = parse_document_string(format, "|||\n")
        @test document isa TallyCount && document.count == 3
        @test make_document_string(format, document) == "|||"
        @test parse_document_string(format, make_document_string(format, document)).count == 3
    end

    @testset "a reference leaf holds its marker, and the string writes the marker" begin
        format = TallyFileFormat()
        leaf = make_reference_leaf(format, "file(\"b.tally\")")
        @test leaf isa TallyReference
        @test find_reference_marker(leaf) == "file(\"b.tally\")"
        @test make_document_string(format, leaf) == "<<file(\"b.tally\")>>"
        back = parse_document_string(format, make_document_string(format, leaf))
        @test back isa TallyReference && find_reference_marker(back) == "file(\"b.tally\")"
    end

    @testset "the seams with a default answer it, and a format can answer otherwise" begin
        format, log = TallyFileFormat(), TallyLogFileFormat()
        @test is_editable_file_format(format)
        @test !is_editable_file_format(log)
        @test is_written_in_file(format, TallyCount(count = 2), :count)
        @test !is_written_in_file(log, TallyCount(count = 2), :count)
        @test !is_written_inline(format, TallyReference(marker = "x"))
        @test is_written_inline(log, TallyReference(marker = "x"))
        # The default asks the domain of the format.
        @test is_file_domain_node(format, TallyCount(count = 1))
        @test is_file_domain_node(format, TallyReference(marker = "x"))
        @test !is_file_domain_node(format, 1)
        @test !is_file_domain_node(format, "|")
        @test is_file_domain_node(log, 1)
        @test is_file_domain_node(log, TallyCount(count = 1))
    end

    @testset "a file is read and made in its format" begin
        format = TallyFileFormat()
        folder = mktempdir()
        try
            path = joinpath(folder, "a.tally")
            write(path, "||||\n")
            content = read_file_content(format, path)
            @test content isa TallyCount && content.count == 4
            # A format of its own reads only what it needs.
            log_path = joinpath(folder, "run.log")
            write(log_path, "|||||\nmore lines\n")
            @test read_file_content(TallyLogFileFormat(), log_path).count == 5
        finally
            rm(folder; recursive = true)
        end
        file = make_file(format, "a.tally", "||")
        @test file isa TallyFile
        @test get_filename(file) == "a.tally"
        @test get_file_content(file) isa TallyCount && get_file_content(file).count == 2
        @test get_file_type(format) === TallyFile
        @test get_file_format(file) === format
        again = get_file_type(get_file_format(file))("b.tally", TallyCount(count = 5))
        @test again isa TallyFile && get_file_content(again).count == 5
    end

    @testset "the forms on a file type answer as before" begin
        @test make_file(TextFile, "a.txt", "x") isa TextFile
        @test get_file_content(make_file(TextFile, "a.txt", "x")) == "x"
        @test is_editable_file_type(TextFile)
        @test is_written_in_file(TextFile("a.txt", "x"), "x", :content)
        @test !is_written_inline(TextFile("a.txt", "x"), "x")
    end

    @testset "the session holds each format that a method declares, and no other type" begin
        formats = collect_file_formats()
        @test formats isa Vector{FileFormat}
        @test TallyFileFormat() in formats
        @test TallyLogFileFormat() in formats
        @test !any(format -> format isa TallyFieldFileFormat, formats)
        @test allunique(formats)
        @test issorted(formats; by = format -> String(nameof(typeof(format))))
    end

    @testset "a search finds a format by an extension, a path and a short name" begin
        format = TallyFileFormat()
        @test find_file_format(".tally") === format
        @test find_file_format(".TLY") === format
        @test find_file_format("notes/a.tally") === format
        @test find_file_format("notes/B.TLY") === format
        @test find_file_format(:tally) === format
        @test find_file_format(:TLY) === format
        @test find_file_format("a.no-such-extension") === nothing
        @test find_file_format(:nosuchextension) === nothing
        # A path with no extension does not name a format by its file name.
        @test find_file_format("tally") !== format
        # A type with a field is no format.
        @test find_file_format(".tally-field") === nothing
    end

    @testset "an extension that two formats declare is an error that names both" begin
        @eval SerializationModule.get_file_format_extensions(::TallyCopyFileFormat) = (".tly",)
        try
            message = try
                Base.invokelatest(find_file_format, "a.tly")
                ""
            catch e
                sprint(showerror, e)
            end
            @test occursin("more than one file format", message)
            @test occursin("TallyFileFormat", message) && occursin("TallyCopyFileFormat", message)
            @test Base.invokelatest(find_file_format, "a.tally") === TallyFileFormat()
        finally
            Base.delete_method(only(methods(get_file_format_extensions, Tuple{TallyCopyFileFormat})))
        end
        @test Base.invokelatest(find_file_format, "a.tly") === TallyFileFormat()
    end
end
end
