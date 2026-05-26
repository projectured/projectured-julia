# Projectured Native Executable

This directory contains a Julia program that can be compiled to a native binary executable using PackageCompiler.jl.

## Overview

The executable is a simple command-line tool demonstrating Julia's native compilation capabilities. It provides basic commands for greetings, system information, and version display.

## Building the Executable

### Prerequisites

- Julia 1.6 or later
- PackageCompiler.jl (automatically installed by the build script)

### Build Instructions

1. Navigate to the executable directory:
   ```bash
   cd /home/levy/workspace/predj/executable
   ```

2. Run the build script:
   ```bash
   julia Build.jl
   ```

   This will:
   - Install dependencies (PackageCompiler.jl)
   - Compile the program to a native binary
   - Create the executable in `build/bin/main`

3. Run the executable:
   ```bash
   ./build/bin/main help
   ```

## Usage

The executable supports the following commands:

```bash
./build/bin/main hello [name]    # Print a greeting (default: "World")
./build/bin/main info            # Print system information
./build/bin/main version         # Print version information
./build/bin/main help            # Show help message
```

### Examples

```bash
# Greet the world
./build/bin/main hello

# Greet a specific person
./build/bin/main hello Alice

# Show system information
./build/bin/main info

# Show version
./build/bin/main version
```

## Project Structure

```
executable/
├── Project.toml          # Package configuration with dependencies
├── Build.jl              # Build script for compiling the executable
├── README.md             # This file
├── src/
│   ├── Main.jl           # Main program entry point
│   └── Precompile.jl     # Precompilation script for faster builds
└── build/                # Generated build output (created during build)
    └── bin/
        └── main          # Compiled native executable
```

## Customization

To modify the executable behavior:

1. Edit `src/Main.jl` to change the program logic
2. Edit `src/Precompile.jl` to add functions for precompilation
3. Rebuild using `julia Build.jl`

## Notes

- The first build may take several minutes as PackageCompiler compiles the Julia runtime
- Subsequent builds are faster if using incremental compilation
- The compiled binary is self-contained and can be distributed without Julia installed
