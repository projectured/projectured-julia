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
    "--window=pane|workbench" =>
        "the window: tabs in split panes (the default), or\nthe workbench",
    "--assistant=ollama|anthropic|none" =>
        "the model backend of the assistant (ollama by\ndefault), or no assistant",
    "--model=NAME" => "the model of that backend (default: the default\nmodel of the backend)",
    "--root=DIRECTORY" => "the directory that the navigator lists (default:\nthe current directory)",
    "--mcp" => "start an MCP server at http://127.0.0.1:9876/mcp",
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
                     kwargs...)
end

"""
    build_projectured_distribution(; name = "projectured", kwargs...) -> String

Build the application for other machines, check that the copy runs outside
this checkout, and write it as an archive with a README. Answer the path of the
archive.

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
                       expect = ["share/projectured/font"])
end
