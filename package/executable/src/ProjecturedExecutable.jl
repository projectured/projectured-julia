"""
ProjecturedExecutable

The compiled-app entry module. It is **generic over a baked configuration**: the
editor it runs (domain, workbench, file-backed) and the backend(s) compiled in are
fixed at build time by `build_executable` (see `../Builder.jl`), which writes the
`AppConfig.jl` this module includes. `julia_main` then parses the runtime arguments
(a file to edit, and `--backend` when the build exposed it) and opens the editor.
"""
module ProjecturedExecutable

using ProjecturedExample                       # run_file_editor, build_file_editor, …
using Projectured: make_backend, write_image

# Baked configuration + the backend `using` line(s). Prefer the generated
# `AppConfig.jl` (written by `build_executable`); fall back to the checked-in
# default (a JSON file editor on SDL) when no build has run yet.
include(joinpath(@__DIR__,
                 isfile(joinpath(@__DIR__, "AppConfig.jl")) ? "AppConfig.jl" :
                                                              "AppConfig.default.jl"))

export julia_main, main, print_help, print_version, precompile_warmup

# ── Help / version ─────────────────────────────────────────────────────────

function print_help()
    file_suffix = APP_FILE_BACKED ? " [FILE]" : ""
    println("$(APP_NAME) — a Projectured editor (domain: :$(APP_DOMAIN))")
    println()
    println("Usage: $(APP_NAME) [options]$(file_suffix)")
    println()
    println("Options:")
    APP_FILE_BACKED &&
        println("  FILE              open and edit FILE (a :$(APP_DOMAIN) file); omitted → scratch document")
    APP_EXPOSE_BACKEND &&
        println("  --backend KIND    display backend, one of $(APP_BACKENDS) (default: :$(APP_DEFAULT_BACKEND))")
    println("  -h, --help        show this help")
    println("  -v, --version     show version")
    println()
    if APP_EXPOSE_BACKEND
        println("Backends compiled in: $(join(APP_BACKENDS, ", "))")
    else
        println("Backend: :$(APP_DEFAULT_BACKEND) (baked in)")
    end
end

print_version() = println("$(APP_NAME) (Projectured) — built with Julia $(VERSION)")

# ── Runtime argument parsing ───────────────────────────────────────────────

# Parse the binary's runtime args into (help, version, backend, file). `--backend`
# is accepted as `--backend KIND` or `--backend=KIND`; a lone non-flag token is the
# FILE to open. Unknown flags / extra files raise (the caller turns that into a
# usage error).
function parse_runtime_args(args)
    help = false; version = false; backend = nothing; file = nothing
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--help" || a == "-h"
            help = true
        elseif a == "--version" || a == "-v"
            version = true
        elseif startswith(a, "--backend=")
            backend = Symbol(a[(length("--backend=") + 1):end])
        elseif a == "--backend"
            i += 1
            i <= length(args) || error("--backend requires a value")
            backend = Symbol(args[i])
        elseif startswith(a, "-")
            error("unknown option: $a")
        else
            file === nothing || error("unexpected extra argument: $a (a file was already given: $file)")
            file = a
        end
        i += 1
    end
    (; help, version, backend, file)
end

# Resolve the backend kind to use, honouring whether this build exposed the choice.
# Returns the Symbol, or throws a user-facing error.
function resolve_backend(requested)
    requested === nothing && return APP_DEFAULT_BACKEND
    APP_EXPOSE_BACKEND ||
        error("this build does not accept --backend (backend :$(APP_DEFAULT_BACKEND) is baked in)")
    requested in APP_BACKENDS ||
        error("backend :$(requested) is not built into this binary (available: $(APP_BACKENDS))")
    requested
end

# ── Precompile warm-up (config-driven) ─────────────────────────────────────

"""
    precompile_warmup()

Exercise the *configured* editor without opening a window, so PackageCompiler warms
the right code paths. Builds the document + projection for the baked domain and,
when an SDL backend is compiled in, renders one offscreen frame to warm the printer
and rasteriser. Used by `src/Precompile.jl`.
"""
function precompile_warmup()
    print_help()
    print_version()
    doc, proj, _name = build_file_editor(APP_DOMAIN; workbench = APP_WORKBENCH)
    if :sdl in APP_BACKENDS
        try
            mktempdir() do d
                write_image(doc, proj, joinpath(d, "warm.png"))
            end
        catch err
            @warn "precompile_warmup: offscreen warm render failed" err
        end
    end
    nothing
end

# ── Entry points ───────────────────────────────────────────────────────────

function julia_main(args::Vector{String})::Cint
    opts = try
        parse_runtime_args(args)
    catch e
        println(stderr, "error: ", sprint(showerror, e))
        println(stderr)
        print_help()
        return 1
    end
    opts.help    && (print_help();    return 0)
    opts.version && (print_version(); return 0)

    backend_kind = try
        resolve_backend(opts.backend)
    catch e
        println(stderr, "error: ", sprint(showerror, e))
        return 1
    end

    try
        run_file_editor(APP_DOMAIN;
                        file      = APP_FILE_BACKED ? opts.file : nothing,
                        workbench = APP_WORKBENCH,
                        backend   = make_backend(backend_kind),
                        width     = APP_WIDTH,
                        height    = APP_HEIGHT,
                        mcp       = APP_MCP)
    catch e
        e isa InterruptException && return 0
        println(stderr, "error: ", sprint(showerror, e))
        return 1
    end
    return 0
end

# PackageCompiler entry point.
julia_main()::Cint = julia_main(copy(ARGS))

# Convenience for running this file directly with `julia ProjecturedExecutable.jl`.
main() = julia_main(copy(ARGS))

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end

end # module
