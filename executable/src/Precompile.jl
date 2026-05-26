#!/usr/bin/env julia

"""
Precompilation script for PackageCompiler.

This file is used to precompile functions and warm up the Julia runtime
before creating the native executable, which improves startup time.
"""

# Precompile the main program by calling its functions
include("ProjecturedExecutable.jl")

# Import the functions into Main scope
using .ProjecturedExecutable

# Warm up the functions with typical usage patterns
cmd_hello("TestUser")
cmd_info()
cmd_version()
print_help()
cmd_workbench_example()
