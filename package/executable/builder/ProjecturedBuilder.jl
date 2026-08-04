# ═══════════════════════════════════════════════════════════════════════════
# executable/builder/ProjecturedBuilder.jl
#
# The configurable build front-end. A `BuildSpec` describes the editor to bake
# into the native executable (which domain, workbench or not, file-backed or not,
# which backend(s) compiled in and whether the choice is exposed at runtime).
# `build_executable` turns a spec into a binary:
#
#   1. generate `main/AppConfig.jl` — the baked configuration constants plus the
#      `using` line(s) for exactly the compiled-in backends;
#   2. develop the local packages the app needs (the meta-package, the examples,
#      and each baked backend) so they resolve regardless of a stale Manifest;
#   3. compile with PackageCompiler.
#
# The interface is plain Julia functions callable from the REPL — no CLI parsing
# and no script to run:
#
#     using ProjecturedSdl, ProjecturedBuilder
#     build_executable(workbench_app(SdlBackend))
#
# Generation (step 1) is separated from compilation (steps 2-3) so it can be
# tested without the multi-minute `create_app`: call `build_executable(spec;
# compile=false)` (or `render_app_config(spec)` directly).
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedBuilder

import Pkg

export BuildSpec, build_executable, render_app_config, write_app_config
export default_json_app, workbench_app

# The executable directory (`package/executable/`) — this package lives one level
# below it, and every path the builder writes to is relative to it.
const EXECUTABLE_DIR = normpath(joinpath(@__DIR__, ".."))

# A backend is named by its real type (`SdlBackend`, `WebBackend`, `ConsoleBackend`);
# everything the builder needs is derived from that type by reflection, so no symbol
# registry is maintained here.
#
# - the friendly runtime `--backend` name: the type name minus `Backend`, lowercased
#   (`SdlBackend` → `sdl`); this is only a CLI label, never a dispatch key;
# - the package to `using` in the generated config: the type's parent module;
# - the local dir to `develop` (for backends in their own opt-in package): derived
#   from that module name by the `package/<short>/main` layout convention.
#
# Backends whose package the core app already pulls in (console lives in
# `ProjecturedVisual`) need neither a `using` line nor a develop.
const CORE_BACKEND_MODULES =
    Set(["ProjecturedKernel", "ProjecturedBase", "ProjecturedVisual", "ProjecturedDomain"])

_backend_kind(T::Type)    = Symbol(lowercase(replace(String(nameof(T)), "Backend" => "")))
_backend_module(T::Type)  = String(nameof(parentmodule(T)))
_backend_needs_local(T::Type) = !(_backend_module(T) in CORE_BACKEND_MODULES)
_backend_localdir(T::Type) = lowercase(replace(_backend_module(T), "Projectured" => "")) * "/main"

# Local (path) packages the app always needs, developed by path so they resolve
# without a registry. `projectured` (the meta-package) brings `kernel`+`domain` via
# its own `[sources]`, but `example` depends on `llm` and declares no `[sources]`
# of its own, so `llm` must be developed explicitly too. Backends are added on top
# from `spec.backends`.
const LOCAL_CORE_PACKAGES = ["projectured/main", "projectured/example", "llm/main"]

# ── BuildSpec ────────────────────────────────────────────────────────────────

"""
    BuildSpec(; app_name="projectured", domain=:json, domains=[domain], workbench=false,
                file_backed=true, backends, default_backend=first(backends),
                expose_backend_flag=false, width=nothing, height=nothing, mcp=false)

Description of the editor to bake into the executable. See
`plan/.../executable-builder-editor-configuration.md`. The keyword constructor
validates the spec (non-empty `backends`; `default_backend` ∈ `backends`;
non-empty `domains` with `domain` ∈ `domains`).

`backends` are real backend **types** (`SdlBackend`, `WebBackend`, `ConsoleBackend`)
— name the type, not a coined symbol; the caller's session must have the backend
package loaded so the type resolves. The builder derives everything else (the
friendly `--backend` name, the `using` line, the develop path) from each type by
reflection. `default_backend` is one of those types (defaulting to the first).

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
    backends::Vector{DataType}
    default_backend::DataType
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
                     backends::AbstractVector,
                     default_backend::Type=first(backends),
                     expose_backend_flag::Bool=false,
                     width::Union{Integer,Nothing}=nothing,
                     height::Union{Integer,Nothing}=nothing,
                     mcp::Bool=false)
    spec = BuildSpec(String(app_name), domain, Symbol.(collect(domains)), workbench,
                     file_backed, DataType[b for b in backends], default_backend,
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
    spec.default_backend in spec.backends ||
        error("BuildSpec: default_backend $(spec.default_backend) is not in backends $(spec.backends)")
    (spec.expose_backend_flag || length(spec.backends) == 1) ||
        @warn "BuildSpec: multiple backends baked but expose_backend_flag=false; only $(spec.default_backend) is reachable at runtime"
    spec
end

# ── AppConfig.jl generation ──────────────────────────────────────────────────

_opt(x) = x === nothing ? "nothing" : repr(x)

"""
    render_app_config(spec::BuildSpec) -> String

