# build.jl — compile adaptagrams_shim.cpp against an installed/built Adaptagrams
# (libcola + libavoid + libvpsc) into deps/libadaptagrams_shim.<ext>.
#
# Run automatically by `Pkg.build("ProjecturedAdaptagrams")`, or by hand:
#   julia package/ProjecturedAdaptagrams/deps/build.jl
#
# The module loads the shim from this fixed path (no generated deps.jl); whether
# it has been built is a runtime check (ProjecturedAdaptagrams.isavailable()), so
# building the .so is picked up without a stale precompile cache.
#
# Locating Adaptagrams, in order of preference:
#   1. pkg-config (libcola libavoid libvpsc) — works after `make install` when
#      the .pc files are on PKG_CONFIG_PATH.
#   2. $ADAPTAGRAMS_DIR — the `cola/` directory of an Adaptagrams checkout
#      (contains libavoid/ libcola/ libvpsc/). Defaults to ~/workspace/adaptagrams/cola.
#
# This script never throws: if Adaptagrams cannot be found or the compile fails,
# it removes any stale shim and warns; AdaptagramsLayout then falls back to a
# pure-Julia layout engine at call time and warns once, rather than erroring.
# Re-run the build after installing the native library.

const HERE = @__DIR__
const SHIM_SRC = joinpath(HERE, "adaptagrams_shim.cpp")
const SHIM_EXT = Sys.iswindows() ? "dll" : Sys.isapple() ? "dylib" : "so"  # == Libdl.dlext
const SHIM_LIB = joinpath(HERE, "libadaptagrams_shim." * SHIM_EXT)

cxx() = get(ENV, "CXX", Sys.which("g++") !== nothing ? "g++" : "c++")

"Try pkg-config; return (cflags::Vector, libs::Vector) or nothing."
function try_pkgconfig()
    pc = Sys.which("pkg-config")
    pc === nothing && return nothing
    pkgs = ["libcola", "libavoid", "libvpsc"]
    try
        success(`$pc --exists $pkgs`) || return nothing
        cflags = split(read(`$pc --cflags $pkgs`, String))
        libs = split(read(`$pc --libs $pkgs`, String))
        @info "Found Adaptagrams via pkg-config" pkgs
        return (collect(String, cflags), collect(String, libs))
    catch
        return nothing
    end
end

"Fall back to a source/checkout dir; return (cflags, libs) or nothing."
function try_source_dir()
    dir = get(ENV, "ADAPTAGRAMS_DIR",
              joinpath(homedir(), "workspace", "adaptagrams", "cola"))
    isdir(dir) || (@warn "ADAPTAGRAMS_DIR not a directory" dir; return nothing)
    # Include root: the dir that contains libavoid/, libcola/, libvpsc/.
    inc = dir
    isfile(joinpath(inc, "libavoid", "libavoid.h")) ||
        (@warn "No libavoid/libavoid.h under include root — set ADAPTAGRAMS_DIR to the cola/ dir" inc; return nothing)

    # Library dirs: in-tree libtool builds land in <lib>/.libs; an install lands
    # in <prefix>/lib. Probe the common spots and keep the ones that exist.
    candidates = String[]
    for sub in ("libavoid", "libcola", "libvpsc")
        push!(candidates, joinpath(dir, sub, ".libs"))
        push!(candidates, joinpath(dir, sub))
    end
    push!(candidates, joinpath(dirname(dir), "lib"))   # ../lib next to cola/
    push!(candidates, "/usr/local/lib")
    libdirs = unique(filter(isdir, candidates))
    isempty(libdirs) && (@warn "No Adaptagrams library dirs found; build it first" dir; return nothing)

    cflags = ["-I$inc"]
    libs = String[]
    for d in libdirs
        push!(libs, "-L$d")
        push!(libs, "-Wl,-rpath,$d")   # so the shim finds the .so at runtime
    end
    # cola before vpsc (cola depends on vpsc).
    append!(libs, ["-lcola", "-lvpsc", "-lavoid"])
    @info "Found Adaptagrams source tree" inc libdirs
    return (cflags, libs)
end

"Add -rpath for each -L in a pkg-config libs list (runtime resolution)."
function with_rpaths(libs::Vector{String})
    out = String[]
    for l in libs
        push!(out, l)
        startswith(l, "-L") && push!(out, "-Wl,-rpath," * l[3:end])
    end
    out
end

function main()
    isfile(SHIM_SRC) || error("missing $SHIM_SRC")

    found = try_pkgconfig()
    if found === nothing
        found = try_source_dir()
    end
    if found === nothing
        @warn """
        Adaptagrams (libcola/libavoid/libvpsc) not found — the AdaptagramsLayout
        shim was NOT built. Install/build Adaptagrams, then re-run
        `Pkg.build("ProjecturedAdaptagrams")`. Point ADAPTAGRAMS_DIR at the cola/
        directory of a checkout, or put the .pc files on PKG_CONFIG_PATH.
        GridEmbedding remains available in the meantime.
        """
        rm(SHIM_LIB; force = true)   # don't leave a stale shim that looks available
        return
    end

    cflags, libs = found
    libs = with_rpaths(libs)
    cmd = `$(cxx()) -std=c++11 -O2 -fPIC -shared $SHIM_SRC $cflags -o $SHIM_LIB $libs`
    @info "Compiling adaptagrams shim" cmd
    try
        run(cmd)
        @info "Built shim" SHIM_LIB
    catch e
        @warn """
        Compiling adaptagrams_shim.cpp failed ($e). The most likely cause is an
        Adaptagrams API mismatch — see the "VERIFY" notes in adaptagrams_shim.cpp
        and adjust to the installed headers. GridEmbedding remains usable.
        """
        rm(SHIM_LIB; force = true)
    end
end

main()
