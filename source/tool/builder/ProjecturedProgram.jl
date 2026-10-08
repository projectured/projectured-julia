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
    APPLICATION_OPTIONS

The options of a window application, as `(group, label, description)`: the
`projectured` command takes all of them, and another window program built on
the platform takes the groups that its build names. `parse_application_arguments`
of the platform reads every one, and a test checks that the two agree.
`--backend` is not here, because its values are the backends of a build. The
builder writes its own four options after these.

The groups:

- `:assistant` — the assistant, its model, its context and the external agent;
- `:mcp` — the MCP server;
- `:fault` — what the program does with a fault;
- `:files` — the folder that the Files pane lists.
"""
const APPLICATION_OPTIONS = [
    (group = :assistant, label = "--assistant=ollama|anthropic|acp|none",
     description = "the model backend of the assistant, an external\nagent (acp), or no assistant (default: the\nsettings, ollama at first)"),
    (group = :assistant, label = "--model=NAME",
     description = "the model of that backend (default: the settings,\nelse the default model of the backend)"),
    (group = :files, label = "--root=DIRECTORY",
     description = "the directory that the Files pane lists (default:\nthe current directory)"),
    (group = :mcp, label = "--mcp",
     description = "start an MCP server at http://127.0.0.1:9876/mcp"),
    (group = :mcp, label = "--mcp=[HOST:]PORT",
     description = "start an MCP server at http://HOST:PORT/mcp\n(HOST is 127.0.0.1 when it is not given)"),
    (group = :assistant, label = "--context=TOKENS",
     description = "how many tokens of the conversation the model may\nsee (default: the settings, else the default of the\nbackend)"),
    (group = :fault, label = "--strict-fault-policy",
     description = "stop at the first fault and print its stack,\ninstead of surviving it"),
    (group = :assistant, label = "--agent-command=COMMAND",
     description = "the command line of the external agent of\n--assistant=acp (default: the settings,\nthe built-in Claude Code agent at first)"),
]

"""
    make_application_usage(description; synopsis = "[options] [files...]",
                           groups = <every group>, backends = Symbol[]) -> Usage

The `--help` text of a window application that offers the options of `groups`
from [`APPLICATION_OPTIONS`](@ref), in the order of that table. With more than
one of `backends`, `--backend` comes second and names them, and the first one
is the default.
"""
function make_application_usage(description::AbstractString;
                                synopsis::AbstractString = "[options] [files...]",
                                groups = unique(option.group for option in APPLICATION_OPTIONS),
                                backends = Symbol[])
    known = unique(option.group for option in APPLICATION_OPTIONS)
    for group in groups
        group in known ||
            error("make_application_usage: the groups are ", join(repr.(known), ", "),
                  ", not ", repr(group))
    end
    options = [option.label => option.description
               for option in APPLICATION_OPTIONS if option.group in groups]
    if length(backends) > 1
        insert!(options, min(2, length(options) + 1),
                "--backend=" * join(String.(backends), "|") =>
                    "where the window is drawn (default: $(first(backends)))")
    end
    Usage(description; synopsis = synopsis, options = options)
end

"""
    PROJECTURED_REQUIREMENTS

What a machine needs to run a `projectured` distribution, as the lines of its
README.
"""
const PROJECTURED_REQUIREMENTS = [
    "Linux on x86-64.",
    "A display for the native window, or a web browser with --backend=web.",
    "For the assistant: an Ollama server with a pulled model, an Anthropic " *
        "API key in the environment variable ANTHROPIC_API_KEY, or, with " *
        "--assistant=acp, Claude Code installed and signed in, or another agent of " *
        "the Agent Client Protocol, signed in with its own sign-in.",
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
    PROJECTURED_DATA_TEXTS

The licence texts of the data from others that the code of a `projectured` binary
holds, as `"<name>" => "<file>"`: the colours of the Radix, Tailwind and Solarized
palettes, each under the MIT License, which asks for its notice in every copy.
"""
const PROJECTURED_DATA_TEXTS = ["RadixColors" => "asset/licence/RadixColors-MIT.txt",
                                "TailwindCSS" => "asset/licence/TailwindCSS-MIT.txt",
                                "Solarized" => "asset/licence/Solarized-MIT.txt"]

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
make_projectured_usage(backends) =
    make_application_usage("Open files in a window, with a Files pane and an AI assistant.\n" *
                           "A file opens in the format that its extension names.";
                           backends = collect(backends))

