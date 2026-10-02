# Fragment of `BuilderModule` — the binaries of this repository, and the release
# of its packages.

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
const PROJECTURED_BACKENDS = (sdl = ("ProjecturedSDL", :SdlBackend),
                              web = ("ProjecturedWeb", :WebBackend))

"""
    PROJECTURED_STAND_INS

The JLL packages that a `projectured` binary does not carry, as
`"<name>" => "<uuid>"`: [`write_app_package`](@ref) puts an empty stand-in in
their place. `SDL2_jll` and SimpleDirectMediaLayer load `alsa_plugins_jll`,
and it brings FFmpeg, which is built with `--enable-nonfree` and so may not be
given to anyone, and PulseAudio with GPL-3 and AGPL-3 libraries. The application
plays no sound: it starts SDL for video only.

It keeps two of the dependencies of the real one: the libraries of `SDL2_jll`
link `libsamplerate.so.0` and `libiconv.so.2`, and `SDL2_jll` names neither JLL.
A container of Debian 12 found them missing on 2026-09-30.
"""
const PROJECTURED_STAND_INS = [
    StandIn("alsa_plugins_jll", "5ac2f6bb-493e-5871-9171-112d4c21a6e7";
            keeps = ["libsamplerate_jll" => "9427e74d-4e05-59c1-8ff3-7d74b6e52ac8",
                     "Libiconv_jll" => "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"])]

