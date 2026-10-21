# The semantic tokens of a text: the relative encoding of the protocol becomes
# marks that count the characters of the text, the text goes to the server as an
# open and then as changes, and `clangd` colours the names of a C file when it
# is installed.

const _ST_SOURCE = "int main() {\n    int count = 0;\n    return count;\n}"

_st_spans(marks) = [(mark.start, mark.stop, mark.text) for mark in marks]

function test_semantic_tokens()
@testset "semantic tokens" begin

@testset "the relative encoding becomes marks of the text" begin
    data = [0, 4, 4, 1, 3,   1, 8, 5, 0, 3,   1, 11, 5, 0, 0]
    marks = convert_semantic_tokens(data, _ST_SOURCE, ["variable", "function"], "utf-32")
    @test _st_spans(marks) == [(4, 8, ColorRole(:function_name)), (21, 26, ColorRole(:variable)),
                               (43, 48, ColorRole(:variable))]
end

@testset "two tokens on one line count the column from the token before" begin
    marks = convert_semantic_tokens([0, 0, 1, 0, 0,   0, 4, 1, 0, 0], "a = b", ["variable"], "utf-32")
    @test _st_spans(marks) == [(0, 1, ColorRole(:variable)), (4, 5, ColorRole(:variable))]
end

@testset "a kind with no role and a token past the last line get no mark" begin
    marks = convert_semantic_tokens([0, 0, 3, 1, 0,   9, 0, 1, 0, 0], "abc", ["variable", "unknown"], "utf-32")
    @test isempty(marks)
end

@testset "a UTF-16 column counts a character beyond the basic plane as two units" begin
    text = "a😀b x"
    @test _st_spans(convert_semantic_tokens([0, 5, 1, 0, 0], text, ["variable"], "utf-16")) ==
          [(4, 5, ColorRole(:variable))]
    @test _st_spans(convert_semantic_tokens([0, 4, 1, 0, 0], text, ["variable"], "utf-32")) ==
          [(4, 5, ColorRole(:variable))]
end

@testset "the text goes to the server as an open, then as a change, then a close" begin
    tokens(text) = occursin("main", text) ? [0, 4, 4, 1, 0] : Int[]
    server, connection = start_fake_language_server(tokens = tokens)
    path = "/projectured/a.c"
    @test _st_spans(compute_semantic_text_marks(connection, path, "c", "int main() {}")) ==
          [(4, 8, ColorRole(:function_name))]
    @test isempty(compute_semantic_text_marks(connection, path, "c", "int other() {}"))
    opened = only(get_fake_messages(server, "textDocument/didOpen"))
    @test opened["params"]["textDocument"]["languageId"] == "c"
    @test opened["params"]["textDocument"]["version"] == 1
    changed = only(get_fake_messages(server, "textDocument/didChange"))
    @test changed["params"]["textDocument"]["version"] == 2
    @test server.texts[make_file_uri(path)] == "int other() {}"
    close_language_server_document!(connection, path)
    @test timedwait(() -> !isempty(get_fake_messages(server, "textDocument/didClose")), 5.0) === :ok
    @test isempty(connection.documents)
    # After the close, the file opens again as its first version.
    compute_semantic_text_marks(connection, path, "c", "int main() {}")
    @test length(get_fake_messages(server, "textDocument/didOpen")) == 2
    stop_language_server!(connection)
end

@testset "clangd colours the names of a C file" begin
    if Sys.which("clangd") === nothing
        @test_skip "clangd is not installed"
    else
        directory = mktempdir()
        path = joinpath(directory, "hello.c")
        write(path, _ST_SOURCE)
        connection = LanguageServerConnection(["clangd", "--log=error"]; directory)
        try
            marks = compute_semantic_text_marks(connection, path, "c", _ST_SOURCE)
            found = Dict((mark.start, mark.stop) => mark.text for mark in marks)
            @test get(found, (4, 8), nothing) == ColorRole(:function_name)
            @test get(found, (21, 26), nothing) == ColorRole(:variable)
            @test get(found, (43, 48), nothing) == ColorRole(:variable)
            @test connection.position_encoding == "utf-32"
        finally
            stop_language_server!(connection)
        end
        @test !is_language_server_running(connection)
    end
end

@testset "a clangd that ended starts again, and the file opens again" begin
    if Sys.which("clangd") === nothing
        @test_skip "clangd is not installed"
    else
        directory = mktempdir()
        path = joinpath(directory, "again.c")
        write(path, _ST_SOURCE)
        connection = LanguageServerConnection(["clangd", "--log=error"]; directory)
        try
            @test length(compute_semantic_text_marks(connection, path, "c", _ST_SOURCE)) == 3
            kill(connection.process)
            @test timedwait(() -> !is_language_server_running(connection), 10.0) === :ok
            @test length(compute_semantic_text_marks(connection, path, "c", _ST_SOURCE)) == 3
            @test connection.documents[make_file_uri(path)] == 1
        finally
            stop_language_server!(connection)
        end
    end
end

end # @testset
end