The source text of the generated `main/AppConfig.jl`: the backend `using` line(s)
for exactly the compiled-in backends, followed by the baked `APP_*` constants the
app's `julia_main` reads. Pure — no filesystem or Pkg side effects.
"""
function render_app_config(spec::BuildSpec)
    lines = String[
        "# ───────────────────────────────────────────────────────────────────────────",
        "# AUTO-GENERATED by build_executable (ProjecturedBuilder).",
        "# Do not edit by hand — re-run the builder to regenerate.",
        "#",
        "# Bakes the chosen editor configuration + backend `using` lines into the app.",
        "# ───────────────────────────────────────────────────────────────────────────",
    ]
    for T in spec.backends
        _backend_needs_local(T) || continue            # console's package is core
        push!(lines, "using $(_backend_module(T))")
    end
    # Friendly runtime name → real backend type; the app constructs the chosen type
    # directly (no make_backend seam). The `using` line(s) above bring the types
    # into scope. APP_DEFAULT_BACKEND stays a friendly Symbol (a `--backend` value
    # and the key into APP_BACKENDS), so help text and error messages read naturally.
    backend_entries = join(("$(_backend_kind(T)) = $(nameof(T))" for T in spec.backends), ", ")
    append!(lines, [
        "",
        "const APP_NAME            = $(repr(spec.app_name))",
        "const APP_DOMAIN          = $(repr(spec.domain))",
        "const APP_DOMAINS         = $(repr(Tuple(spec.domains)))",
        "const APP_WORKBENCH       = $(spec.workbench)",
        "const APP_FILE_BACKED     = $(spec.file_backed)",
        "const APP_BACKENDS        = (; $(backend_entries))",
        "const APP_DEFAULT_BACKEND = $(repr(_backend_kind(spec.default_backend)))",
        "const APP_EXPOSE_BACKEND  = $(spec.expose_backend_flag)",
        "const APP_WIDTH           = $(_opt(spec.width))",
        "const APP_HEIGHT          = $(_opt(spec.height))",
        "const APP_MCP             = $(spec.mcp)",
    ])
    join(lines, "\n") * "\n"
end

"""
    write_app_config(spec::BuildSpec, path) -> path

Write [`render_app_config`](@ref) to `path` (the generated `main/AppConfig.jl`).
"""
function write_app_config(spec::BuildSpec, path::AbstractString)
    write(path, render_app_config(spec))
    path
end

# ── Full build ───────────────────────────────────────────────────────────────

"""
    build_executable(spec::BuildSpec; exe_dir=EXECUTABLE_DIR, output=joinpath(exe_dir,"build"),
                     compile=true, force=true, logfile=nothing) -> path
    build_executable(; kwargs...)   # builds a BuildSpec from keyword args first

Generate `main/AppConfig.jl` from `spec` and, when `compile=true`, compile the
native executable with PackageCompiler. With `compile=false` only the config is
generated (returns the AppConfig path) — useful for testing generation without the
multi-minute build. Returns the output directory when compiling.

`logfile` sends the (long and noisy) compile output to a file instead of the
terminal — pass `joinpath(exe_dir, "build.log")` for the behaviour the old
`Build.jl` / `regenerate.sh` scripts hard-coded. The default, `nothing`, leaves
output where an interactive caller can see it.