"""
    PROJECTURED_APPLICATION_IMPORTS

The packages that the binary loads beside the platform, its backends and its
adapters, so that it opens every format: the console and PDF backends and the
domains. A binary holds a fixed set of packages, so it loads the platform and not
the umbrella, and AutoIntegration has no part in it.
"""
const PROJECTURED_APPLICATION_IMPORTS = ["ProjecturedConsole", "ProjecturedPDF",
    "ProjecturedJSON", "ProjecturedYAML", "ProjecturedXML", "ProjecturedMarkdown",
    "ProjecturedRST", "ProjecturedBook", "ProjecturedMath", "ProjecturedJulia",
    "ProjecturedSQL", "ProjecturedDatabase", "ProjecturedGraph", "ProjecturedChart",
    "ProjecturedSequenceChart", "ProjecturedDBCatalog", "ProjecturedFormula",
    "ProjecturedFSM", "ProjecturedProcess", "ProjecturedPivot"]

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
    main = :(ProjecturedPlatform.run_application_command(ARGS; backends = $table))
    build_executable(context; name = name,
                     packages = vcat(["ProjecturedPlatform", "ProjecturedOllama",
                                      "ProjecturedAnthropic", "ProjecturedMCP", "ProjecturedACP"],
                                     backend_packages),
                     imports = PROJECTURED_APPLICATION_IMPORTS,
                     main = main,
                     workload = workload ? :(ProjecturedPlatform.warm_application()) : nothing,
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
                       data_texts = PROJECTURED_DATA_TEXTS,
                       expect = vcat(["share/projectured/font"], last.(PROJECTURED_ASSETS)),
                       check = check_projectured_copy)
end

"""
    PROJECTURED_RELEASE_EXCLUSIONS

The packages that stay out of the registry although they are neither an example
package nor a test package: each one depends on a package that the registry
does not hold, reads a folder outside its own, compiles native code on the
machine of the user, or serves only the development of this repository, as the
flat namespace of `ProjecturedAll` does.
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
`[compat]`. The code uses what Julia 1.12 adds: the `gc_safe` option of
`@ccall`, so that a collection on another thread goes on while SDL waits, and the
world of a binding, which the completion by reflection reads names in.
"""
const PROJECTURED_JULIA_COMPAT = "1.12"

"""
    PROJECTURED_CI_JULIA_VERSIONS

The Julia versions on which the workflow of the release repository tests each
package: the oldest that the packages name in their `[compat]`.
"""
const PROJECTURED_CI_JULIA_VERSIONS = [PROJECTURED_JULIA_COMPAT]

"""
    PROJECTURED_REGISTRY_URL

The registry that serves the released packages, `ProjecturedRegistry`.
"""
const PROJECTURED_REGISTRY_URL = "https://github.com/projectured/ProjecturedRegistry"

"""
    PROJECTURED_RELEASE_URL

The release repository, which holds one folder for each released package.
"""
const PROJECTURED_RELEASE_URL = "https://github.com/projectured/Projectured.jl"

"""
    AUTOINTEGRATION_URL

The repository of AutoIntegration, the package that loads an installed package
of ProjecturEd when its triggers are loaded. `Projectured` depends on it.
"""
const AUTOINTEGRATION_URL = "https://github.com/projectured/AutoIntegration.jl"

"""
    AGENT_CLIENT_PROTOCOL_URL

The repository of AgentClientProtocol, the package of the Agent Client Protocol
(ACP) that `ProjecturedACP` depends on.
"""
const AGENT_CLIENT_PROTOCOL_URL = "https://github.com/projectured/AgentClientProtocol.jl"

"""
    CLAUDE_CODE_ACP_URL

The repository of ClaudeCodeACP, the ACP agent that runs Claude Code, which
`ProjecturedACP` runs as its built-in agent.
"""
const CLAUDE_CODE_ACP_URL = "https://github.com/projectured/ClaudeCodeACP.jl"

"""
    AUTOPRECOMPILE_URL

The repository of AutoPrecompile, the package that builds one package image for
the packages that a session loads, from recorded precompile statements.
"""
const AUTOPRECOMPILE_URL = "https://github.com/projectured/AutoPrecompile.jl"

"""
    GENERAL_REGISTRY_URL

The General registry of Julia, which serves the packages of other authors that
the released packages depend on.
"""
const GENERAL_REGISTRY_URL = "https://github.com/JuliaRegistries/General"

