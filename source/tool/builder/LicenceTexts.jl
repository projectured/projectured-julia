# Fragment of `BuilderModule` — the licence texts of what a bundle holds
# besides the program.
#
# A bundle carries more than the program: the runtime of Julia and the libraries
# it ships, the artifacts of the JLL packages, and the Julia packages compiled
# into the image. Their licences ask for their texts in every copy. Each artifact
# already carries its own texts under `share/licenses/`. The runtime of Julia
# carries only its `LICENSE.md`, and the image carries no text of the packages
# compiled into it. This collects those, for exactly the versions the bundle
# holds, and writes an index of all of it.

"""
    bundle_licence_texts!(directory; project, cache, credits, extra_texts, data_texts,
                          julia_thirdparty, stdlib, depots) -> String

Write into `share/licenses/` of `directory`, a copy of a bundle that is about to
be archived, and answer the path of the index it writes there, `README`:

- `julia/` — the `LICENSE.md` of this Julia, and its `THIRDPARTY.md`, from
  `julia_thirdparty`: a URL or a path, by default the file of the tag of this
  version on GitHub.
- `stdlib/<Name>/` — the texts of each standard-library JLL of this Julia, from
  the `share/licenses/` of its artifact for this platform. The artifact is
  downloaded once, checked against its SHA-256, and kept in `cache`.
- `stdlib/<Name>/` also for each `"<Name>" => "<file>"` of `extra_texts`: a
  library that Julia ships and whose JLL names no artifact to take its text
  from.
- `packages/<Name>/` — the licence files of each package of the manifest of
  `project` that came from a registry, found in `depots`.
- `data/<Name>/` — for each `"<Name>" => "<file>"` of `data_texts`: data from
  others that the code of the program holds, such as the colours of a palette.
- `README` — what each folder holds, the texts that each artifact of the bundle
  carries in its own `share/licenses/`, and `credits`: sentences that a licence
  asks to appear in the documentation.
"""
function bundle_licence_texts!(directory::AbstractString; project::AbstractString,
                               cache::AbstractString,
                               credits = String[],
                               extra_texts = Pair{String,String}[],
                               data_texts = Pair{String,String}[],
                               julia_thirdparty::AbstractString =
                                   "https://raw.githubusercontent.com/JuliaLang/julia/v" *
                                   "$(VERSION)/THIRDPARTY.md",
                               stdlib::AbstractString = Sys.STDLIB,
                               depots = DEPOT_PATH)
    licenses = joinpath(directory, "share", "licenses")
    mkpath(cache)

    julia = joinpath(licenses, "julia")
    mkpath(julia)
    julia_licence = normpath(joinpath(Sys.BINDIR, "..", "LICENSE.md"))
    isfile(julia_licence) ||
        error("bundle_licence_texts!: this Julia has no LICENSE.md at $julia_licence")
    cp(julia_licence, joinpath(julia, "LICENSE.md"); force = true)
    _fetch_licence_file(julia_thirdparty, joinpath(julia, "THIRDPARTY.md"))

    stdlib_names = _bundle_stdlib_licences!(joinpath(licenses, "stdlib"), stdlib, cache)
    for (name, file) in extra_texts
        isfile(file) || error("bundle_licence_texts!: no licence text at $file for $name")
        mkpath(joinpath(licenses, "stdlib", name))
        cp(file, joinpath(licenses, "stdlib", name, basename(file)); force = true)
        push!(stdlib_names, name)
    end
    sort!(unique!(stdlib_names))
    data_names = String[]
    for (name, file) in data_texts
        isfile(file) || error("bundle_licence_texts!: no licence text at $file for $name")
        mkpath(joinpath(licenses, "data", name))
        cp(file, joinpath(licenses, "data", name, basename(file)); force = true)
        push!(data_names, name)
    end
    sort!(unique!(data_names))
    packages = _bundle_package_licences!(joinpath(licenses, "packages"), project, depots)
    artifacts = _collect_artifact_licences(directory)

    lines = ["The licences of what this program carries besides its own code",
             "",
             "The program's own licence is beside the program, in the top folder.",
             "",
             "julia/LICENSE.md is the licence of the Julia runtime, and " *
             "julia/THIRDPARTY.md",
             "names the licences of the parts that Julia ships with it.",
             "",
             "The libraries that Julia ships (lib/julia, libexec/julia, " *
             "share/julia/cert.pem),",
             "each with its texts in stdlib/<name>/:",
             ""]
    append!(lines, ["  " * name for name in stdlib_names])
    append!(lines, ["",
                    "The Julia packages compiled into the program, each with its " *
                    "licence files in",
                    "packages/<name>/:", ""])
    for (name, version, files) in packages
        push!(lines,
              "  $name $version" *
              (isempty(files) ? " (it carries no licence file)" : ""))
    end
    append!(lines, ["",
                    "The libraries of the artifacts, each with its texts in the " *
                    "artifact itself:",
                    ""])
    append!(lines, ["  $name: $path" for (name, path) in artifacts])
    if !isempty(data_names)
        append!(lines, ["",
                        "The data from others that the code of the program holds, " *
                        "such as the colours",
                        "of its palettes, each with its texts in data/<name>/:",
                        ""])
        append!(lines, ["  " * name for name in data_names])
    end
    if !isempty(credits)
        append!(lines, ["", "Credits that these licences ask for:", ""])
        append!(lines, ["  " * String(credit) for credit in credits])
    end
    readme = joinpath(licenses, "README")
    write(readme, join(lines, "\n") * "\n")
    readme