The caller's active environment is restored on the way out: the compile has to
`Pkg.activate` the app environment, and a REPL session must not be left in it.
"""
function build_executable(spec::BuildSpec; exe_dir::AbstractString=EXECUTABLE_DIR,
                          output::AbstractString=joinpath(exe_dir, "build"),
                          compile::Bool=true, force::Bool=true,
                          logfile::Union{AbstractString,Nothing}=nothing)
    config_path = joinpath(exe_dir, "main", "AppConfig.jl")
    write_app_config(spec, config_path)
    @info "build_executable: wrote $config_path"
    compile || return config_path

    logfile === nothing && return _compile!(spec, exe_dir, output, force)
    mkpath(dirname(abspath(logfile)))
    @info "build_executable: compiling — output goes to $(abspath(logfile))"
    open(logfile, "w") do io
        redirect_stdout(io) do
            redirect_stderr(io) do
                _compile!(spec, exe_dir, output, force)
            end
        end
    end
end

# Steps 2-3: develop the local packages into the app environment and run
# `create_app`. Activating is unavoidable (PackageCompiler builds the active
# project), so the caller's project is captured and restored around it.
function _compile!(spec::BuildSpec, exe_dir, output, force)
    package_dir = normpath(joinpath(exe_dir, ".."))
    previous_project = Base.active_project()
    try
        Pkg.activate(joinpath(exe_dir, "main"))
        # Develop the local packages this app needs by path, so they resolve even when
        # the committed Manifest is stale: the core packages (meta-package + examples +
        # their local deps) and each baked backend (e.g. ProjecturedSdl → package/sdl/main).
        local_specs = Pkg.PackageSpec[
            Pkg.PackageSpec(path = joinpath(package_dir, p)) for p in LOCAL_CORE_PACKAGES
        ]
        for T in spec.backends
            _backend_needs_local(T) || continue
            push!(local_specs, Pkg.PackageSpec(path = joinpath(package_dir, _backend_localdir(T))))
        end
        Pkg.develop(local_specs)
        # Julia 1.12 precompile fix.
        Pkg.add(url = "https://github.com/JuliaMath/FixedPointNumbers.jl",
                rev = "59ee94b93f2f1ee75544ef44187fc0e440cd8015")
        haskey(Pkg.project().dependencies, "PackageCompiler") || Pkg.add("PackageCompiler")
        Pkg.resolve()
        Pkg.instantiate()

        @eval import PackageCompiler
        @info "build_executable: compiling :$(spec.app_name) (domain=:$(spec.domain), backends=$(Tuple(_backend_kind.(spec.backends)))) — this takes several minutes"
        Base.invokelatest(PackageCompiler.create_app, joinpath(exe_dir, "main"), output;
            precompile_execution_file = joinpath(exe_dir, "main", "Precompile.jl"),
            executables = [spec.app_name => "julia_main"],
            force = force)
        @info "build_executable: done → $(joinpath(output, "bin", spec.app_name))"
        output
    finally
        previous_project === nothing || Pkg.activate(previous_project; io = devnull)
    end
end

build_executable(; kwargs...) = build_executable(BuildSpec(; kwargs...))

# ── Named specs ──────────────────────────────────────────────────────────────
#
# The two configurations that used to be hard-coded in `Build.jl` and
# `regenerate.sh`. They are FUNCTIONS of the backend type, not constants: a
# constant would have to name `SdlBackend`, which would make this package depend
# on ProjecturedSdl and undo the reflection design that keeps it backend-agnostic.

"""
    default_json_app(backend) -> BuildSpec

The v1 default: a JSON file editor with `backend` baked in. What `Build.jl` built.

    using ProjecturedSdl, ProjecturedBuilder
    build_executable(default_json_app(SdlBackend))
"""
default_json_app(backend::Type) = BuildSpec(; backends = [backend])

"""
    workbench_app(backend) -> BuildSpec

The current shipping configuration: a workbench, multi-domain
(json / xml / sql / julia) file editor with json the default/scratch domain and
`backend` baked in. What `regenerate.sh` built.
"""
workbench_app(backend::Type) = BuildSpec(; domain = :json,
                                           domains = [:json, :xml, :sql, :julia],
                                           workbench = true,
                                           file_backed = true,
                                           backends = [backend])

end # module ProjecturedBuilder
