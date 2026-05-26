#!/usr/bin/env julia

"""
Build script for compiling Projectured executable to a native binary.

This script uses PackageCompiler.jl to create a standalone executable
from the Main.jl program.

Usage:
    julia Build.jl

All output is written to build.log in the executable directory.
"""

using Pkg

# Redirect all stdout and stderr to a log file
const LOG_FILE = @__DIR__() * "/build.log"
const LOG_IO = open(LOG_FILE, "w")

redirect_stdout(LOG_IO)
redirect_stderr(LOG_IO)

# Activate the executable project environment
Pkg.activate(@__DIR__)

# Add local packages as developable dependencies FIRST
println("Adding local packages...")
Pkg.develop(PackageSpec(path = "../program"))
Pkg.develop(PackageSpec(path = "../example"))

# Use development version of FixedPointNumbers to fix Julia 1.12 compatibility
println("Adding FixedPointNumbers from specific commit (fixes Julia 1.12 precompile issue)...")
Pkg.add(url="https://github.com/JuliaMath/FixedPointNumbers.jl", rev="59ee94b93f2f1ee75544ef44187fc0e440cd8015")

# Install dependencies if not already installed
println("Installing dependencies...")
if isfile(@__DIR__() * "/Manifest.toml")
    Pkg.instantiate()
else
    Pkg.resolve()
end

# Add PackageCompiler if not already present
if !haskey(Pkg.project().dependencies, "PackageCompiler")
    println("Adding PackageCompiler...")
    Pkg.add("PackageCompiler")
end

# Import PackageCompiler
using PackageCompiler

println("Building native executable...")
println("This may take several minutes on first build...")

# Create the executable from the current directory (which contains Project.toml)
create_app(
    @__DIR__(),
    @__DIR__() * "/build",
    precompile_execution_file = @__DIR__() * "/src/Precompile.jl",
    force = true,
)

println("\n✅ Build complete!")
println("Executable location: $(@__DIR__())/build/bin/main")
println("\nTo run the executable:")
println("  $(@__DIR__())/build/bin/main help")

# Close the log file
close(LOG_IO)
