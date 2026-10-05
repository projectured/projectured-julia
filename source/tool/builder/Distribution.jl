# Fragment of `BuilderModule` — turn a bundle into something a person
# copies to another machine.
#
# The archive is the small half. The half worth writing is the check, because
# nothing here proves a bundle runs on a machine that did not build it until it
# is actually started on one. The fonts already showed why that check matters: a
# compiled `StyleFont` carried the path `asset/font` had on the build machine,
# and a bundle read its fonts out of that checkout and ran on the machine that
# built it and nowhere else. [`bundle_fonts!`](@ref) repairs it, and nothing
# checked that the repair worked until `check_relocation` did.

"""
    build_distribution(context; name, bundle, requirements, expect, version,
                         output, staging, source, licence_texts, project,
                         licence_cache, credits, extra_texts, source_archive) -> String

Check that the bundle of the binary called `name` travels, and write it as an
archive. Answers the path of the archive.

- `bundle` — the directory a build wrote, `build/<name>` under `context.root`
  unless another is named.
- `requirements` — what the target machine must still have, one sentence each.
  They go into the README beside the binary, and they are the one thing that
  differs between distributions.
- `licences` — the licence files of `context.root`, copied into the archive and
  named in the README. A licence that asks for its notice in every copy is
  broken by an archive that leaves it out, so a missing file stops the build.
- `expect` — paths inside the bundle that must exist and hold something, such as
  `"share/projectured/font"`. What a build declared it bundled, asserted.
- `staging` — where the bundle is copied to be tested. **Outside `context.root`**,
  because a copy tested in place proves nothing about a copy.
  [`get_staging_root`](@ref) chooses it when a caller does not.
- `hidden` — folders that look empty to the copy while it is tested, so that a
  copy that still reads the checkout or the depot fails here. The default is
  [`get_hidden_directories`](@ref).
- `check` — a test of its own that the program needs, or `nothing`. It is
  called as `check(executable, directory, hidden)` with the copied executable,
  a folder it can write into, and `hidden`, after the start test and before
  the archive.
- `source` — where the source code of the program is, which the README names
  with the tag of `version`; `nothing` names none.
- `licence_texts` — whether the archive carries the licence texts of what the
  bundle holds besides the program: [`bundle_licence_texts!`](@ref) writes them,
  from `project`, the app package of the build, with the downloads it needs kept
  in `licence_cache`. `credits` are sentences that a licence asks to appear in
  the documentation; the README of the archive and the index hold them.
  `extra_texts`, `"<name>" => "<file of context.root>"`, adds the text of a
  library whose JLL names no artifact to take it from, and `data_texts` the text
  of data from others that the code of the program holds.
- `source_archive` — the file name of the archive of the sources that the
  licences of some libraries ask for ([`build_source_archive`](@ref)), which the
  README names; `nothing` names none.

The archive unpacks into `<name>-<version>/` and never into the directory it was
unpacked in.
"""
function build_distribution(context::BuildContext; name::AbstractString,
                              bundle::AbstractString = joinpath(context.root, "build", String(name)),
                              requirements = String[],
                              licences = String[],
                              expect = String[],
                              version::AbstractString = context.version,
                              output::AbstractString = joinpath(context.root, "build"),
                              staging::Union{AbstractString,Nothing} = nothing,
                              hidden = get_hidden_directories(context),
                              check = nothing,
                              source::Union{AbstractString,Nothing} = nothing,
                              licence_texts::Bool = true,
                              project::AbstractString = joinpath(context.root, "build",
                                  "app", String(name)),
                              licence_cache::AbstractString = joinpath(context.root,
                                  "build", "licence-cache"),
                              credits = String[],
                              extra_texts = Pair{String,String}[],
                              data_texts = Pair{String,String}[],
                              source_archive::Union{AbstractString,Nothing} = nothing)
    bundle = abspath(bundle)
    isdir(bundle) ||
        error("build_distribution: no bundle at $bundle — build the executable first")
    executable = joinpath(bundle, "bin", String(name))
    isfile(executable) ||
        error("build_distribution: $bundle holds no bin/$name — the build did not finish")

    for path in expect
        full = joinpath(bundle, String(path))
        (isdir(full) ? !isempty(readdir(full)) : isfile(full)) ||
            error("build_distribution: the build said it bundled $(repr(String(path))), " *
                  "and $full is missing or empty")
    end
    isempty(expect) || @info "The bundle holds what the build declared" count = length(expect)
    _check_julia_libstdcxx(bundle)
    if Sys.islinux()
        missing_libraries = collect_missing_libraries(bundle)
        isempty(missing_libraries) ||
            error("build_distribution: the bundle needs libraries that it does not " *
                  "carry, and that a machine other than this one may not have:\n" *
                  join(["  $library, which $file needs"
                        for (library, file) in missing_libraries],
                       "\n"))
    end

    directory = "$(name)-$(version)"
    root = staging === nothing ? mktempdir(get_staging_root()) : abspath(String(staging))
    # Refused before the directory is made, so a refusal leaves nothing behind.
    startswith(root, context.root) &&
        error("build_distribution: the staging directory is inside $(context.root) — a copy " *
              "tested in the checkout it was built in proves nothing about a copy")
    mkpath(root)
    staged = joinpath(root, directory)
    ispath(staged) && rm(staged; recursive = true)
    @info "Copying the bundle out to test it" staged
    cp(bundle, staged)

    check_relocation(joinpath(staged, "bin", String(name)), root; hidden = hidden)
    if check !== nothing
        check_directory = mkpath(joinpath(root, "check"))
        check(joinpath(staged, "bin", String(name)), check_directory, hidden)
        rm(check_directory; recursive = true, force = true)
    end
    for licence in licences
        source = joinpath(context.root, String(licence))
        isfile(source) ||
            error("build_distribution: no licence file at $source — an archive without " *
                  "its licence may not be distributed")
        cp(source, joinpath(staged, basename(String(licence))))
    end
    licence_texts &&
        bundle_licence_texts!(staged; project, cache = licence_cache, credits,
                              extra_texts = [name => joinpath(context.root, file)
                                             for (name, file) in extra_texts],
                              data_texts = [name => joinpath(context.root, file)
                                            for (name, file) in data_texts])
    write_readme(staged; name, version, requirements, licences, source,
                 third_party = licence_texts, credits, source_archive)

    mkpath(output)
    archive = joinpath(abspath(output),
                       "$(directory)-$(lowercase(string(Sys.KERNEL)))-$(Sys.ARCH).tar.gz")
    @info "Writing the archive" archive
    run(`tar -C $root -czf $archive $directory`)
    report_distribution(archive)
    staging === nothing && rm(root; recursive = true, force = true)
    archive
