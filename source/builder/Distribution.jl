# Fragment of `ProjecturedBuilder` — turn a bundle into something a person
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
                         output, staging) -> String

Check that the bundle of the binary called `name` travels, and write it as an
archive. Answers the path of the archive.

- `bundle` — the directory a build wrote, `build/<name>` under `context.root`
  unless another is named.
- `requirements` — what the target machine must still have, one sentence each.
  They go into the README beside the binary, and they are the one thing that
  differs between distributions.
- `expect` — paths inside the bundle that must exist and hold something, such as
  `"share/projectured/font"`. What a build declared it bundled, asserted.
- `staging` — where the bundle is copied to be tested. **Outside `context.root`**,
  because a copy tested in place proves nothing about a copy.
  [`get_staging_root`](@ref) chooses it when a caller does not.

The archive unpacks into `<name>-<version>/` and never into the directory it was
unpacked in.
"""
function build_distribution(context::BuildContext; name::AbstractString,
                              bundle::AbstractString = joinpath(context.root, "build", String(name)),
                              requirements = String[],
                              expect = String[],
                              version::AbstractString = context.version,
                              output::AbstractString = joinpath(context.root, "build"),
                              staging::Union{AbstractString,Nothing} = nothing)
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

    check_relocation(joinpath(staged, "bin", String(name)), root)
    write_readme(staged; name, version, requirements)

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
    check_relocation(executable, working_directory) -> Nothing

Start the copied binary where it now stands, with no depot, and make it answer.

**`--build-info` is what it is asked**, because the builder writes that flag into
every binary itself — see [`get_smoke_flag`](@ref). A binary that answers it has
loaded its system image, reached module scope and read a constant out of it, from
a directory it was not built in.

**An empty `JULIA_DEPOT_PATH` is the point of the test.** `create_app` is supposed
to bundle every artifact a binary opens; a binary that still reaches into the
depot that built it fails here and nowhere else.

**What this does not prove.** The checkout is still on the disk, so this cannot
show that nothing reads it by an absolute path. Only a machine without the
checkout shows that. It proves the depot is not needed and that the bundle starts
somewhere else, which is what fails first.
"""
function check_relocation(executable::AbstractString, working_directory::AbstractString)
    depot = mktempdir()
    try
        environment = copy(ENV)
        environment["JULIA_DEPOT_PATH"] = depot
        environment["JULIA_LOAD_PATH"] = ""
        command = setenv(`$executable $(get_smoke_flag())`, environment; dir = working_directory)
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
        @info "The copied bundle starts with no depot" seconds
    finally
        rm(depot; recursive = true, force = true)
    end
    nothing
end

"""
    write_readme(staged; name, version, requirements) -> String

What a person who unpacks the archive reads.

The requirements are the reason a distribution is a function per binary rather
than one call: what the target machine still needs is the one thing that differs
between them.
"""
function write_readme(staged::AbstractString; name, version, requirements)
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