"""
    PROJECTURED_SOURCE_OFFERS

The sources that a `projectured` distribution gives beside its archive: the
libraries under the LGPL and the GPL that the bundle carries, for exactly the
versions it carries. Every URL and SHA-256 was checked by a download on
2026-09-30. [`build_source_archive`](@ref) stops when the bundle carries
another version of one of the JLLs.
"""
const PROJECTURED_SOURCE_OFFERS = [
    SourceOffer("alsa-lib", "1.2.15.3"; jll = "alsa_jll", jll_version = "1.2.15+0",
        url = "https://www.alsa-project.org/files/pub/lib/alsa-lib-1.2.15.3.tar.bz2",
        sha256 = "7b079d614d582cade7ab8db2364e65271d0877a37df8757ac4ac0c8970be861e",
        recipe = "https://github.com/JuliaPackaging/Yggdrasil/tree" *
                "/3af3dd7c1c07c28c28d734f5d42a26c2972da25b/A/alsa",
        notes = "LGPL-2.1. The build applies no patch."),
    SourceOffer("GMP", "6.3.0"; jll = "GMP_jll", jll_version = "6.3.0+2",
        url = "https://gmplib.org/download/gmp/gmp-6.3.0.tar.bz2",
        sha256 = "ac28211a7cfb609bae2e2c8d6058d66c8fe96434f740cf6fe2e47b000d1c20cb",
        recipe = "https://github.com/JuliaPackaging/Yggdrasil/tree" *
                "/c52e41b25b1d4c30b6024444ad1b0d3a1f051d57/G/GMP/GMP@6.3.0",
        patches = ["https://raw.githubusercontent.com/JuliaPackaging/Yggdrasil" *
                    "/c52e41b25b1d4c30b6024444ad1b0d3a1f051d57/G/GMP/GMP@6.3.0/bundled" *
                    "/patches/gmp-alloc_overflow.patch",
                   "https://raw.githubusercontent.com/JuliaPackaging/Yggdrasil" *
                    "/c52e41b25b1d4c30b6024444ad1b0d3a1f051d57/G/GMP/GMP@6.3.0/bundled" *
                    "/patches/gmp-exception.patch"],
        notes = "LGPL-3 or GPL-2. The build applies the two patches in patches/."),
    SourceOffer("MPFR", "4.2.2"; jll = "MPFR_jll", jll_version = "4.2.2+0",
        url = "https://www.mpfr.org/mpfr-4.2.2/mpfr-4.2.2.tar.xz",
        sha256 = "b67ba0383ef7e8a8563734e2e889ef5ec3c3b898a01d00fa0a6869ad81c6ce01",
        recipe = "https://github.com/JuliaPackaging/Yggdrasil/tree" *
                "/4499d58a12fc3a78fa500b8809f943e68f7eec9f/M/MPFR",
        notes = "LGPL-3. The build applies no patch."),
    SourceOffer("GCC runtime libraries", "15.2.0";
        jll = "CompilerSupportLibraries_jll", jll_version = "1.5.5+2",
        url = "https://ftp.gnu.org/gnu/gcc/gcc-15.2.0/gcc-15.2.0.tar.xz",
        sha256 = "438fd996826b0c82485a29da03a72d71d6e3541a83ec702df4271f6fe025d24e",
        recipe = "https://github.com/JuliaPackaging/Yggdrasil/tree" *
                "/00967747008623072bd475bb50e8568b07f11035/C/CompilerSupportLibraries" *
                "/CompilerSupportLibraries@v1.5",
        notes = "libgcc_s, libstdc++, libgfortran, libgomp, libatomic, libssp and " *
                "libquadmath: GPL-3 with the\n" *
                "GCC Runtime Library Exception, libquadmath LGPL-2.1. The libraries " *
                "name GCC 15.2.0 in their\n" *
                "own banner. The recipe copies them out of the GCC that Yggdrasil " *
                "builds by its recipe\n" *
                "0_RootFS/GCCBootstrap@15, whose bundled/patches/ hold the patches " *
                "that it applies to GCC."),
    SourceOffer("libgit2", "0060d9cf5666f015b1067129bd874c6cc4c9c7ac";
        jll = "LibGit2_jll", jll_version = "1.9.1+0",
        url = "https://github.com/libgit2/libgit2/archive" *
            "/0060d9cf5666f015b1067129bd874c6cc4c9c7ac.tar.gz",
        sha256 = "7efaf8f564c7a2c0f5cf475f80c91fc003e529e66643b07b9265320f55b0664b",
        recipe = "https://github.com/JuliaPackaging/Yggdrasil/tree" *
                "/717c4da21c7ca5e0b6165738810945dab53265dc/L/LibGit2",
        notes = "GPL-2 with a linking exception. The build takes this git revision and " *
                "applies no patch.\n" *
                "GitHub makes the archive of a revision, and does not promise the same " *
                "bytes for ever:\n" *
                "when the SHA-256 differs, `git archive` of the revision is the same " *
                "source."),
    SourceOffer("7-Zip", "26.02"; jll = "p7zip_jll", jll_version = "17.8.2+0",
        url = "https://github.com/ip7z/7zip/releases/download/26.02/7z2602-src.tar.xz",
        sha256 = "cf967c98bca02a4b8b16375f441825a8e141362f14be1969bbec8e1ca0bff9dd",
        recipe = "https://github.com/JuliaPackaging/Yggdrasil/tree" *
                "/6bcdfadfa59d4facd0fcc96e92a4c3790c73ee1a/P/p7zip/p7zip@17.8",
        notes = "LGPL-2.1 with BSD parts. p7zip_jll 17.8.2 builds 7-Zip 26.02 of " *
                "ip7z/7zip, the continuation\n" *
                "of 7-Zip; the build applies no patch."),
    SourceOffer("Julia", "1.13.0"; jll = "julia", jll_version = "1.13.0",
        url = "https://github.com/JuliaLang/julia/releases/download/v1.13.0" *
            "/julia-1.13.0.tar.gz",
        sha256 = "5558c3328cd15c4ef32d1009ccda9aa43401e0436adf1177d1a34ecb0eb5f926",
        recipe = "https://github.com/JuliaLang/julia/tree/v1.13.0",
        notes = "MIT, with the LGPL-2.1 part src/dl-cache.h in libjulia-internal. The " *
                "SHA-256 is the one of\n" *
                "julia-1.13.0.sha256 of the Julia project."),
]

