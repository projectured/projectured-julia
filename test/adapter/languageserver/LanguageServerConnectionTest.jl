# The connection to a language server: the start and the agreement on the
# protocol, a request and its answer, a request and a notification of the server,
# a request with no answer, the end of the server, and the stop. A server in this
# process answers; one test starts a command that is not installed.

function test_language_server_connection()
@testset "LanguageServerConnection" begin

@testset "the start agrees on the protocol and reads the legend" begin
    server, connection = start_fake_language_server(token_types = ["variable", "function", "macro"])
    @test !is_language_server_running(connection)
    start_language_server!(connection)
    @test is_language_server_running(connection)
    @test connection.position_encoding == "utf-32"
    @test connection.token_types == ["variable", "function", "macro"]
    initialize = only(get_fake_messages(server, "initialize"))
    @test initialize["params"]["capabilities"]["general"]["positionEncodings"] == ["utf-32", "utf-16"]
    @test length(get_fake_messages(server, "initialized")) == 1
    # A second start does nothing.
    start_language_server!(connection)
    @test length(get_fake_messages(server, "initialize")) == 1
    stop_language_server!(connection)
end

@testset "a server that names no encoding counts UTF-16 units" begin
    server, connection = start_fake_language_server(encoding = nothing)
    start_language_server!(connection)
    @test connection.position_encoding == "utf-16"
    stop_language_server!(connection)
end

@testset "a request gets its answer, and an error answer throws" begin
    server, connection = start_fake_language_server()
    @test send_language_server_request!(connection, "test/echo", Dict("a" => [1, 2])) == Dict("a" => [1, 2])
    error = try
        send_language_server_request!(connection, "test/fail", Dict{String, Any}())
        nothing
    catch exception
        exception
    end
    @test error isa LanguageServerException
    @test occursin("test/fail", error.message)
    stop_language_server!(connection)
end

@testset "a request of the server gets an error answer, and a notification is dropped" begin
    server, connection = start_fake_language_server(ask = true)
    start_language_server!(connection)
    @test send_language_server_request!(connection, "test/echo", 7) == 7
    answers = [m for m in server.received if get(m, "id", nothing) == 900]
    @test length(answers) == 1
    @test answers[1]["error"]["code"] == -32601
    stop_language_server!(connection)
end

@testset "a request with no answer ends at its timeout" begin
    server, connection = start_fake_language_server()
    start_language_server!(connection)
    @test_throws LanguageServerException send_language_server_request!(connection, "test/silent", nothing;
                                                                       timeout = 0.2)
    @test isempty(connection.waits)
    # The connection still works.
    @test send_language_server_request!(connection, "test/echo", "x") == "x"
    stop_language_server!(connection)
end

@testset "the end of the server ends a request that waits" begin
    server, connection = start_fake_language_server()
    start_language_server!(connection)
    waiting = Threads.@spawn try
        send_language_server_request!(connection, "test/silent", nothing; timeout = 30)
    catch exception
        exception
    end
    timedwait(() -> !isempty(get_fake_messages(server, "test/silent")), 5.0)
    close(server.to_client)
    @test timedwait(() -> istaskdone(waiting), 5.0) === :ok
    @test fetch(waiting) isa LanguageServerException
    @test !is_language_server_running(connection)
end

@testset "the stop asks for a shutdown and an exit, and the connection stays stopped" begin
    server, connection = start_fake_language_server()
    start_language_server!(connection)
    stop_language_server!(connection)
    @test length(get_fake_messages(server, "shutdown")) == 1
    @test length(get_fake_messages(server, "exit")) == 1
    @test !haskey(only(get_fake_messages(server, "shutdown")), "params")
    @test !is_language_server_running(connection)
    @test_throws LanguageServerException start_language_server!(connection)
end

@testset "a command that is not installed fails once, and is not tried again" begin
    connection = LanguageServerConnection(["projectured-no-such-language-server"])
    first_failure = try start_language_server!(connection); nothing catch exception; exception end
    @test first_failure isa LanguageServerException
    @test occursin("not installed", first_failure.message)
    second_failure = try start_language_server!(connection); nothing catch exception; exception end
    @test second_failure === first_failure
end

@testset "a file URI encodes each byte that a path part can not hold" begin
    @test make_file_uri("/home/me/a.cc") == "file:///home/me/a.cc"
    @test make_file_uri("/home/me/my file#1.cc") == "file:///home/me/my%20file%231.cc"
    @test make_file_uri("/tmp/é.h") == "file:///tmp/%C3%A9.h"
end

end # @testset
end
