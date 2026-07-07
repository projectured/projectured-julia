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

# Extensions this build actually accepts: the baked domains' entries in the
# extension→domain map.
_baked_extensions() = sort!([ext for (ext, d) in EXTENSION_DOMAINS if d in APP_DOMAINS])

function print_help()
    file_suffix = APP_FILE_BACKED ? " [FILE]" : ""
    multi = length(APP_DOMAINS) > 1
    domain_desc = multi ? "domains: $(join(map(d -> ":$d", APP_DOMAINS), ", "))" :
                          "domain: :$(APP_DOMAIN)"
    println("$(APP_NAME) — a Projectured editor ($(domain_desc))")
    println()
    println("Usage: $(APP_NAME) [options]$(file_suffix)")
    println()
    println("Options:")
    if APP_FILE_BACKED
        if multi
            println("  FILE              open and edit FILE (domain chosen by extension: $(join(_baked_extensions(), ", "))); omitted → :$(APP_DOMAIN) scratch")
        else
            println("  FILE              open and edit FILE (a :$(APP_DOMAIN) file); omitted → scratch document")
        end
    end
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

# Pick the content domain for a run: from the FILE's extension when file-backed and a
# file was given (restricted to the baked APP_DOMAINS), otherwise the default
# APP_DOMAIN. A single-domain build always resolves to APP_DOMAIN.
resolve_domain(file) =
    (APP_FILE_BACKED && file !== nothing) ?
        domain_for_path(file; default = APP_DOMAIN, allowed = APP_DOMAINS) : APP_DOMAIN

# ── Precompile warm-up (config-driven) ─────────────────────────────────────

"""
    precompile_warmup()

Exercise the *configured* editor without opening a window, so PackageCompiler warms
the right code paths. For **every** baked domain (`APP_DOMAINS`) it builds the
document + projection and, when an SDL backend is compiled in, renders one offscreen
frame to warm the printer and rasteriser, then drives the interactive path. Used by
`main/Precompile.jl`.
"""
function precompile_warmup()
    print_help()
    print_version()
    for domain in APP_DOMAINS
        doc, proj, _name = build_file_editor(domain; workbench = APP_WORKBENCH)
        if :sdl in APP_BACKENDS
            try
                mktempdir() do d
                    write_image(doc, proj, joinpath(d, "warm.png"))
                end
            catch err
                @warn "precompile_warmup: offscreen warm render failed" domain err
            end
        end
        # Warm the *interactive* path (reader → operation-evaluation → reprint) of the
        # windowed pipeline the binary actually runs, so the first keystroke of the
        # built app doesn't pay first-call JIT. Backend-independent, so it runs for
        # every baked backend (not just SDL). Self-guards against throwing.
        warm_file_editor(domain; workbench = APP_WORKBENCH)
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
        run_file_editor(resolve_domain(opts.file);
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