"""
    MOZILLA_PUBLIC_LICENSE_URL

The text of the Mozilla Public License 2.0, the licence of the released packages.
"""
const MOZILLA_PUBLIC_LICENSE_URL = "https://www.mozilla.org/en-US/MPL/2.0/"

"""
    PROJECTURED_JOINED_PACKAGE_URLS

The repository of each package of another author that an integration joins, as
`"<package>" => "<url>"`, for the links of the front page. An integration that
joins a package without an entry stops the release.
"""
const PROJECTURED_JOINED_PACKAGE_URLS = Dict(
    "DataFrames" => "https://github.com/JuliaData/DataFrames.jl",
    "FFMPEG" => "https://github.com/JuliaIO/FFMPEG.jl",
    "ModelContextProtocol" => "https://github.com/JuliaSMLM/ModelContextProtocol.jl",
    "ODBC" => "https://github.com/JuliaDatabases/ODBC.jl",
    "SimpleDirectMediaLayer" => "https://github.com/JuliaMultimedia/SimpleDirectMediaLayer.jl",
    "Tulip" => "https://github.com/ds4dm/Tulip.jl")

"""
    PROJECTURED_PACKAGE_READMES

The README of each released package, as
`"<package>" => (summary = "<one sentence>", document = "<file of this repository>")`:
what the package holds or does, for a person who does not know ProjecturEd, and
the document that says more. A released package without an entry stops the
release.
"""
const PROJECTURED_PACKAGE_READMES = Dict(
    "Projectured" =>
        (summary = "The umbrella package of ProjecturEd: it loads the kernel, the platform and AutoIntegration, and gives the names that most users call.",
         document = "documentation/guide/own-project-guide.md"),
    "ProjecturedIntegrations" =>
        (summary = "Installs every integration of ProjecturEd and the packages that they join, and loads each integration when the package that it joins is loaded.",
         document = "documentation/guide/own-project-guide.md"),
    "ProjecturedAll" =>
        (summary = "Every package of ProjecturEd that needs no package of another author, with all their names in one namespace. It loads much more than most programs need.",
         document = "documentation/design/system-anatomy.md"),
    "ProjecturedKernel" =>
        (summary = "The core of ProjecturEd: reactive cells, documents, references, operations, projections and the editor loop, with no concrete kind of data.",
         document = "documentation/design/concepts.md"),
    "ProjecturedPlatform" =>
        (summary = "What every kind of data shares: text, syntax, graphics, layout, widgets, panes, windows, the generic views and the application.",
         document = "documentation/package/README.md"),
    "ProjecturedAnthropic" =>
        (summary = "Runs the AI assistant of ProjecturEd with a Claude model, through the Anthropic API.",
         document = "documentation/package/adapter/anthropic/anthropic.md"),
    "ProjecturedBook" =>
        (summary = "Structured prose: a book, its chapters, paragraphs of styled text, lists and pictures.",
         document = "documentation/package/domain/book/book.md"),
    "ProjecturedChart" =>
        (summary = "Line, scatter, bar, histogram and strip charts as documents, drawn with no plotting library.",
         document = "documentation/package/domain/chart/chart.md"),
    "ProjecturedConsole" =>
        (summary = "Shows the editor in a terminal with ANSI colours, and reads the keys of the terminal.",
         document = "documentation/package/backend/console/console.md"),
    "ProjecturedDataFrames" =>
        (summary = "Shows a `DataFrame` of DataFrames.jl as a table that you can scroll, sort, filter and edit, while the data stays in the data frame.",
         document = "documentation/package/README.md"),
    "ProjecturedDatabase" =>
        (summary = "The interface of a database adapter, and the documents of a database connection.",
         document = "documentation/package/domain/database/database.md"),
    "ProjecturedDBCatalog" =>
        (summary = "The catalog of a database as a tree of documents: its tables and their columns.",
         document = "documentation/package/domain/database/database.md"),
    "ProjecturedFormula" =>
        (summary = "Named formulas that refer to each other and compute a value, as the cells of a spreadsheet do.",
         document = "documentation/package/domain/formula/formula.md"),
    "ProjecturedFSM" =>
        (summary = "Extended state machines: states, transitions on events, timers or conditions, and variables. A machine draws as a live diagram and generates a Julia module.",
         document = "documentation/package/domain/fsm/fsm.md"),
    "ProjecturedPivot" =>
        (summary = "A table cut into parts by the values of its dimensions, as nested row and column headers, with a view of each part in its cell.",
         document = "documentation/package/domain/pivot/pivot.md"),
    "ProjecturedGraph" =>
        (summary = "Node-and-edge diagrams in which each vertex holds a document of any kind.",
         document = "documentation/package/domain/graph/graph.md"),
    "ProjecturedJSON" =>
        (summary = "JSON data as a tree of documents that you edit in the JSON notation.",
         document = "documentation/package/domain/json/json.md"),
    "ProjecturedJulia" =>
        (summary = "Julia source code as a tree of documents that you edit in the Julia notation.",
         document = "documentation/package/domain/julia/julia.md"),
    "ProjecturedMarkdown" =>
        (summary = "A Markdown page as a tree of blocks and inlines.",
         document = "documentation/package/domain/markdown/markdown.md"),
    "ProjecturedMath" =>
        (summary = "A math formula as a tree of documents: its structure, not its picture and not its value.",
         document = "documentation/package/domain/math/math.md"),
    "ProjecturedACP" =>
        (summary = "Lets the AI assistant of ProjecturEd talk to an agent that runs its own loop, such as Claude, over the Agent Client Protocol (ACP).",
         document = "documentation/package/adapter/acp/acp.md"),
    "ProjecturedMCP" =>
        (summary = "Lets a client outside the process, such as an AI assistant, drive a running editor over the Model Context Protocol (MCP).",
         document = "documentation/package/adapter/mcp/mcp.md"),
    "ProjecturedODBC" =>
        (summary = "Connects the database documents to a live database through ODBC.jl, and runs its queries.",
         document = "documentation/package/adapter/odbc/odbc.md"),
    "ProjecturedOllama" =>
        (summary = "Runs the AI assistant of ProjecturEd with a model on your own machine, through a local Ollama server.",
         document = "documentation/package/adapter/ollama/ollama.md"),
    "ProjecturedOpenRouter" =>
        (summary = "A relevance model for the search of the AI assistant, which asks a model through the API of OpenRouter.",
         document = "documentation/package/adapter/openrouter/openrouter.md"),
    "ProjecturedPDF" =>
        (summary = "Writes a view as a vector PDF with selectable text, with no third-party package.",
         document = "documentation/package/backend/pdf/pdf.md"),
    "ProjecturedProcess" =>
        (summary = "An algorithm as a structured flowchart: steps, decisions, loops and jumps. It runs with breakpoints and a live trace.",
         document = "documentation/package/domain/process/process.md"),
    "ProjecturedRST" =>
        (summary = "reStructuredText as a tree of documents, with a parser and two presentations.",
         document = "documentation/package/domain/rst/rst.md"),
    "ProjecturedSDL" =>
        (summary = "Shows the editor in native windows with SDL2, and writes images of a view.",
         document = "documentation/package/backend/sdl/sdl.md"),
    "ProjecturedSequenceChart" =>
        (summary = "Sequence charts: lanes of occurrences with arrows between them, which show what happened where, in which order, and what caused what.",
         document = "documentation/package/domain/sequencechart/sequencechart.md"),
    "ProjecturedSQL" =>
        (summary = "A SQL statement as a tree of clause and expression documents, with a parser.",
         document = "documentation/package/domain/sql/sql.md"),
    "ProjecturedTulip" =>
        (summary = "Solves the relations of a constraint layout with the linear-programming solver Tulip.jl.",
         document = "documentation/package/adapter/tulip/tulip.md"),
    "ProjecturedVideo" =>
        (summary = "Records a scripted editing session as an `.mp4` file, with no window.",
         document = "documentation/package/backend/video/video.md"),
    "ProjecturedWeb" =>
        (summary = "Shows the editor in a web browser, through an HTTP and WebSocket server.",
         document = "documentation/package/backend/web/web.md"),
    "ProjecturedXML" =>
        (summary = "An XML document as a tree of elements, text nodes and attributes.",
         document = "documentation/package/domain/xml/xml.md"),
    "ProjecturedYAML" =>
        (summary = "YAML data as the tree of scalars, sequences and mappings that the JSON domain uses.",
         document = "documentation/package/domain/yaml/yaml.md"))

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
                           readme = name -> _format_projectured_package_readme(context, name),
                           tests = name -> _find_projectured_release_test(context, name),
                           workflow = _format_projectured_release_workflow,
                           overview = names -> _format_projectured_release_overview(context,
                                                                                     names),
                           julia_compat = PROJECTURED_JULIA_COMPAT, registry = registry,
                           kwargs...)