"""
    PROJECTURED_OPTIONS

The options of the `projectured` command that every build takes, as
`"--option=value" => "what it does"`. `--backend` is added when a build holds
more than one backend. The builder writes its own four options after these.
"""
const PROJECTURED_OPTIONS = [
    "--assistant=ollama|anthropic|none" =>
        "the model backend of the assistant (default: the\nsettings, ollama at first), or no assistant",
    "--model=NAME" => "the model of that backend (default: the settings,\nelse the default model of the backend)",
    "--root=DIRECTORY" => "the directory that the navigator lists (default:\nthe current directory)",
    "--mcp" => "start an MCP server at http://127.0.0.1:9876/mcp",
    "--mcp=[HOST:]PORT" => "start an MCP server at http://HOST:PORT/mcp\n(HOST is 127.0.0.1 when it is not given)",
    "--context=TOKENS" => "how many tokens of the conversation the model may\nsee (default: the settings, else the default of the\nbackend)",
    "--strict-fault-policy" => "stop at the first fault and print its stack,\ninstead of surviving it",
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

The licence files of the repository, which the archive of a distribution and
every released package carry: the Mozilla Public License 2.0. It asks that a
copy of the code carries its text.
"""
const PROJECTURED_LICENCES = ["LICENSE"]

"""
    PROJECTURED_CREDITS

Sentences that the licence of a library in the binary asks to appear in its
documentation: the IJG licence of libjpeg-turbo, and the FreeType License, with
the year of the FreeType that the binary carries (2.14.3, copyright 1996-2026).
"""
const PROJECTURED_CREDITS = [
    "This software is based in part on the work of the Independent JPEG Group.",
    "Portions of this software are copyright © 2026 The FreeType Project " *
        "(https://freetype.org). All rights reserved."]

"""
    PROJECTURED_EXTRA_TEXTS

The licence texts that the archive takes from this repository, as
`"<name>" => "<file>"`: the certificates of Mozilla that Julia ships in
`share/julia/cert.pem` are under MPL-2.0, and their JLL names no artifact to take
the text from. It is the text of `LICENSE`.
"""
const PROJECTURED_EXTRA_TEXTS = ["MozillaCACerts" => "LICENSE"]

"""
    PROJECTURED_SOURCE

Where the source code of this repository is. The README of an archive names it,
because MPL-2.0 asks a program in executable form to say where its source is.
"""
const PROJECTURED_SOURCE = "https://github.com/projectured/projectured-julia"

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

The binary holds the umbrella, which holds every domain and, through the
platform, the application; both model adapters, the MCP server, and the
backends.
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
    # `(sdl = ProjecturedSDL.SdlBackend, …)`, in the order the build names them,
    # so the first one is the default of the command line.
    table = Expr(:tuple, [Expr(:(=), backend,
                               Expr(:., Symbol(first(PROJECTURED_BACKENDS[backend])),
                                    QuoteNode(last(PROJECTURED_BACKENDS[backend]))))
                          for backend in backends]...)
    main = :(Projectured.run_application_command(ARGS; backends = $table))
    build_executable(context; name = name,
                     packages = vcat(["Projectured", "ProjecturedOllama", "ProjecturedAnthropic",
                                      "ProjecturedMCP"], backend_packages),
                     main = main,
                     workload = workload ? :(Projectured.warm_application()) : nothing,
                     usage = make_projectured_usage(collect(backends)),
                     fonts = true,
                     assets = PROJECTURED_ASSETS,
                     stand_ins = PROJECTURED_STAND_INS,
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
    # Before the archive, so that a JLL of another version than its offer stops
    # the build before anything is written.
    sources = build_source_archive(context; name = name,
                                   offers = PROJECTURED_SOURCE_OFFERS)
    build_distribution(context; name = name, bundle = bundle,
                       source_archive = basename(sources),
                       requirements = PROJECTURED_REQUIREMENTS,
                       licences = PROJECTURED_LICENCES, source = PROJECTURED_SOURCE,
                       credits = PROJECTURED_CREDITS,
                       extra_texts = PROJECTURED_EXTRA_TEXTS,
                       expect = vcat(["share/projectured/font"], last.(PROJECTURED_ASSETS)),
                       check = check_projectured_copy)
end

"""
    PROJECTURED_RELEASE_EXCLUSIONS

The packages that stay out of the registry although they are neither an example
package nor a test package: each one depends on a package that the registry
does not hold, reads a folder outside its own, or compiles native code on the
machine of the user.
"""
const PROJECTURED_RELEASE_EXCLUSIONS = ["ProjecturedAdaptagrams", "ProjecturedBench",
                                        "ProjecturedBuilder", "ProjecturedREPL"]

"""
    PROJECTURED_PACKAGE_ASSETS

The folders and files of the repository that a released package, or a package
of its tests, reads while it runs, as
`"<package>" => ["<folder or file>" => "<the same in the package>", …]`. Each one sits at
the same place relative to the source of the package as in the repository, so
the code that reads it needs no change.
"""
const PROJECTURED_PACKAGE_ASSETS = Dict(
    "ProjecturedKernel" => ["documentation" => "documentation"],
    "ProjecturedPlatform" => ["asset/font" => "asset/font"],
    "ProjecturedWeb" => ["asset/web" => "asset/web", "asset/font" => "asset/font"],
    "ProjecturedPlatformExample" => ["asset/image/file.png" => "asset/image/file.png",
                                     "asset/image/projectured.png" => "asset/image/projectured.png"],
    "ProjecturedMarkdownTest" => ["asset/image/file.png" => "asset/image/file.png"],
    "ProjecturedSDLTest" => ["tool/precompile/recording-driver.jl" =>
                             "tool/precompile/recording-driver.jl"],
    "ProjecturedTest" => ["test/suite" => "test/suite"])

"""
    PROJECTURED_JULIA_COMPAT

The oldest Julia that a released package of this repository names in its
`[compat]`. The packages reach each other by `[sources]`, which Julia 1.11 is
the first to read.
"""
const PROJECTURED_JULIA_COMPAT = "1.11"

"""
    collect_projectured_release_packages(context) -> Vector{String}

The packages of this repository that go into the registry: every package that
is not an example package and not a test package, without
[`PROJECTURED_RELEASE_EXCLUSIONS`](@ref).
"""
function collect_projectured_release_packages(context::BuildContext)
    names = String[]
    for root in context.package_roots, name in readdir(root)
        isfile(joinpath(root, name, "Project.toml")) || continue
        (endswith(name, "Test") || endswith(name, "Example")) && continue
        name in PROJECTURED_RELEASE_EXCLUSIONS || push!(names, name)
    end
    sort!(unique!(names))
end

"""
    build_projectured_package_release!(output; context, kwargs...) -> Vector

Write the release copy of the packages of this repository into `output`, the
working tree of the release repository `projectured/Projectured.jl`, one folder
for each package. The packages are served by `registry`, the General registry
or the name or folder of another one, and every version of the last release must
be in it. The other keywords go to [`build_package_release!`](@ref).
"""
function build_projectured_package_release!(output::AbstractString;
                                              context::BuildContext =
                                                  make_projectured_build_context(),
                                              registry::Union{AbstractString,Nothing} =
                                                  "General",
                                              kwargs...)
    build_package_release!(context;
                           packages = collect_projectured_release_packages(context),
                           output = output, assets = PROJECTURED_PACKAGE_ASSETS,
                           licences = PROJECTURED_LICENCES,
                           readme = _format_projectured_package_readme,
                           tests = name -> _find_projectured_release_test(context, name),
                           julia_compat = PROJECTURED_JULIA_COMPAT, registry = registry,
                           kwargs...)
end

# The README of the folder of one released package, which is also its page on
# GitHub.
_format_projectured_package_readme(name) = """
    # $name

    A package of [ProjecturEd](https://github.com/projectured/projectured-julia), a
    projectional editor. The release of ProjecturEd writes this folder: the source
    of `$name` is `package/$name` there, and a change belongs there.

    The licence is the Mozilla Public License 2.0, in `LICENSE`.
    """

# The suite that tests a released package of this repository: its test package
# `<Name>Test` and its aggregator `test_<name>()`. The umbrella runs the part of
# its suite that only the umbrella can run.
function _find_projectured_release_test(context::BuildContext, name)
    name == "Projectured" &&
        return "ProjecturedTest" => _format_projectured_runtests("ProjecturedTest", "test_integration")
    test_package = name * "Test"
    has_package_directory(context, test_package) || return nothing
    suite = "test_" * lowercase(name[length("Projectured")+1:end])
    test_package => _format_projectured_runtests(test_package, suite)
end

_format_projectured_runtests(test_package, suite) = """
    # The suite of `$test_package`, which the release copies into `support/` with
    # the packages it needs that no registry holds. SDL draws into memory when no
    # display is named.
    haskey(ENV, "SDL_VIDEODRIVER") || (ENV["SDL_VIDEODRIVER"] = "offscreen")
    using $test_package
    $suite()
    """

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
