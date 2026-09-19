# ──────────────────────────────────────────────────────────────────────────
# The binaries of this repository.
#
# A build function says what goes into one binary: the packages, the body of
# `julia_main`, the workload and the command line. It names the packages as
# strings, so this file loads none of them; the build finds each one in the
# repository and writes a package that holds them.
# ──────────────────────────────────────────────────────────────────────────

"""
    PROJECTURED_BACKENDS

The backends a `projectured` binary can hold: each name, with the package that
defines the backend and the type that `--backend` makes.
"""
const PROJECTURED_BACKENDS = (sdl = ("ProjecturedSdl", :SdlBackend),
                              web = ("ProjecturedWeb", :WebBackend))

"""
    PROJECTURED_OPTIONS

The options of the `projectured` command that every build takes, as
`"--option=value" => "what it does"`. `--backend` is added when a build holds
more than one backend. The builder writes its own four options after these.
"""
const PROJECTURED_OPTIONS = [
    "--assistant=ollama|anthropic|none" =>
        "the model backend of the assistant (ollama by\ndefault), or no assistant",
    "--model=NAME" => "the model of that backend (default: the default\nmodel of the backend)",
    "--root=DIRECTORY" => "the directory that the navigator lists (default:\nthe current directory)",
    "--mcp" => "start an MCP server at http://127.0.0.1:9876/mcp",
    "--context=TOKENS" => "how many tokens of the conversation the model may\nsee (default: the default of the backend)",
    "--gesture-log" => "list the last gestures and what each one did, in a\ncorner of the window",
]

"""
    PROJECTURED_REQUIREMENTS

What a machine needs to run a `projectured` distribution, as the lines of its
README.
"""
const PROJECTURED_REQUIREMENTS = [
    "Linux on x86-64.",
    "A display for the native window, or a web browser with --backend=web.",
    "For the assistant: an Ollama server with a pulled model, or an Anthropic " *
        "API key in the environment variable ANTHROPIC_API_KEY.",
]

"""
    PROJECTURED_LICENCES

The licence files of the repository, which the archive of a distribution
carries. `LICENCE-PD` asks for its notice in every copy, so an archive without
it may not be distributed.
"""
const PROJECTURED_LICENCES = ["LICENCE-PD", "LICENCE-COMMERCIAL"]

"""
    PROJECTURED_ASSETS

The folders of the repository that a `projectured` binary reads while it runs,
as `"<folder>" => "<folder in the bundle>"`: the web client, and the guides
that the assistant reads. The binary reads them from the bundle.
"""
const PROJECTURED_ASSETS = ["asset/web" => "share/projectured/web",
                            "documentation" => "share/projectured/documentation"]

"""
    make_projectured_usage(backends) -> Usage

The `--help` text of a `projectured` binary that holds `backends`.
"""
function make_projectured_usage(backends)
    options = copy(PROJECTURED_OPTIONS)
    if length(backends) > 1
        insert!(options, 2, "--backend=" * join(String.(backends), "|") =>
            "where the window is drawn (default: $(first(backends)))")
    end
    Usage("Open files in a window, with a file navigator and an AI assistant.\n" *
          "A file opens in the format that its extension names.";
          synopsis = "[options] [files...]", options = options)
end