end

# The table `[auto-integration]` of the `Project.toml` of the package `name`, or
# `nothing` when it declares none.
_find_auto_integration(context::BuildContext, name) =
    get(TOML.parsefile(joinpath(get_package_directory(context, name), "Project.toml")),
        "auto-integration", nothing)

# The names joined as a person writes them: "A", "A and B", "A, B and C".
_join_names(names) =
    length(names) <= 1 ? join(names) : join(names[1:end-1], ", ") * " and " * names[end]

# How the package `name` loads: by a `using` line, and by AutoIntegration when it
# declares triggers.
function _format_projectured_load_text(context::BuildContext, name)
    declaration = _find_auto_integration(context, name)
    declaration === nothing && return "`using $name` loads it."
    triggers = sort(collect(keys(get(declaration, "triggers", Dict{String,Any}())));
                    by = trigger -> (trigger != "Projectured", trigger))
    when = _join_names(["`$trigger`" for trigger in triggers]) *
           (length(triggers) == 1 ? " is loaded" : " are loaded")
    get(declaration, "default", "manual") == "auto" ?
        "`using $name` loads it. [AutoIntegration]($AUTOINTEGRATION_URL) also loads it by itself when $when, " *
        "unless your environment sets it to `\"manual\"`." :
        "`using $name` loads it. [AutoIntegration]($AUTOINTEGRATION_URL) loads it by itself when $when, " *
        "if your environment sets it to `\"auto\"`."
