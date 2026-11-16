"""
    test_file_format_contract()

The contract of each file format of the session, with every domain loaded. For
each format of `collect_file_formats()`: its extensions are lower-case strings
with a dot, or `""`, and each names the format again; its domain is a type; and a
file of its file type gives the format back. For each text of
`make_workload_file`: the format of its name parses it, prints the document, and
reads the printed string back to a document that prints the same string. A
format with no workload text is named in a list, so a new format is not skipped
without a word.
"""
function test_file_format_contract()
@testset "FileFormat: the contract of each format of the session" begin
    formats = collect_file_formats()
    rows = [make_workload_file(type) for type in collect_workload_file_types()]
    # A picture and a source file have no workload text; `TallyFileFormat` and
    # `TallyLogFileFormat` are the formats of `FileFormatTest.jl`.
    formats_without_workload = [:ImageFileFormat, :SourceFileFormat,
                                :TallyFileFormat, :TallyLogFileFormat]

    @testset "no two formats declare one extension" begin
        declared = [extension for format in formats
                              for extension in get_file_format_extensions(format)]
        @test allunique(declared)
    end

    folder = mktempdir()
    try
        for format in formats
            @testset "$(nameof(typeof(format))): extensions, domain and file type" begin
                extensions = get_file_format_extensions(format)
                @test extensions isa Tuple
                @test allunique(extensions)
                for extension in extensions
                    @test extension isa String
                    @test extension == lowercase(extension)
                    @test extension == "" || (startswith(extension, ".") && length(extension) > 1)
                    @test find_file_format(extension) === format
                    @test find_file_format(joinpath("notes", "a" * uppercase(extension))) === format
                    isempty(extension) || @test find_file_format(Symbol(extension[2:end])) === format
                end
                @test get_file_format_domain(format) isa Type
                if hasmethod(get_file_type, Tuple{typeof(format)})
                    # The file of the first extension, with the workload text of
                    # the format, or with no text.
                    name = "a" * (isempty(extensions) ? "" : first(extensions))
                    row = findfirst(row -> find_file_format(row.name) === format, rows)
                    path = joinpath(folder, name)
                    write(path, row === nothing ? "" : rows[row].text)
                    file = get_file_type(format)(name, read_file_content(format, path))
                    @test file isa get_file_type(format)
                    @test get_file_format(file) === format
                end
            end
        end
    finally
        rm(folder; recursive = true)
    end

    for row in rows
        @testset "$(row.name) of the workload: parse, print, and parse the print" begin
            format = find_file_format(row.name)
            @test format isa FileFormat
            if format isa FileFormat
                # The printer of the format where it declares one, and the printer
                # of its file otherwise.
                is_declared(document) =
                    hasmethod(make_document_string, Tuple{typeof(format), typeof(document)})
                make_string(document) =
                    is_declared(document) ? make_document_string(format, document) :
                                            emit_text(get_file_type(format)(row.name, document))
                document = parse_document_string(format, row.text)
                domain = get_file_format_domain(format)
                domain === Union{} || @test document isa domain
                printed = make_string(document)
                @test printed isa String
                again = parse_document_string(format, printed)
                @test make_string(again) == printed
                # A format that declares its string writes what its file writes,
                # without the line break that the write of a file adds.
                if is_declared(document)
                    @test emit_text(get_file_type(format)(row.name, document)) in
                          (printed, printed * "\n")
                end
            end
        end
    end

    @testset "each format with no workload text is named" begin
        with_workload = [find_file_format(row.name) for row in rows]
        found = sort!([nameof(typeof(format)) for format in formats if !(format in with_workload)])
        @test found == sort(formats_without_workload)
    end
end
end
