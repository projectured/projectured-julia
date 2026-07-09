#!/usr/bin/env julia

"""
Build script for compiling a Projectured editor to a native binary.

The actual logic lives in `Builder.jl` (`build_executable`); this script is just a
thin entry point that builds the **default** configuration — a JSON file editor
with the SDL backend baked in. To build a different editor, call `build_executable`
directly from the REPL, e.g.:

    julia --project=package/executable/main -e '
        using ProjecturedSdl;
        include("package/executable/Builder.jl");
        using .ProjecturedBuilder;
        build_executable(; app_name="json-editor", domain=:json, backends=[SdlBackend])'

All output is written to build.log in the executable directory.

Usage:
    julia Build.jl
"""

# Redirect all stdout and stderr to a log file (the build is long and noisy).
const LOG_IO = open(joinpath(@__DIR__, "build.log"), "w")
redirect_stdout(LOG_IO)
redirect_stderr(LOG_IO)

import Pkg
# Activate + instantiate the app env first so `ProjecturedSdl` resolves and its
# `SdlBackend` type can be named below (the builder derives the friendly `sdl`
# runtime flag from the type). `build_executable` re-activates and develops the
# same env; doing it here as well is idempotent.
Pkg.activate(joinpath(@__DIR__, "main"))
Pkg.instantiate()
using ProjecturedSdl

include(joinpath(@__DIR__, "Builder.jl"))
using .ProjecturedBuilder

# Default spec: JSON file editor, SDL backend baked in.
build_executable(; backends = [SdlBackend])

close(LOG_IO)