end

# A file by URL or by path.
function _fetch_licence_file(source::AbstractString, target::AbstractString)
    if startswith(source, "http://") || startswith(source, "https://") ||
       startswith(source, "file://")
        run(`curl -sfL --max-time 600 -o $target $source`)
    else
        cp(source, target; force = true)
    end
    target
end

# The texts of every standard-library JLL, from its artifact for this platform.
# Answers the names of the folders of texts, sorted.
function _bundle_stdlib_licences!(target::AbstractString, stdlib::AbstractString,
                                  cache::AbstractString)
    mkpath(target)
    names = String[]
    for jll in sort(readdir(stdlib))
        toml = joinpath(stdlib, jll, "StdlibArtifacts.toml")
        (endswith(jll, "_jll") && isfile(toml)) || continue
        for (_, meta) in Pkg.Artifacts.select_downloadable_artifacts(
                toml; platform = Base.BinaryPlatforms.HostPlatform())
            place = first(meta["download"])
            tarball = joinpath(cache, place["sha256"] * ".tar.gz")
            isfile(tarball) || _fetch_licence_file(place["url"], tarball)
            digest = bytes2hex(open(sha256, tarball))
            digest == place["sha256"] ||
                error("bundle_licence_texts!: the artifact of $jll at $(place["url"]) " *
                      "has SHA-256 $digest, not $(place["sha256"])")
            unpacked = mktempdir(get_staging_root())
            try
                run(ignorestatus(`tar -xzf $tarball -C $unpacked
                                  --wildcards '*share/licenses/*'`))
                found = joinpath(unpacked, "share", "licenses")
                isdir(found) || continue
                for name in readdir(found)
                    cp(joinpath(found, name), joinpath(target, name); force = true)
                    push!(names, name)
                end
            finally
                rm(unpacked; recursive = true, force = true)
            end
        end
    end
    sort!(unique!(names))
end

# The licence files of each package of the manifest of `project` that came from
# a registry, from the depot that holds it. Answers `(name, version, files)`.
function _bundle_package_licences!(target::AbstractString, project::AbstractString,
                                   depots)
    manifest = TOML.parsefile(joinpath(project, "Manifest.toml"))
    found = Tuple{String,String,Vector{String}}[]
    for (name, entries) in sort!(collect(get(manifest, "deps", Dict{String,Any}()));
                                 by = first)
        entry = entries[1]
        haskey(entry, "git-tree-sha1") || continue
        slug = Base.version_slug(Base.UUID(entry["uuid"]),
                                 Base.SHA1(entry["git-tree-sha1"]))
        folder = nothing
        for depot in depots
            candidate = joinpath(depot, "packages", name, slug)
            isdir(candidate) && (folder = candidate; break)
        end
        folder === nothing &&
            error("bundle_licence_texts!: no depot holds $name " *
                  "$(get(entry, "version", "")) (slug $slug)")
        files = filter(file -> occursin(r"^(licen[cs]e|copying|notice)"i, file) &&
                               isfile(joinpath(folder, file)), readdir(folder))
        isempty(files) || mkpath(joinpath(target, name))
        for file in files
            cp(joinpath(folder, file), joinpath(target, name, file); force = true)
        end
        push!(found, (name, get(entry, "version", ""), files))
    end
    found
end

# The texts that each artifact of the bundle carries itself, as
# `(name, path relative to the bundle)`, sorted by name.
function _collect_artifact_licences(directory::AbstractString)
    artifacts = joinpath(directory, "share", "julia", "artifacts")
    found = Pair{String,String}[]
    isdir(artifacts) || return found
    for hash in readdir(artifacts)
        licenses = joinpath(artifacts, hash, "share", "licenses")
        isdir(licenses) || continue
        for name in readdir(licenses)
            push!(found, name => relpath(joinpath(licenses, name), directory))
        end
    end
    sort!(found; by = first)
end
