#!/usr/bin/env julia

"""
Precompilation workload for PackageCompiler.

Config-agnostic: it warms whatever editor the build is configured for, via
`ProjecturedExecutable.precompile_warmup()` (which reads the baked `AppConfig`).
So this one file serves every `build_executable` spec — no per-build generation.
"""

include(joinpath(@__DIR__, "..", "..", "package", "ProjecturedExecutable",
                 "src", "ProjecturedExecutable.jl"))
using .ProjecturedExecutable

ProjecturedExecutable.precompile_warmup()
