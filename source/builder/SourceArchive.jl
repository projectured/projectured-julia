# Fragment of `ProjecturedBuilder` — the source code that the licences of some
# libraries in a bundle ask to go with every copy.
#
# The LGPL and the GPL ask whoever gives a binary to others to give the
# corresponding source as well. A release does that in the simplest form: an
# archive of exactly the sources of the versions that the bundle carries, beside
# the binary archive in the same release. Each part is the tarball of its
# authors, checked against a SHA-256 that a person verified, and the patches that
# its build applies.

"""
    SourceOffer(name, version, jll, jll_version, url, sha256; recipe, patches, notes)

The source of one library that a bundle carries and whose licence asks for its
source: the tarball of its authors at `url`, whose SHA-256 is `sha256`; the build
recipe at `recipe`, at a fixed commit; the `patches` that build applies, as URLs;
and `notes`, what a reader of the archive needs to know. `jll` and `jll_version`
name the JLL whose build this source is, so that a build of a later version stops
instead of shipping the wrong source; `jll = "julia"` names Julia itself.
"""
struct SourceOffer
    name::String
    version::String
    jll::String
    jll_version::String
    url::String
    sha256::String
    recipe::String
    patches::Vector{String}
    notes::String
end

SourceOffer(name, version, jll, jll_version, url, sha256;
            recipe = "", patches = String[], notes = "") =
    SourceOffer(name, version, jll, jll_version, url, sha256, recipe, patches, notes)

"""
    build_source_archive(context; name, version, offers, output, cache, project,
                         stdlib) -> String

Write `<name>-<version>-sources.tar` into `output`, and answer its path. It
holds, for each of `offers`, the tarball of its authors, downloaded once into
`cache` and checked against its SHA-256, the patches that its build applies, and
a `README` that says what each part is, which version of which JLL it is the
source of, and where its build recipe is.

Before it downloads anything, it checks that each JLL carries the version that
its offer names: a standard-library JLL in `stdlib`, another in the manifest of
`project`, and Julia in `VERSION`. A different version stops the build.
"""
function build_source_archive(context::BuildContext; name::AbstractString,
                              version::AbstractString = context.version,
                              offers,
                              output::AbstractString = joinpath(context.root, "build"),
                              cache::AbstractString = joinpath(context.root, "build", "source-cache"),
                              project::AbstractString = joinpath(context.root, "build", "app", String(name)),
                              stdlib::AbstractString = Sys.STDLIB)
    _check_source_offers(offers, project, stdlib)
    directory = "$(name)-$(version)-sources"
    root = mktempdir(get_staging_root())
    try
        staged = joinpath(root, directory)
        mkpath(staged)
        mkpath(cache)
        lines = ["The source code of the libraries under the LGPL and the GPL that",
                 "$name $version carries, for exactly the versions it carries.",
                 "",
                 "Each part is the tarball of its authors, checked against the SHA-256 below,",
                 "and the patches that its build applies. Each JLL is built by the recipe named",
                 "below, from BinaryBuilder's Yggdrasil.",
                 ""]
        for offer in offers
            tarball = joinpath(cache, offer.sha256 * "-" * basename(offer.url))
            isfile(tarball) || _fetch_licence_file(offer.url, tarball)
            digest = bytes2hex(open(sha256, tarball))
            digest == offer.sha256 ||
                error("build_source_archive: $(offer.url) has SHA-256 $digest, not " *
                      "$(offer.sha256); the source of $(offer.name) must be checked again")
            folder = joinpath(staged, _get_source_folder_name(offer))
            ispath(folder) &&
                error("build_source_archive: two offers share the folder $(basename(folder))")
            mkpath(folder)
            cp(tarball, joinpath(folder, basename(offer.url)))
            for patch in offer.patches
                mkpath(joinpath(folder, "patches"))
                _fetch_licence_file(patch, joinpath(folder, "patches", basename(patch)))
            end
            append!(lines, ["$(offer.name) $(offer.version)",
                            "  folder:  $(basename(folder))/",
                            "  of:      $(offer.jll) $(offer.jll_version)",
                            "  from:    $(offer.url)",
                            "  SHA-256: $(offer.sha256)"])
            isempty(offer.recipe) || push!(lines, "  recipe:  $(offer.recipe)")
            isempty(offer.patches) || push!(lines, "  patches: " * join(basename.(offer.patches), ", "))
            isempty(offer.notes) || append!(lines, ["  " * line for line in split(offer.notes, "\n")])
            push!(lines, "")
        end
        write(joinpath(staged, "README"), join(lines, "\n") * "\n")
        mkpath(output)
        archive = joinpath(abspath(output), directory * ".tar")
        @info "Writing the source archive" archive
        run(`tar -C $root -cf $archive $directory`)
        archive
    finally
        rm(root; recursive = true, force = true)
    end
end

# A folder name for an offer: its name up to the first space or parenthesis,
# and its version up to the first space.
_get_source_folder_name(offer::SourceOffer) =
    first(split(offer.name, r"[ (]")) * "-" * first(split(offer.version, " "))

# Each JLL carries the version that its offer names.
function _check_source_offers(offers, project::AbstractString, stdlib::AbstractString)
    manifest = isfile(joinpath(project, "Manifest.toml")) ?
        get(TOML.parsefile(joinpath(project, "Manifest.toml")), "deps", Dict{String,Any}()) :
        Dict{String,Any}()
    for offer in offers
        carried = if offer.jll == "julia"
            string(VERSION)
        elseif isfile(joinpath(stdlib, offer.jll, "Project.toml"))
            TOML.parsefile(joinpath(stdlib, offer.jll, "Project.toml"))["version"]
        elseif haskey(manifest, offer.jll)
            get(manifest[offer.jll][1], "version", "")
        else
            error("build_source_archive: the binary carries no $(offer.jll), which the offer " *
                  "of $(offer.name) names")
        end
        carried == offer.jll_version ||
            error("build_source_archive: the binary carries $(offer.jll) $carried, and the " *
                  "offer of $(offer.name) is the source of $(offer.jll_version). Find the " *
                  "source of $carried, and change the offer.")
    end
    nothing
end
