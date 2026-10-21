# A source file: its extension opens it as a `SourceFile` whose content is a
# marked text, and a save writes the text. In an editor, the acquire takes the
# server of the editor, the print shows the answer of the server, a key moves the
# colours of the text around it until the next answer, a server that is not
# installed leaves the text plain, and the release and the stop end the work of
# the server. One test opens a file with `clangd` when it is installed.

const _SF_SOURCE = "int main() {\n    int count = 0;\n    return count;\n}"

_sf_spans(marks) = [(mark.start, mark.stop, mark.text) for mark in marks]

const _SF_FUNCTION = ColorRole(:function_name)
const _SF_VARIABLE = ColorRole(:variable)

# The tokens of a text, as a server of C gives them: `main` is a function and
# `count` a variable, wherever they stand.
function _sf_tokens(text)
    found = Tuple{Int,Int,Int,Int}[]
    for (line, content) in enumerate(split(text, '\n'))
        for (word, kind) in (("main", 1), ("count", 0))
            for match in eachmatch(Regex("\\b$word\\b"), content)
                column = length(SubString(content, 1, prevind(content, match.offset)))
                push!(found, (line - 1, column, length(word), kind))
            end
        end
    end
    data = Int[]
    previous_line, previous_column = 0, 0
    for (line, column, token_length, kind) in sort!(found)
        delta_line = line - previous_line
        append!(data, (delta_line, delta_line == 0 ? column - previous_column : column, token_length, kind, 0))
        previous_line, previous_column = line, column
    end
    data
end

function _sf_editor(file)
    backend = HeadlessBackend()
    editor = build_editor(file, NaturalToGraphics(; measure = FontFileMeasure());
                          backend, devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, appearance = false, settings = false, tabs = false,
                          focus_cycling = false)
    _sf_frame!(editor, backend)
    (editor, backend)
end

# Apply what tasks posted to the editor, as its loop does, run a frame, and give
# the texts that it drew. The headless backend keeps the output and walks
# nothing, so this walk computes the cells of the output, as a paint does, and as
# the evaluation of the editor, so that a background cell that it reads asks the
# editor.
function _sf_frame!(editor, backend)
    drain_operations!(editor)
    run_frame!(editor)
    run_with_evaluation_editor(editor) do
        _sf_drawn_texts(last(rendered_output(backend)))
    end
end

# Run frames until `condition()` holds, at most `timeout` seconds.
function _sf_wait(condition, editor, backend; timeout = 20.0)
    deadline = time() + timeout
    while time() < deadline
        _sf_frame!(editor, backend)
        condition() && return true
        sleep(0.01)
    end
    false
end

# Every text that a frame drew, with its colour.
function _sf_drawn_texts(node, found = Tuple{String,Any}[])
    node = node isa AbstractCell ? node[] : node
    if node isa GraphicsCanvas
        foreach(element -> _sf_drawn_texts(element, found), node.elements)
    elseif node isa GraphicsViewport
        _sf_drawn_texts(node.content, found)
    elseif node isa ScrollLayout
        for part in SCROLL_LAYOUT_PARTS
            content = getproperty(node, part)
            content === nothing || _sf_drawn_texts(content, found)
        end
    elseif node isa GraphicsText
        push!(found, (String(node.text), node.color))
    end
    found
end

# Give the editor the server of the command of `path` before the acquire takes it.
function _sf_give_server!(editor, path, connection)
    servers = get_session_document!(LanguageServers, editor, LanguageServers)
    servers.connections[find_source_file_language(path).command] = connection
end

function test_source_file()
@testset "SourceFile" begin

@testset "a C or C++ extension opens as a source file whose content is a marked text" begin
    for extension in (".c", ".h", ".cc", ".cpp", ".cxx", ".hh", ".hpp", ".hxx", ".CC")
        @test get_file_document_type("a" * extension) === SourceFile
    end
    directory = mktempdir()
    path = joinpath(directory, "hello.cc")
    write(path, _SF_SOURCE)
    file = make_file_tab(path)
    @test file isa SourceFile
    @test file.content isa MarkedText
    @test file.content.text == _SF_SOURCE
    file.content.text = replace(_SF_SOURCE, "count" => "total")
    @test emit_text(file) == replace(_SF_SOURCE, "count" => "total")
end

@testset "a file that no tab acquired has no server and no marks" begin
    file = SourceFile("/projectured/hello.c", MarkedText(text = _SF_SOURCE))
    @test file.server === nothing
    @test isempty(file.content.marks)
end