"""
    build_projectured_executable(; name = "projectured", backends = (:sdl, :web),
                                 workload = true,
                                 context = make_projectured_build_context(),
                                 kwargs...) -> String

Build the ProjecturEd application, and answer the directory of the bundle,
`build/<name>/`, with the executable in `bin/<name>`.

- `backends` names the backends the binary holds, from
  [`PROJECTURED_BACKENDS`](@ref). The first one is the default; with more than
  one, `--backend` chooses.
- `workload` runs the application once without a window while the image
  compiles, so the first frames of a real start need no compilation.
- Every other keyword goes to [`build_executable`](@ref), for example
  `compile = false` to write the package and compile nothing, or
  `incremental = false` for a fresh image.

The binary holds the example package, which holds every domain, both assistant
backends and the application, and the MCP server.
"""
function build_projectured_executable(; name::AbstractString = "projectured",
                                        backends = (:sdl, :web),
                                        workload::Bool = true,
                                        context::BuildContext = make_projectured_build_context(),
                                        kwargs...)
    isempty(backends) && error("build_projectured_executable: name at least one backend")
    for backend in backends
        haskey(PROJECTURED_BACKENDS, backend) ||
            error("build_projectured_executable: the backends are " *
                  join(keys(PROJECTURED_BACKENDS), ", ") * ", not $(repr(backend))")
    end
    backend_packages = [first(PROJECTURED_BACKENDS[backend]) for backend in backends]
    # `(sdl = ProjecturedSdl.SdlBackend, …)`, in the order the build names them,
    # so the first one is the default of the command line.
    table = Expr(:tuple, [Expr(:(=), backend,
                               Expr(:., Symbol(first(PROJECTURED_BACKENDS[backend])),
                                    QuoteNode(last(PROJECTURED_BACKENDS[backend]))))
                          for backend in backends]...)
    main = :(ProjecturedExample.run_application_command(ARGS; backends = $table))
    build_executable(context; name = name,
                     packages = vcat(["ProjecturedExample", "ProjecturedMcp"], backend_packages),
                     main = main,
                     workload = workload ? :(ProjecturedExample.warm_application()) : nothing,
                     usage = make_projectured_usage(collect(backends)),
                     fonts = true,
                     assets = PROJECTURED_ASSETS,
                     kwargs...)
end

"""
    build_projectured_distribution(; name = "projectured", kwargs...) -> String

Build the application for other machines, check that the copy runs outside
this checkout, and write it as an archive with a README. Answer the path of the
archive. [`check_projectured_copy`](@ref) is the check.

The image is fresh and holds code for several processor families, as a
distribution must. The keywords go to
[`build_projectured_executable`](@ref).
"""
function build_projectured_distribution(; name::AbstractString = "projectured",
                                          context::BuildContext = make_projectured_build_context(),
                                          kwargs...)
    get(kwargs, :compile, true) ||
        error("build_projectured_distribution: a distribution needs a compiled bundle")
    bundle = build_projectured_executable(; name = name, context = context,
                                          incremental = false,
                                          cpu_target = PORTABLE_CPU_TARGET,
                                          kwargs...)
    build_distribution(context; name = name, bundle = bundle,
                       requirements = PROJECTURED_REQUIREMENTS,
                       licences = PROJECTURED_LICENCES,
                       expect = vcat(["share/projectured/font"], last.(PROJECTURED_ASSETS)),
                       check = check_projectured_copy)
end

const _CHECK_WEB = "http://127.0.0.1:8080"
const _CHECK_MCP = "http://127.0.0.1:9876/mcp"

