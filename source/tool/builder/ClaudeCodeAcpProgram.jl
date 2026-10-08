# Fragment of `BuilderModule` — the build of `claude-code-acp`, the program of the
# package ClaudeCodeACP: an agent of the Agent Client Protocol that runs Claude
# Code, for an editor that starts agents as programs.

"""
    CLAUDE_CODE_ACP_WORKLOAD

What the build of `claude-code-acp` runs while its image compiles: the agent
serves a client in the process through `initialize`, on two streams, so the
first answer of the binary needs no compilation. It starts no `claude`.
"""
const CLAUDE_CODE_ACP_WORKLOAD = quote
    ACP = ClaudeCodeACP.ACP
    to_agent, to_client = Base.BufferStream(), Base.BufferStream()
    agent = @async ClaudeCodeACP.serve_agent(; input = to_agent, output = to_client)
    connection = ACP.open_connection(nothing, to_client, to_agent)
    ACP.send_request!(connection, ACP.InitializeRequest(protocol_version = ACP.PROTOCOL_VERSION); timeout = 60)
    ACP.close_connection!(connection)
    wait(agent)
end

"""
    make_claude_code_acp_build_context(source; context = make_projectured_build_context()) -> BuildContext

The context of the build of `claude-code-acp`: the packages of this repository,
and `source`, the folder of the package ClaudeCodeACP, as one more root.
"""
make_claude_code_acp_build_context(source::AbstractString;
                                   context::BuildContext = make_projectured_build_context()) =
    BuildContext(context.root; package_roots = vcat(context.package_roots, abspath(source)),
                 log_variable = "CLAUDE_CODE_ACP_LOG_LEVEL", statements = context.statements,
                 version = context.version)

"""
    build_claude_code_acp_executable(; name = "claude-code-acp", source, workload = true,
                                     context = make_claude_code_acp_build_context(source),
                                     kwargs...) -> String

Build the program `claude-code-acp` of the package ClaudeCodeACP, and answer the
directory of the bundle, `build/<name>/`, with the executable in `bin/<name>`.
An editor such as Zed starts it as an agent of the Agent Client Protocol; it
runs the `claude` program that the person installed.

- `source` is the folder of the package, by default the folder
  `claude-code-acp` beside this repository, where `environment/all` finds it
  too.
- `workload` serves a client in the process through `initialize` while the
  image compiles; see [`CLAUDE_CODE_ACP_WORKLOAD`](@ref).
- Every other keyword goes to [`build_executable`](@ref), for example
  `compile = false` to write the package and compile nothing.

The program reads its own command line, `--help` and `--login` among it, so
the build gives no `Usage`.
"""
function build_claude_code_acp_executable(; name::AbstractString = "claude-code-acp",
                                            source::AbstractString = joinpath(
                                                dirname(make_projectured_build_context().root),
                                                "claude-code-acp"),
                                            workload::Bool = true,
                                            context::BuildContext = make_claude_code_acp_build_context(source),
                                            kwargs...)
    has_package_directory(context, "ClaudeCodeACP") ||
        error("build_claude_code_acp_executable: no package ClaudeCodeACP in $(source)")
    build_executable(context; name = name, packages = ["ClaudeCodeACP"],
                     main = :(ClaudeCodeACP.main(ARGS)),
                     workload = workload ? CLAUDE_CODE_ACP_WORKLOAD : nothing,
                     usage = nothing, kwargs...)
end