end

# The README of the folder of one released package, which is also its page on
# GitHub: what it is, how to install and load it, and where its source is.
function _format_projectured_package_readme(context::BuildContext, name)
    haskey(PROJECTURED_PACKAGE_READMES, name) ||
        error("build_projectured_package_release!: $name has no README; add it to " *
              "PROJECTURED_PACKAGE_READMES")
    readme = PROJECTURED_PACKAGE_READMES[name]
    """
    # $name

    $(readme.summary)

    It is a package of [ProjecturEd]($PROJECTURED_SOURCE), a projectional editor:
    the data is the source, and every view is computed from it.
    [$(basename(readme.document))]($PROJECTURED_SOURCE/blob/main/$(readme.document))
    says more.

    ## Install

    The packages of ProjecturEd are in the registry
    [`ProjecturedRegistry`]($PROJECTURED_REGISTRY_URL). Add
    [General]($GENERAL_REGISTRY_URL) too, for the packages that they depend on. If
    General is there already, the line does nothing.

    ```
    pkg> registry add General
    pkg> registry add $PROJECTURED_REGISTRY_URL
    pkg> add $name
    ```

    $(_format_projectured_load_text(context, name))
    [The front page]($PROJECTURED_RELEASE_URL) says how the packages install and load,
    and [ProjecturEd in your own project]($PROJECTURED_SOURCE/blob/main/documentation/guide/own-project-guide.md)
    says how to open a window from your code.

    ## Source and licence

    The release of ProjecturEd writes this folder from
    [projectured-julia]($PROJECTURED_SOURCE); a change belongs there. The licence is
    the [Mozilla Public License 2.0]($MOZILLA_PUBLIC_LICENSE_URL), in [`LICENSE`](LICENSE).
    """
end

# The suite that tests a released package of this repository: its test package
# `<Name>Test` and its aggregator `test_<name>()`. The umbrella runs the part of
# its suite that only the umbrella can run.
function _find_projectured_release_test(context::BuildContext, name)
    name == "Projectured" &&
        return "ProjecturedTest" => _format_projectured_runtests(name, "ProjecturedTest",
                                                                 "test_integration")
    test_package = name * "Test"
    has_package_directory(context, test_package) || return nothing
    suite = "test_" * lowercase(chopprefix(name, "Projectured"))
    test_package => _format_projectured_runtests(name, test_package, suite)
end

# The package loads first, as a user loads it: a test package can reach the code
# that it tests through another package, as the suite of the umbrella reaches it
# through `ProjecturedAll`.
_format_projectured_runtests(name, test_package, suite) = """
    # The suite of `$test_package`, which the release holds in `test/` and the
    # registry serves. SDL draws into memory when no display is named.
    haskey(ENV, "SDL_VIDEODRIVER") || (ENV["SDL_VIDEODRIVER"] = "offscreen")
    using $name
    using $test_package
    $suite()
    """

