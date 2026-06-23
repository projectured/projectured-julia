"""
ProjecturedExecutable

A simple command-line tool demonstrating Julia native compilation.
This module provides basic commands for greetings, system information, and version display.
"""
module ProjecturedExecutable

using ProjecturedExample
# The compiled GUI binary bakes in the SDL backend (no weakdep auto-activation in
# the standalone executable): `using ProjecturedSdl` registers make_backend(:sdl).
using ProjecturedSdl

export print_banner, print_help, cmd_hello, cmd_info, cmd_version, main, cmd_workbench_example

function print_banner()
    println("=" ^ 60)
    println("  Projectured Native Executable")
    println("  Compiled with PackageCompiler.jl")
    println("=" ^ 60)
end

function print_help()
    print_banner()
    println()
    println("Usage: projectured_executable [command] [options]")
    println()
    println("Commands:")
    println("  hello [name]    - Print a greeting")
    println("  info            - Print system information")
    println("  version         - Print version information")
    println("  help            - Show this help message")
    println()
    println("If no command is given, the workbench_example will run by default.")
    println()
end

function cmd_hello(name::String = "World")
    print_banner()
    println()
    println("Hello, $(name)! 👋")
    println("Welcome to Projectured native executable.")
    println()
end

function cmd_info()
    print_banner()
    println()
    println("System Information:")
    println("  Julia Version: $(VERSION)")
    println("  OS: $(Sys.KERNEL)")
    println("  Architecture: $(Sys.ARCH)")
    println("  CPU Threads: $(Sys.CPU_THREADS)")
    println("  Word Size: $(Sys.WORD_SIZE)")
    println()
end

function cmd_version()
    println("Projectured Executable v0.1.0")
    println("Built with Julia $(VERSION)")
end

function cmd_workbench_example()
    println("Running workbench_example...")
    run_example("workbench")
end

function main()
    if length(ARGS) == 0
        cmd_workbench_example()
        return 0
    end

    command = ARGS[1]

    if command == "info"
        cmd_info()
    elseif command == "version"
        cmd_version()
    elseif command == "help" || command == "--help" || command == "-h"
        print_help()
    else
        println("Unknown command: $(command)")
        println()
        print_help()
        return 1
    end

    return 0
end

# Entry point for PackageCompiler executable
function julia_main()::Cint
    julia_main(ARGS)
end

function julia_main(args::Vector{String})::Cint
    if length(args) == 0
        cmd_workbench_example()
        return 0
    end

    command = args[1]

    if command == "hello"
        name = length(args) >= 2 ? args[2] : "World"
        cmd_hello(name)
    elseif command == "info"
        cmd_info()
    elseif command == "version"
        cmd_version()
    elseif command == "help" || command == "--help" || command == "-h"
        print_help()
    else
        println("Unknown command: $(command)")
        println()
        print_help()
        return 1
    end

    return 0
end

# Entry point for the executable
if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end

end # module
