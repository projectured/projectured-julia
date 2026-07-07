#!/usr/bin/env julia

"""
Build script for compiling a Projectured editor to a native binary.

The actual logic lives in `Builder.jl` (`build_executable`); this script is just a
thin entry point that builds the **default** configuration — a JSON file editor
with the SDL backend baked in. To build a different editor, call `build_executable`
directly from the REPL, e.g.:

    julia --project=package/executable/main -e '
        include("package/executable/Builder.jl");
        using .ProjecturedBuilder;
        build_executable(; app_name="json-editor", domain=:json, backends=[:sdl])'

All output is written to build.log in the executable directory.

Usage:
    julia Build.jl
"""

# Redirect all stdout and stderr to a log file (the build is long and noisy).
const LOG_IO = open(joinpath(@__DIR__, "build.log"), "w")
redirect_stdout(LOG_IO)
redirect_stderr(LOG_IO)

include(joinpath(@__DIR__, "Builder.jl"))
using .ProjecturedBuilder

# Default spec: JSON file editor, SDL baked in (BuildSpec()'s defaults).
build_executable()

close(LOG_IO)
