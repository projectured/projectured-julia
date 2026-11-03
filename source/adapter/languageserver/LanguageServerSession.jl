# Fragment of `LanguageServerModule` — the language servers of one editor: one
# connection for each command, made at the first file that needs it, and stopped
# when the loop of the editor ends.

"""
    LanguageServers

The language servers of one editor, a session document of the editor: one
`LanguageServerConnection` for each command, by its command. A server is per
editor, because it holds one text of each file, and two editors can hold two
texts of one file.

`compile_command` is a `Ref` that holds the function from a path to its compile
command (`LanguageServerConnection`), or `nothing`; each connection that
`get_language_server!` makes gets what it holds at that time.
"""
struct LanguageServers
    connections::Dict{Vector{String}, LanguageServerConnection}
    lock::ReentrantLock
    compile_command::Ref{Any}
end

LanguageServers() = LanguageServers(Dict{Vector{String}, LanguageServerConnection}(), ReentrantLock(),
                                    Ref{Any}(nothing))

"""
    get_language_server!(editor, command) -> LanguageServerConnection

The connection of `editor` to the server that `command` starts, made at the
first call for that command, with the compile command function of the editor. It starts nothing: the connection starts its
process at its first use, off the loop.
"""
function get_language_server!(editor, command::AbstractVector{<:AbstractString})
    servers = get_session_document!(LanguageServers, editor, LanguageServers)
    key = String.(command)
    lock(() -> get!(() -> LanguageServerConnection(key; compile_command = servers.compile_command[]),
                       servers.connections, key), servers.lock)
end

"""
    stop_language_servers!(editor)

Stop every language server of `editor` (`stop_language_server!`). The stop step
of the wrapper `language_server` of `build_editor` calls it when the loop of
the editor ends.
"""
function stop_language_servers!(editor)
    servers = get_session_document!(LanguageServers, editor, LanguageServers)
    connections = lock(() -> collect(values(servers.connections)), servers.lock)
    foreach(stop_language_server!, connections)
    nothing
end

"""
The wrapper of `build_editor` that stops the language servers of the editor
when its loop ends. It is on by default, because an editor with no source file
starts no server and its stop does nothing.

The argument `(; compile_command = f)` gives each server of the editor the
function `f` from the path of a file to its compile command, or to `nothing`
(`LanguageServerConnection`). With the argument `true` there is none.
"""
function wrap_editor!(::Val{:language_server}, layer::Symbol, argument, parts::EditorParts)
    compile_command = argument isa NamedTuple ? get(argument, :compile_command, nothing) : nothing
    compile_command === nothing || push!(parts.start_steps, editor ->
        (get_session_document!(LanguageServers, editor, LanguageServers).compile_command[] = compile_command; nothing))
    push!(parts.stop_steps, stop_language_servers!)
    parts
end

get_wrapper_layers(::Val{:language_server}) = (:screen => 20,)
is_wrapper_default(::Val{:language_server}) = true