# The front page of the release repository: what it is, how to install and load
# the packages, the integrations with their triggers, and one row for each package
# with the sentence of its README. The packages that a user meets first come
# first, then the others by name.
function _format_projectured_release_overview(context::BuildContext, names)
    core = ["Projectured", "ProjecturedKernel", "ProjecturedPlatform", "ProjecturedIntegrations",
            "ProjecturedAll"]
    order = [filter(in(names), core); sort(filter(!in(core), names))]
    # A package with tests has a workflow of its own, and its badge. A table of
    # GitHub has no column width, and a header does not wrap, so the spaces of the
    # header keep the column of the badges wide enough that GitHub does not scale
    # them down.
    badge(name) = _find_projectured_release_test(context, name) === nothing ? "" :
        "[![tests]($PROJECTURED_RELEASE_URL/actions/workflows/$name.yml/badge.svg)]" *
        "($PROJECTURED_RELEASE_URL/actions/workflows/$name.yml)"
    rows = join(["| [$name]($name) | $(badge(name)) | " *
                 "$(PROJECTURED_PACKAGE_READMES[name].summary) |\n" for name in order])
    # An integration declares a trigger beside the umbrella: the package that it joins.
    integrations = String[]
    for name in order
        declaration = _find_auto_integration(context, name)
        declaration === nothing && continue
        triggers = sort(collect(keys(get(declaration, "triggers", Dict{String,Any}())));
                        by = trigger -> (trigger != "Projectured", trigger))
        joined = filter(!=("Projectured"), triggers)
        isempty(joined) && continue
        links = [haskey(PROJECTURED_JOINED_PACKAGE_URLS, package) ?
                 "[$package]($(PROJECTURED_JOINED_PACKAGE_URLS[package]))" :
                 error("build_projectured_package_release!: $name joins $package, which has no " *
                       "repository; add it to PROJECTURED_JOINED_PACKAGE_URLS")
                 for package in joined]
        push!(integrations, "| [`$name`]($name) | $(_join_names(links)) | $(_join_names(triggers)) |\n")
    end
    """
    # Projectured.jl

    The released packages of [ProjecturEd]($PROJECTURED_SOURCE), a projectional
    editor: the data is the source, and every view is computed from it. Each folder
    is one package. The release of ProjecturEd writes this repository from
    [projectured-julia]($PROJECTURED_SOURCE), so a change belongs there.

    ## Install

    The packages are in the registry [`ProjecturedRegistry`]($PROJECTURED_REGISTRY_URL).
    Add [General]($GENERAL_REGISTRY_URL) too, for the packages that they depend on.
    If General is there already, the line does nothing.

    ```
    pkg> registry add General
    pkg> registry add $PROJECTURED_REGISTRY_URL
    ```

    Each package installs only what it needs. Add each package that you use by its
    name. A `using` line reaches only the packages that you added, so add the
    packages of other authors that you load too.

    ## Use

    To install and to load are two different steps. You can load in two ways.

    ### Let `Projectured` load the integrations

    ```
    pkg> add Projectured ProjecturedSDL ProjecturedDataFrames DataFrames SimpleDirectMediaLayer

    julia> using Projectured, DataFrames, SimpleDirectMediaLayer
    julia> display_in_editor(DataFrame(n = 1:100_000, square = (1:100_000) .^ 2))
    ```

    > The first `display_in_editor` of a session can take a long time before the
    > window opens. Julia compiles the code of the editor the first time that it
    > runs. The next calls in the same session do not compile it again, so the
    > window opens fast.

    `using Projectured` loads [the kernel](ProjecturedKernel),
    [the platform](ProjecturedPlatform) and [AutoIntegration]($AUTOINTEGRATION_URL).
    AutoIntegration loads a package that you installed when all its triggers are
    loaded. The order of the `using` lines does not matter. Each domain, the
    console, PDF and the model adapters load when `Projectured` is loaded. An
    integration loads when the package that it joins is loaded too:

    | Integration | It joins | It loads when these are loaded |
    | --- | --- | --- |
    $(join(integrations))
    A package that loads in this way puts no name into `Main`. To write
    `SdlBackend()`, add `using ProjecturedSDL`.

    ### Name each package

    ```
    pkg> add ProjecturedSDL ProjecturedDataFrames DataFrames

    julia> using DataFrames, ProjecturedSDL, ProjecturedDataFrames
    julia> display_in_editor(DataFrame(n = 1:100_000, square = (1:100_000) .^ 2))
    ```

    The session loads the packages that you name and the packages that they depend
    on. Nothing else loads. `ProjecturedDataFrames` brings DataFrames as its own
    dependency, but a `using` line reaches only a package that you added by name,
    so the `add` line names DataFrames too: without it, `using DataFrames` fails
    with "Package DataFrames not found in current path".

    ### Choose for each package

    Each package says if it loads by itself. You can change it for each package in
    the file `LocalPreferences.toml` beside the `Project.toml` of your environment:

    ```toml
    [AutoIntegration]
    ProjecturedSDL = "auto"
    ProjecturedDataFrames = "manual"
    ```

    `"auto"` loads the package when its triggers are loaded. `"manual"` loads it
    only when you name it. A package with no line keeps its own default. This call
    writes the same line, after you add AutoIntegration by name:

    ```
    pkg> add AutoIntegration

    julia> using AutoIntegration
    julia> set_auto_integration!("ProjecturedDataFrames", :manual)
    ```

    ### Load all integrations

    ```
    pkg> add ProjecturedIntegrations DataFrames SimpleDirectMediaLayer

    julia> using ProjecturedIntegrations, DataFrames, SimpleDirectMediaLayer
    ```

    [`ProjecturedIntegrations`](ProjecturedIntegrations) installs every integration and every package that
    they join. It loads an integration when the package that it joins is loaded,
    whatever `LocalPreferences.toml` says. Use it when you want all of them and do
    not want to choose.

    ### Why there are so many packages

    ProjecturEd joins many packages of other authors, and each join is one small
    package. Pkg installs all dependencies of a package and has no optional ones.
    So each integration is its own package, and you install only the ones that you
    add. Some users want the integrations to load by themselves, and some users
    name each package. The setting for each package lets you choose.

    ## Faster sessions

    A Julia session compiles the code that it runs, and it keeps that code only
    until it ends. So each new session that shows a data frame compiles the editor
    again. [AutoPrecompile]($AUTOPRECOMPILE_URL) keeps that code for the next session:

    ```
    pkg> add AutoPrecompile

    julia> using AutoPrecompile, Projectured, DataFrames, SimpleDirectMediaLayer
    julia> display_in_editor(DataFrame(n = 1:100_000, square = (1:100_000) .^ 2))
    ```

    Each package of ProjecturEd ships the precompile statements that its
    recordings compiled, in its folder `precompile/`. In the first session,
    AutoPrecompile builds one package image for the packages that you loaded, in
    the background, and logs that it does. A later session that loads the same
    packages loads that image, so it compiles almost nothing of what the
    recordings hold. The images take at most 2048 MB together; the entry
    `disk_limit_mb` of the table `[AutoPrecompile]` in `LocalPreferences.toml`
    sets another limit.

    ## Which repository is which

    | Repository | What it is |
    | --- | --- |
    | [projectured-julia]($PROJECTURED_SOURCE) | The source: the application, the examples, the tests and the guides. A change belongs there. |
    | [Projectured.jl]($PROJECTURED_RELEASE_URL) | This repository: the released packages, which the release writes from projectured-julia. |
    | [ProjecturedRegistry]($PROJECTURED_REGISTRY_URL) | The Julia registry that names each version of these packages. |
    | [AutoIntegration.jl]($AUTOINTEGRATION_URL) | The package that loads an installed package when its triggers are loaded. `Projectured` depends on it. |
    | [AgentClientProtocol.jl]($AGENT_CLIENT_PROTOCOL_URL) | The Agent Client Protocol (ACP) in Julia, for a client and for an agent. `ProjecturedACP` depends on it. |
    | [ClaudeCodeACP.jl]($CLAUDE_CODE_ACP_URL) | An ACP agent that runs Claude Code. `ProjecturedACP` runs it as its built-in agent. |
    | [AutoPrecompile.jl]($AUTOPRECOMPILE_URL) | The package that builds one package image for the packages that a session loads, from recorded precompile statements. |

    ## The packages

    | Package | &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Tests&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | What it holds or does |
    | --- | :---: | --- |
    $rows
    ## Tests

    Each package holds its tests in `test/`. Each package with tests has a workflow
    of its own in [`.github/workflows`](.github/workflows), `<Package>.yml`, which
    runs them on every push, on Julia $PROJECTURED_JULIA_COMPAT; its badge is in the
    table above.

    ## Licence

    The [Mozilla Public License 2.0]($MOZILLA_PUBLIC_LICENSE_URL), in [`LICENSE`](LICENSE).
    """