"""
    check_projectured_copy(executable, directory, hidden) -> Nothing

Start a copied `projectured` with the web backend and the MCP server, with the
folders in `hidden` out of its sight, and check the files that it reads from
its bundle:

- the web client and a font, through the web server at port 8080;
- the list of guides, through the tool `read_resource` of the MCP server at
  port 9876.

The check opens no window and starts no assistant. It fails when one of the
two ports is in use.
"""
function check_projectured_copy(executable::AbstractString, directory::AbstractString, hidden)
    for url in (_CHECK_WEB, _CHECK_MCP)
        _is_http_free(url) ||
            error("check_projectured_copy: a program uses $url, and the check needs it")
    end
    file = joinpath(directory, "check.json")
    write(file, "{\"name\": \"check\"}")
    log = joinpath(directory, "check.log")
    depot = mktempdir()
    environment = copy(ENV)
    environment["JULIA_DEPOT_PATH"] = depot
    environment["JULIA_LOAD_PATH"] = ""
    command = make_hidden_command(`$executable --backend=web --mcp --assistant=none $file`, hidden)
    output = open(log, "w")
    process = run(pipeline(setenv(command, environment; dir = directory);
                           stdout = output, stderr = output); wait = false)
    try
        for url in (_CHECK_WEB, _CHECK_MCP)
            _wait_for_http(url, process, log)
        end
        occursin("<html", lowercase(_read_http("$_CHECK_WEB/"))) ||
            error("check_projectured_copy: the copy serves no web client")
        isempty(_read_http("$_CHECK_WEB/client.js")) &&
            error("check_projectured_copy: the copy serves an empty client.js")
        font = match(r"\"fonts\"\s*:\s*\[\s*\"([^\"]+)\"", _read_http("$_CHECK_WEB/fonts.json"))
        font === nothing && error("check_projectured_copy: the copy finds no font")
        sizeof(_read_http("$_CHECK_WEB/font/$(font.captures[1])")) > 1000 ||
            error("check_projectured_copy: the copy serves no data for $(font.captures[1])")
        guides = _call_mcp_tool("read_resource", "{\"uri\": \"resource://guides\"}")
        occursin("design/concepts", guides) ||
            error("check_projectured_copy: the list of guides of the copy does not name " *
                  "design/concepts:\n" * guides)
        @info "The copy reads the web client, the fonts and the guides from its bundle"
    finally
        kill(process)
        timedwait(() -> !process_running(process), 10.0)
        process_running(process) && kill(process, Base.SIGKILL)
        close(output)
        rm(depot; recursive = true, force = true)
    end
    deadline = time() + 10
    while !all(_is_http_free, (_CHECK_WEB, _CHECK_MCP))
        time() < deadline ||
            error("check_projectured_copy: the copy still answers after it was stopped")
        sleep(0.5)
    end
    nothing
end

# Whether no program answers at `url`. curl ends with 7 when nothing listens.
function _is_http_free(url::AbstractString)
    run(ignorestatus(`curl -s -o /dev/null --max-time 5 $url`)).exitcode == 7
end

# The body at `url`, or "" when the answer is not a success.
function _read_http(url::AbstractString)
    read(ignorestatus(`curl -sf --max-time 30 $url`), String)
end

# Wait until a program answers at `url`, with any status, for two minutes at most.
function _wait_for_http(url::AbstractString, process, log::AbstractString)
    deadline = time() + 120
    while time() < deadline
        process_running(process) ||
            error("check_projectured_copy: the copy stopped:\n" * read(log, String))
        _is_http_free(url) || return nothing
        sleep(0.5)
    end
    error("check_projectured_copy: nothing answers at $url after two minutes:\n" *
          read(log, String))
end

# Call one tool of the MCP server, and answer the text of the reply.
function _call_mcp_tool(name::AbstractString, arguments::AbstractString)
    options = ["-sf", "--max-time", "30", "-H", "Content-Type: application/json",
               "-H", "Accept: application/json, text/event-stream"]
    headers = tempname()
    initialize = """{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": """ *
                 """{"protocolVersion": "2025-06-18", "capabilities": {}, """ *
                 """"clientInfo": {"name": "check", "version": "0"}}}"""
    read(`curl $options -D $headers -d $initialize $_CHECK_MCP`, String)
    session = match(r"(?im)^mcp-session-id:\s*(\S+)", read(headers, String))
    rm(headers; force = true)
    session === nothing || append!(options, ["-H", "Mcp-Session-Id: $(session.captures[1])"])
    initialized = """{"jsonrpc": "2.0", "method": "notifications/initialized"}"""
    read(`curl $options -d $initialized $_CHECK_MCP`, String)
    call = """{"jsonrpc": "2.0", "id": 2, "method": "tools/call", """ *
           """"params": {"name": "$name", "arguments": $arguments}}"""
    read(`curl $options -d $call $_CHECK_MCP`, String)
end