end

"""
    GLIBC_LIBRARIES

The shared libraries that every Linux machine with glibc has: a bundle may need
them and not carry them.
"""
const GLIBC_LIBRARIES = ["ld-linux-x86-64.so.2", "libc.so.6", "libdl.so.2", "libm.so.6",
                         "libpthread.so.0", "librt.so.1", "libutil.so.1",
                         "libresolv.so.2", "libanl.so.1", "libmvec.so.1", "libnsl.so.1"]

"""
    collect_missing_libraries(bundle;
                              system = GLIBC_LIBRARIES) -> Vector{Pair{String,String}}

Every shared library that a file of `bundle` needs, by the `NEEDED` entries that
`readelf -d` shows, and that neither the bundle nor `system` provides, as
`"<library>" => "<file that needs it>"`. The test of a copy can not see such a
library when the machine that builds has it, for example in `/usr/local/lib`.
"""
function collect_missing_libraries(bundle::AbstractString; system = GLIBC_LIBRARIES)
    Sys.which("readelf") === nothing &&
        error("collect_missing_libraries: install binutils; the check reads each " *
              "library with readelf")
    provided = Set{String}(system)
    files = String[]
    for (directory, _, names) in walkdir(bundle), name in names
        occursin(r"\.so(\.|$)", name) && push!(provided, name)
        path = joinpath(directory, name)
        (isfile(path) && !islink(path)) && push!(files, path)
    end
    missing_libraries = Pair{String,String}[]
    for path in files
        _is_elf_file(path) || continue
        for line in eachline(ignorestatus(`readelf -d $path`))
            needed = match(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", line)
            needed === nothing && continue
            needed.captures[1] in provided ||
                push!(missing_libraries, needed.captures[1] => relpath(path, bundle))
        end
    end
    sort!(unique!(missing_libraries))
end

_is_elf_file(path) = open(io -> read(io, 4), path) == UInt8[0x7f, 0x45, 0x4c, 0x46]

# A distribution carries the libstdc++ of Julia. PackageCompiler copies the one
# that the building Julia loaded, and Julia loads the machine's own when it is
# newer; that one can need a newer glibc than a user's machine has, and its source
# is not the source of Julia's. A binary still loads a newer libstdc++ of its
# user's machine when there is one.
function _check_julia_libstdcxx(bundle::AbstractString)
    Sys.islinux() || return nothing
    bundled = joinpath(bundle, "lib", "julia", "libstdc++.so.6")
    own = joinpath(Sys.BINDIR, "..", "lib", "julia", "libstdc++.so.6")
    (isfile(bundled) && isfile(own)) || return nothing
    read(bundled) == read(own) ||
        error("build_distribution: the bundle carries $(basename(realpath(bundled))) " *
              "of this machine, not $(basename(realpath(own))) of Julia. Start the " *
              "build with JULIA_PROBE_LIBSTDCXX=0, as bin/build_projectured does.")
    nothing
end

"""
    get_staging_root() -> String

Where a bundle is copied to be tested, when the caller names no directory.

**`/var/tmp` before `/tmp`, and this is not a preference.** A bundle can run to
several hundred megabytes, and `/tmp` is a `tmpfs` on many machines — a copy
there is a copy into memory. `/var/tmp` is the place the filesystem standard
keeps for large temporary files, and it is on a disk.

`TMPDIR` wins over both, because a person who set it meant it.
"""
function get_staging_root()
    haskey(ENV, "TMPDIR") && return ENV["TMPDIR"]
    isdir("/var/tmp") && return "/var/tmp"
    return tempdir()
end

"""
    get_hidden_directories(context) -> Vector{String}

The folders that a copied binary must not need: the repository of `context`,
the repository of each of its package folders, and the depot of this Julia.
"""
function get_hidden_directories(context::BuildContext)
    directories = vcat([context.root],
                       [dirname(abspath(root)) for root in context.package_roots],
                       [first(DEPOT_PATH)])
    unique(filter(isdir, [normpath(directory) for directory in directories]))
end

"""
    make_hidden_command(command, hidden) -> Cmd

`command`, run so that each folder in `hidden` looks empty to it. `bwrap` puts
an empty folder over each one and leaves the rest of the file system as it is.
With no folder in `hidden`, the answer is `command`. Set the environment and
the directory on the answer, not on `command`.

The program runs in a process namespace of its own (`--unshare-pid`). When
`bwrap` stops, the kernel stops every process in that namespace, so a signal to
the answer stops the program too. `--die-with-parent` alone does not do that.
"""
function make_hidden_command(command::Cmd, hidden)
    isempty(hidden) && return command
    Sys.which("bwrap") === nothing &&
        error("make_hidden_command: install bubblewrap (`bwrap`). The test of a copy " *
              "needs it to hide " * join(hidden, ", "))
    arguments = ["--dev-bind", "/", "/", "--unshare-pid", "--die-with-parent"]
    for directory in hidden
        append!(arguments, ["--tmpfs", String(directory)])
    end
    `bwrap $arguments -- $(command.exec)`
end

"""
    check_relocation(executable, working_directory; hidden = String[]) -> Nothing

Start the copied binary where it now stands, with no depot, and make it answer.

**`--build-info` is what it is asked**, because the builder writes that flag into
every binary itself — see [`get_smoke_flag`](@ref). A binary that answers it has
loaded its system image, reached module scope and read a constant out of it, from
a directory it was not built in.

**An empty `JULIA_DEPOT_PATH` is the point of the test.** `create_app` is supposed
to bundle every artifact a binary opens; a binary that still reaches into the
depot that built it fails here and nowhere else.

**`hidden` puts the checkout out of sight.** The checkout is still on the
disk, and a binary that reads a file of it by an absolute path finds it on this
machine. With the folders of [`get_hidden_directories`](@ref) hidden, that
binary fails here as it fails on another machine.
"""
function check_relocation(executable::AbstractString, working_directory::AbstractString;
                          hidden = String[])
    depot = mktempdir()
    try
        environment = copy(ENV)
        environment["JULIA_DEPOT_PATH"] = depot
        environment["JULIA_LOAD_PATH"] = ""
        command = setenv(make_hidden_command(`$executable $(get_smoke_flag())`, hidden),
                         environment; dir = working_directory)
        answer = IOBuffer()
        start = time()
        process = run(pipeline(command; stdout = answer, stderr = answer); wait = false)
        wait(process)
        seconds = round(time() - start; digits = 2)
        text = String(take!(answer))
        success(process) ||
            error("build_distribution: the copied binary answered $(get_smoke_flag()) with " *
                  "exit code $(process.exitcode), so this bundle does not travel:\n" * text)
        isempty(strip(text)) &&
            error("build_distribution: the copied binary answered $(get_smoke_flag()) with " *
                  "nothing, so its build record did not survive the copy")
        # The binary says what it is, and this is where it is believed. An
        # incremental image is built on top of the base one for a fast rebuild
        # while developing; it carries the whole base image and nobody should be
        # handed one.
        occursin(INCREMENTAL_MARK, text) &&
            error("build_distribution: this binary says it was built incrementally, and " *
                  "an incremental image is for a rebuild while developing. Build it " *
                  "again without `incremental` before you archive it.")
        @info "The copied bundle starts with no depot" seconds hidden
    finally
        rm(depot; recursive = true, force = true)
    end
    nothing
end

"""
    write_readme(staged; name, version, requirements, licences, source,
                 third_party, credits, source_archive) -> String

What a person who unpacks the archive reads. `source`, when a caller gives it,
says where the source code of this version is, which a licence such as MPL-2.0
asks of a program in executable form. `third_party` says that the archive
carries the licences of its other parts, and `credits` are sentences that a
licence asks to appear in the documentation.

The requirements are the reason a distribution is a function per binary rather
than one call: what the target machine still needs is the one thing that differs
between them.
"""
function write_readme(staged::AbstractString; name, version, requirements,
                        licences = String[],
                        source::Union{AbstractString,Nothing} = nothing,
                        third_party::Bool = false,
                        credits = String[],
                        source_archive::Union{AbstractString,Nothing} = nothing)
    lines = ["$name $version",
             "",
             "Built $(Dates.format(Dates.now(), "yyyy-mm-dd")) by ProjecturedBuilder, for " *
                 "$(lowercase(string(Sys.KERNEL))) on $(Sys.ARCH).",
             "",
             "Run it:",
             "",
             "    ./bin/$name --help",
             "",
             "It needs nothing installed but what is listed below. The system image, the",
             "shared libraries and the artifacts are all in this directory.",
             "",
             "It is compiled for several processor families and picks one at startup, so it",
             "runs on a processor that is not the one that compiled it. `--build-info` names",
             "the families.",
             ""]
    if isempty(requirements)
        append!(lines, ["This binary needs nothing else on the machine.", ""])
    else
        push!(lines, "What this machine must still have:")
        push!(lines, "")
        for requirement in requirements
            push!(lines, "  - " * String(requirement))
        end
        push!(lines, "")
    end
    if !isempty(licences)
        push!(lines, "The licence of this software:")
        push!(lines, "")
        for licence in licences
            push!(lines, "  - " * basename(String(licence)))
        end
        push!(lines, "")
    end
    if source !== nothing
        push!(lines, "The source code of this version: $source, tag v$version.")
        push!(lines, "")
    end
    if third_party
        push!(lines, "The licences of the other parts of this archive, the Julia " *
                     "runtime and the")
        push!(lines, "libraries among them: share/licenses/README.")
        push!(lines, "")
    end
    if source_archive !== nothing
        push!(lines, "The source code of the libraries under the LGPL and the " *
                     "GPL in this archive:")
        push!(lines, "$source_archive, beside this archive in the same release.")
        push!(lines, "")
    end
    for credit in credits
        push!(lines, String(credit))
    end
    isempty(credits) || push!(lines, "")
    push!(lines, "What went into this build:")
    push!(lines, "")
    push!(lines, "    ./bin/$name --build-info")
    push!(lines, "")
    path = joinpath(staged, "README")
    write(path, join(lines, "\n") * "\n")
    path
end

"""
    report_distribution(archive) -> Nothing

The two numbers a distribution records: how large the archive is, and the
SHA-256 a person checks it against.
"""
function report_distribution(archive::AbstractString)
    size_bytes = filesize(archive)
    # Streamed rather than read whole: a distribution archive can be larger
    # than it is polite to hold in memory.
    digest = open(sha256, archive)
    @info "Wrote the distribution" size_MB = round(size_bytes / 1024^2; digits = 1) sha256 = bytes2hex(digest)
    nothing
end