end

# The name of the workflow of a package, which its badge shows as its label: the
# slice, without the prefix, so the badge fits a column of a table; the umbrella
# keeps its name.
_get_workflow_name(name) = name == "Projectured" ? name : chopprefix(name, "Projectured")

# The workflow of the release repository: one job for each package and Julia
# version. A job develops the folders that the test of its package needs, runs
# `Pkg.test` with coverage, and sends the coverage of the code of the package to
# Codecov.
function _format_projectured_release_workflow(jobs)
    versions = join(("'$version'" for version in PROJECTURED_CI_JULIA_VERSIONS), ", ")
    matrix = join(["        julia: [$versions]",
                   "        package:",
                   ("          - $(job.name)" for job in jobs)...,
                   "        include:",
                   ("          - {package: $(job.name), " *
                    "develop: '$(join(job.develop, ' '))', " *
                    "coverage: '$(join(job.coverage, ','))'}" for job in jobs)...], "\n")
    # A workflow runs when a folder that its test develops changes, or the
    # workflow itself, so a push runs the tests of the packages that it touches.
    patterns = sort!(unique([["$folder/**" for job in jobs for folder in job.develop];
                             [".github/workflows/$(job.name).yml" for job in jobs]]))
    paths = join(["      - '$pattern'" for pattern in patterns], "\n")
    """
    # The test of $(join([job.name for job in jobs], ", ")), with coverage. The
    # release of ProjecturEd writes this file, from
    # source/tool/builder/ProjecturedProgram.jl in projectured-julia.
    #
    # A package reaches its siblings through a registry, which holds a version only
    # after its commit. So a job develops the folders of the packages that its test
    # needs, and tests this commit. It runs when one of those folders changes.
    name: $(join([_get_workflow_name(job.name) for job in jobs], ", "))

    on:
      push:
        branches: [main]
        paths:
    $paths
      pull_request:
        paths:
    $paths
      workflow_dispatch:

    concurrency:
      group: \${{ github.workflow }}-\${{ github.ref }}
      cancel-in-progress: true

    permissions:
      contents: read

    jobs:
      test:
        name: \${{ matrix.package }}, Julia \${{ matrix.julia }}
        runs-on: ubuntu-latest
        timeout-minutes: 180
        permissions:
          contents: read
          id-token: write          # the upload to Codecov through OIDC
        strategy:
          fail-fast: false
          matrix:
    $matrix
        env:
          SDL_VIDEODRIVER: offscreen      # SDL draws into memory; the runner has no display
          JULIA_PKG_PRECOMPILE_AUTO: '0'  # the test compiles what it loads
          PACKAGE: \${{ matrix.package }}
          DEVELOP: \${{ matrix.develop }}
        steps:
          - uses: actions/checkout@v7
          - uses: julia-actions/setup-julia@v3
            with:
              version: \${{ matrix.julia }}
          - uses: julia-actions/cache@v3
            with:
              # A key with the matrix would hold the list of folders, which is
              # longer than a key may be.
              include-matrix: false
              cache-name: julia-cache;package=\${{ matrix.package }};julia=\${{ matrix.julia }}
          # AutoIntegration, AgentClientProtocol and ClaudeCodeACP are packages of
          # other repositories, which no job develops. They come from
          # ProjecturedRegistry, which the job adds beside General.
          - name: Add the registries
            run: >-
              julia --project="\$RUNNER_TEMP/environment"
              -e 'using Pkg; Pkg.Registry.add("General");
              Pkg.Registry.add(url = "$PROJECTURED_REGISTRY_URL")'
          - name: Develop the packages that the test needs
            run: >-
              julia --project="\$RUNNER_TEMP/environment"
              -e 'using Pkg; Pkg.develop([PackageSpec(path = abspath(folder))
              for folder in split(ENV["DEVELOP"])])'
          - name: Test
            run: >-
              julia --project="\$RUNNER_TEMP/environment"
              -e 'using Pkg; Pkg.test(ENV["PACKAGE"]; coverage = true)'
          - uses: julia-actions/julia-processcoverage@v1
            with:
              directories: \${{ matrix.coverage }}
          - uses: codecov/codecov-action@v7
            with:
              files: lcov.info
              flags: \${{ matrix.package }}
              use_oidc: true
              fail_ci_if_error: false
    """
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