@testset "in an editor, the names take the colours of the answer of the server" begin
    server, connection = start_fake_language_server(token_types = ["variable", "function"], tokens = _sf_tokens)
    path = "/projectured/hello.c"
    file = SourceFile(path, MarkedText(text = _SF_SOURCE))
    editor, backend = _sf_editor(file)
    _sf_give_server!(editor, path, connection)
    acquire_document!(editor, file)
    @test file.server === connection
    # The marks are final while the answer is to come: a provisional value would
    # compute again at each read, once for each line of the view.
    _sf_frame!(editor, backend)
    @test !is_cell_provisional(getfield(file.content, :marks))
    expected = [(4, 8, _SF_FUNCTION), (21, 26, _SF_VARIABLE), (43, 48, _SF_VARIABLE)]
    @test _sf_wait(() -> _sf_spans(file.content.marks) == expected, editor, backend)
    opened = only(get_fake_messages(server, "textDocument/didOpen"))
    @test opened["params"]["textDocument"]["languageId"] == "c"
    drawn = _sf_frame!(editor, backend)
    @test ("main", resolve_theme_color(_SF_FUNCTION, Appearance())) in drawn

    # A key moves the marks after it at once, and the answer for the new text
    # comes in a later frame.
    set_selection!(editor.document, annotate_reference_types(editor.document,
        Reference(FieldReferenceStep("content"), FieldReferenceStep("text"), RangeReferenceStep(29, 29))))
    _sf_frame!(editor, backend)
    push_event!(backend, KeyPress('1'; time = 0.0))
    _sf_frame!(editor, backend)
    @test file.content.text == replace(_SF_SOURCE, "= 0" => "= 10")
    moved = [(4, 8, _SF_FUNCTION), (21, 26, _SF_VARIABLE), (44, 49, _SF_VARIABLE)]
    @test _sf_spans(file.content.marks) == moved
    @test !is_cell_provisional(getfield(file.content, :marks))
    @test _sf_wait(() -> !isempty(get_fake_messages(server, "textDocument/didChange")), editor, backend)
    changed = last(get_fake_messages(server, "textDocument/didChange"))
    @test changed["params"]["textDocument"]["version"] == 2
    @test _sf_wait(() -> _sf_spans(file.content.marks) == moved, editor, backend)

    # The release closes the file in the server, and the stop of the editor stops it.
    release_document!(editor, file)
    @test file.server === nothing
    @test timedwait(() -> !isempty(get_fake_messages(server, "textDocument/didClose")), 5.0) === :ok
    @test any(step -> step === stop_language_servers!, editor.stop_steps)
    stop_language_servers!(editor)
    @test length(get_fake_messages(server, "shutdown")) == 1
    @test !is_language_server_running(connection)
end

@testset "a reload of a file in a history keeps its text object, and the colours follow" begin
    server, connection = start_fake_language_server(token_types = ["variable", "function"], tokens = _sf_tokens)
    path = "/projectured/reload.c"
    marked = MarkedText(text = _SF_SOURCE)
    file = SourceFile(path, UndoBuffer(marked))
    editor, backend = _sf_editor(file)
    _sf_give_server!(editor, path, connection)
    acquire_document!(editor, file)
    @test _sf_wait(() -> length(file.content.content.marks) == 3, editor, backend)
    # The file on disk got a line before the code.
    evaluate_operation(editor, ReloadFileOperation(file; content = MarkedText(text = "// x\n" * _SF_SOURCE)))
    @test file.content.content === marked
    @test marked.text == "// x\n" * _SF_SOURCE
    @test _sf_wait(() -> _sf_spans(marked.marks) ==
                   [(9, 13, _SF_FUNCTION), (26, 31, _SF_VARIABLE), (48, 53, _SF_VARIABLE)], editor, backend)
    stop_language_servers!(editor)
end

@testset "a server that is not installed leaves the text plain" begin
    path = "/projectured/plain.c"
    file = SourceFile(path, MarkedText(text = _SF_SOURCE))
    editor, backend = _sf_editor(file)
    connection = LanguageServerConnection(["projectured-no-such-language-server"])
    _sf_give_server!(editor, path, connection)
    acquire_document!(editor, file)
    @test _sf_wait(() -> connection.failure !== nothing, editor, backend)
    drawn = nothing
    for _ in 1:5
        drawn = _sf_frame!(editor, backend)
    end
    @test isempty(file.content.marks)
    @test any(entry -> entry[1] == "int main() {", drawn)
end

@testset "clangd colours a C file in an editor" begin
    if Sys.which("clangd") === nothing
        @test_skip "clangd is not installed"
    else
        directory = mktempdir()
        path = joinpath(directory, "hello.c")
        write(path, _SF_SOURCE)
        file = make_file_tab(path)
        editor, backend = _sf_editor(file)
        acquire_document!(editor, file)
        expected = [(4, 8, _SF_FUNCTION), (21, 26, _SF_VARIABLE), (43, 48, _SF_VARIABLE)]
        try
            @test _sf_wait(() -> issubset(expected, _sf_spans(file.content.marks)), editor, backend)
        finally
            stop_language_servers!(editor)
        end
        @test !is_language_server_running(file.server)
    end
end

end # @testset
end
