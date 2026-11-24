# Fragment of `BuilderModule` — what a build removes from its bundle: the files of
# the artifact folders that no run reads, and the libraries of the Julia runtime
# that nothing links.

"""
    UNUSED_RUNTIME_LIBRARIES

The libraries in `lib/` of a bundle that no binary on Linux uses, as
`"<name>" => "<reason>"`. [`remove_unread_files!`](@ref) removes each file and
each link whose name starts with `<name>.so`, so no link points to nothing.
"""
const UNUSED_RUNTIME_LIBRARIES = [
    "libunwind-coredump" => "Julia unwinds only its own process, and this part unwinds a core file",
    "libunwind-ptrace" => "Julia unwinds only its own process, and this part unwinds another process",
    "libunwind-setjmp" => "no library of a bundle links it",
    "libunwind-x86_64" => "only the three parts above link it",
    "libunwind-generic" => "it is a link to libunwind-x86_64",
    "libuv" => "the runtime holds its own copy of libuv, and only LibUV_jll names this file"]

# The folders of an artifact that no run reads: headers, build data, manuals,
# documents and the logs of the build of the artifact.
const _UNREAD_ARTIFACT_FOLDERS = ["include", "lib/pkgconfig", "lib/cmake", "share/pkgconfig",
                                  "share/aclocal", "share/man", "man", "share/doc",
                                  "share/gtk-doc", "share/info", "logs"]

# A product of a JLL, as its wrapper declares it: the path of a library, a
# program or a file in the artifact folder.
const _PRODUCT_PATTERN = r"@init_(?:library|executable|file)_product\(\s*\w+\s*,\s*\"([^\"]+)\""

"""
    collect_product_paths(manifest; depots = DEPOT_PATH) -> (paths, unknown)

The paths in an artifact folder that a JLL of `manifest` names as a product: a
library, a program or a file, in each wrapper of the version that the manifest
holds. `unknown` are the JLLs whose source is in no depot, so their products are
not known. A stand-in and a JLL of the standard library have no artifact folder,
and they count as neither.
"""
function collect_product_paths(manifest::AbstractString; depots = DEPOT_PATH)
    paths = Set{String}()
    unknown = String[]
    isfile(manifest) || return (paths, ["the manifest $manifest"])
    for (name, entries) in TOML.parsefile(manifest)["deps"], entry in entries
        endswith(name, "_jll") && haskey(entry, "git-tree-sha1") || continue
        slug = Base.version_slug(Base.UUID(entry["uuid"]),
                                 Base.SHA1(hex2bytes(entry["git-tree-sha1"])))
        wrappers = [joinpath(depot, "packages", name, slug, "src", "wrappers") for depot in depots]
        index = findfirst(isdir, wrappers)
        if index === nothing
            push!(unknown, name)
            continue
        end
        for file in readdir(wrappers[index]; join = true)
            endswith(file, ".jl") || continue
            for found in eachmatch(_PRODUCT_PATTERN, read(file, String))
                push!(paths, found[1])
            end
        end
    end
    (paths, unknown)
end

"""
    remove_unread_files!(output, manifest; depots = DEPOT_PATH) -> (count, bytes)

Remove from the bundle `output` what no run reads, and answer the count of the
files and links that went and the bytes of the files.

- In each artifact folder: the folders in `_UNREAD_ARTIFACT_FOLDERS`, each `.a`
  and `.la` file, and each file in `bin/`. A file stays when a JLL of `manifest`
  names it as a product, see [`collect_product_paths`](@ref), and so does the
  target of a link that stays. When the products of a JLL are not known, `bin/`
  stays whole. All other files stay, among them `share/licenses/`, the locale
  data of X11 in `share/X11/` and the configuration of alsa in `share/alsa/`.
- On Linux, in `lib/` and `lib/julia/`: [`UNUSED_RUNTIME_LIBRARIES`](@ref).
  `libuv` stays when the manifest holds `LibUV_jll`.

[`build_executable`](@ref) calls it right after the compile, so it holds for each
kind of build. A second call finds nothing.
"""
function remove_unread_files!(output::AbstractString, manifest::AbstractString;
                              depots = DEPOT_PATH)
    products, unknown = collect_product_paths(manifest; depots)
    isempty(unknown) ||
        @info "remove_unread_files!: the products of $(join(unknown, ", ")) are not known, " *
              "so bin/ of each artifact folder stays"
    count = 0
    bytes = 0
    function remove!(path)
        count += 1
        islink(path) || (bytes += filesize(path))
        rm(path)
    end
    is_kept(relative) = any(relative == product || startswith(relative, product * "/")
                            for product in products)
    function is_unread(relative)
        any(startswith(relative, folder * "/") for folder in _UNREAD_ARTIFACT_FOLDERS) ||
            endswith(relative, ".a") || endswith(relative, ".la") ||
            (isempty(unknown) && startswith(relative, "bin/"))
    end
    artifacts = joinpath(output, "share", "julia", "artifacts")
    for artifact in (isdir(artifacts) ? readdir(artifacts; join = true) : String[])
        isdir(artifact) && !islink(artifact) || continue
        relative(file) = replace(relpath(file, artifact), '\\' => '/')
        files = [joinpath(root, file) for (root, _, names) in walkdir(artifact) for file in names]
        unread = Set(file for file in files if is_unread(relative(file)) && !is_kept(relative(file)))
        # A link that stays keeps the file that it points to.
        for file in files
            !(file in unread) && islink(file) && ispath(file) && delete!(unread, realpath(file))
        end
        foreach(remove!, sort!(collect(unread)))
        # The folders that the removal left empty, from the deepest up. A folder
        # that was empty before stays, because a library can read it by its path.
        emptied = Set{String}()
        for file in unread
            folder = dirname(file)
            while folder != artifact && startswith(folder, artifact)
                push!(emptied, folder)
                folder = dirname(folder)
            end
        end
        for folder in sort!(collect(emptied); by = length, rev = true)
            isdir(folder) && !islink(folder) && isempty(readdir(folder)) && rm(folder)
        end
    end
    if Sys.islinux()
        keeps_libuv = isfile(manifest) && haskey(TOML.parsefile(manifest)["deps"], "LibUV_jll")
        for folder in (joinpath(output, "lib"), joinpath(output, "lib", "julia"))
            isdir(folder) || continue
            for file in readdir(folder), (library, _) in UNUSED_RUNTIME_LIBRARIES
                library == "libuv" && keeps_libuv && continue
                startswith(file, library * ".so") && remove!(joinpath(folder, file))
            end
        end
    end
    (count, bytes)
end
