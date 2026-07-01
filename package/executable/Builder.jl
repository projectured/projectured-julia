# ═══════════════════════════════════════════════════════════════════════════
# executable/Builder.jl
#
# The configurable build front-end. A `BuildSpec` describes the editor to bake
# into the native executable (which domain, workbench or not, file-backed or not,
# which backend(s) compiled in and whether the choice is exposed at runtime).
# `build_executable` turns a spec into a binary:
#
#   1. generate `src/AppConfig.jl` — the baked configuration constants plus the
#      `using` line(s) for exactly the compiled-in backends;
#   2. develop the local packages the app needs (the meta-package, the examples,
#      and each baked backend) so they resolve regardless of a stale Manifest;
#   3. compile with PackageCompiler.
#
# The interface is plain Julia functions callable from the REPL — no CLI parsing.
# `Build.jl` is just a one-line script that calls `build_executable()`.
#
# Generation (step 1) is separated from compilation (steps 2-3) so it can be
# tested without the multi-minute `create_app`: call `build_executable(spec;
# compile=false)` (or `render_app_config(spec)` directly).
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedBuilder

import Pkg

export BuildSpec, build_executable, render_app_config, write_app_config

# Backend symbol → (package name, local package dir under `package/`). `:console`
# lives in the domain package (re-exported by `Projectured`), so it needs no extra
# develop and has no entry here.
const BACKEND_LOCALS = Dict{Symbol,Tuple{String,String}}(
    :sdl => ("ProjecturedSdl", "sdl"),
    :web => ("ProjecturedWeb", "web"),
)
const KNOWN_BACKENDS = Set{Symbol}([:sdl, :web, :console])

# Local (path) packages the app always needs, developed by path so they resolve
# without a registry. `projectured` (the meta-package) brings `kernel`+`domain` via
# its own `[sources]`, but `example` depends on `llm` and declares no `[sources]`
# of its own, so `llm` must be developed explicitly too. Backends are added on top
# from `spec.backends`.
const LOCAL_CORE_PACKAGES = ["projectured", "example", "llm"]

# ── BuildSpec ────────────────────────────────────────────────────────────────

"""
    BuildSpec(; app_name="projectured", domain=:json, domains=[domain], workbench=false,
                file_backed=true, backends=[:sdl], default_backend=:sdl,
                expose_backend_flag=false, width=nothing, height=nothing, mcp=false)

Description of the editor to bake into the executable. See
`plan/.../executable-builder-editor-configuration.md`. The keyword constructor
validates the spec (non-empty/known backends; `default_backend` ∈ `backends`;
non-empty `domains` with `domain` ∈ `domains`).

`domains` is the set of content domains the binary accepts at runtime, chosen per
file by extension (`.json`/`.xml`/`.sql`/`.jl`); `domain` is the default/fallback
used for a scratch document or an unrecognised extension. A single-domain build is
just `domains=[domain]` (the default), so existing specs are unchanged.
"""
struct BuildSpec
    app_name::String
    domain::Symbol
    domains::Vector{Symbol}
    workbench::Bool
    file_backed::Bool
    backends::Vector{Symbol}
    default_backend::Symbol
    expose_backend_flag::Bool
    width::Union{Int,Nothing}
    height::Union{Int,Nothing}
    mcp::Bool
end

function BuildSpec(; app_name::AbstractString="projectured",
                     domain::Symbol=:json,
                     domains::AbstractVector=[domain],
                     workbench::Bool=false,
                     file_backed::Bool=true,
                     backends::AbstractVector=[:sdl],
                     default_backend::Symbol=:sdl,
                     expose_backend_flag::Bool=false,
                     width::Union{Integer,Nothing}=nothing,
                     height::Union{Integer,Nothing}=nothing,
                     mcp::Bool=false)
    spec = BuildSpec(String(app_name), domain, Symbol.(collect(domains)), workbench,
                     file_backed, Symbol.(collect(backends)), default_backend,
                     expose_backend_flag,
                     width === nothing ? nothing : Int(width),
                     height === nothing ? nothing : Int(height), mcp)
    validate(spec)
    spec
end

function validate(spec::BuildSpec)
    isempty(spec.domains) && error("BuildSpec: `domains` must not be empty")
    spec.domain in spec.domains ||
        error("BuildSpec: default domain :$(spec.domain) is not in domains $(spec.domains)")
    isempty(spec.backends) && error("BuildSpec: `backends` must not be empty")
    known = join(sort!(collect(KNOWN_BACKENDS)), ", ")
    for b in spec.backends
        b in KNOWN_BACKENDS || error("BuildSpec: unknown backend :$b (known: $known)")
    end
    spec.default_backend in spec.backends ||
        error("BuildSpec: default_backend :$(spec.default_backend) is not in backends $(spec.backends)")
    (spec.expose_backend_flag || length(spec.backends) == 1) ||
        @warn "BuildSpec: multiple backends baked but expose_backend_flag=false; only :$(spec.default_backend) is reachable at runtime"
    spec
end

# ── AppConfig.jl generation ──────────────────────────────────────────────────

_opt(x) = x === nothing ? "nothing" : repr(x)

"""
    render_app_config(spec::BuildSpec) -> String

The source text of the generated `src/AppConfig.jl`: the backend `using` line(s)
for exactly the compiled-in backends, followed by the baked `APP_*` constants the
app's `julia_main` reads. Pure — no filesystem or Pkg side effects.
"""
function render_app_config(spec::BuildSpec)
    lines = String[
        "# ───────────────────────────────────────────────────────────────────────────",
        "# AUTO-GENERATED by build_executable (package/executable/Builder.jl).",
        "# Do not edit by hand — re-run the builder to regenerate.",
        "#",
        "# Bakes the chosen editor configuration + backend `using` lines into the app.",
        "# ───────────────────────────────────────────────────────────────────────────",
    ]
    for b in spec.backends
        haskey(BACKEND_LOCALS, b) || continue          # :console needs no `using`
        push!(lines, "using $(BACKEND_LOCALS[b][1])")
    end
    append!(lines, [
        "",
        "const APP_NAME            = $(repr(spec.app_name))",
        "const APP_DOMAIN          = $(repr(spec.domain))",
        "const APP_DOMAINS         = $(repr(Tuple(spec.domains)))",
        "const APP_WORKBENCH       = $(spec.workbench)",
        "const APP_FILE_BACKED     = $(spec.file_backed)",
        "const APP_BACKENDS        = $(repr(Tuple(spec.backends)))",
        "const APP_DEFAULT_BACKEND = $(repr(spec.default_backend))",
        "const APP_EXPOSE_BACKEND  = $(spec.expose_backend_flag)",
        "const APP_WIDTH           = $(_opt(spec.width))",
        "const APP_HEIGHT          = $(_opt(spec.height))",
        "const APP_MCP             = $(spec.mcp)",
    ])
    join(lines, "\n") * "\n"
end

"""
    write_app_config(spec::BuildSpec, path) -> path

Write [`render_app_config`](@ref) to `path` (the generated `src/AppConfig.jl`).
"""
function write_app_config(spec::BuildSpec, path::AbstractString)
    write(path, render_app_config(spec))
    path
end

# ── Full build ───────────────────────────────────────────────────────────────

"""
    build_executable(spec::BuildSpec; exe_dir=@__DIR__, output=joinpath(exe_dir,"build"),
                     compile=true, force=true) -> path
    build_executable(; kwargs...)   # builds a BuildSpec from keyword args first

Generate `src/AppConfig.jl` from `spec` and, when `compile=true`, compile the
native executable with PackageCompiler. With `compile=false` only the config is
generated (returns the AppConfig path) — useful for testing generation without the
multi-minute build. Returns the output directory when compiling.
"""
function build_executable(spec::BuildSpec; exe_dir::AbstractString=@__DIR__,
                          output::AbstractString=joinpath(exe_dir, "build"),
                          compile::Bool=true, force::Bool=true)
    config_path = joinpath(exe_dir, "src", "AppConfig.jl")
    write_app_config(spec, config_path)
    @info "build_executable: wrote $config_path"
    compile || return config_path

    package_dir = normpath(joinpath(exe_dir, ".."))
    Pkg.activate(exe_dir)
    # Develop the local packages this app needs by path, so they resolve even when
    # the committed Manifest is stale: the core packages (meta-package + examples +
    # their local deps) and each baked backend (e.g. ProjecturedSdl → package/sdl).
    local_specs = Pkg.PackageSpec[
        Pkg.PackageSpec(path = joinpath(package_dir, p)) for p in LOCAL_CORE_PACKAGES
    ]
    for b in spec.backends
        haskey(BACKEND_LOCALS, b) || continue
        push!(local_specs, Pkg.PackageSpec(path = joinpath(package_dir, BACKEND_LOCALS[b][2])))
    end
    Pkg.develop(local_specs)
    # Julia 1.12 precompile fix (carried over from the original Build.jl).
    Pkg.add(url = "https://github.com/JuliaMath/FixedPointNumbers.jl",
            rev = "59ee94b93f2f1ee75544ef44187fc0e440cd8015")
    haskey(Pkg.project().dependencies, "PackageCompiler") || Pkg.add("PackageCompiler")
    Pkg.resolve()
    Pkg.instantiate()

    @eval import PackageCompiler
    @info "build_executable: compiling :$(spec.app_name) (domain=:$(spec.domain), backends=$(Tuple(spec.backends))) — this takes several minutes"
    Base.invokelatest(PackageCompiler.create_app, exe_dir, output;
        precompile_execution_file = joinpath(exe_dir, "src", "Precompile.jl"),
        executables = [spec.app_name => "julia_main"],
        force = force)
    @info "build_executable: done → $(joinpath(output, "bin", spec.app_name))"
    output
end

build_executable(; kwargs...) = build_executable(BuildSpec(; kwargs...))

end # module ProjecturedBuilder
