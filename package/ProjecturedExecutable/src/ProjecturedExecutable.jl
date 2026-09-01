"""
ProjecturedExecutable

The compiled-app entry module. It is **generic over a baked configuration**: the
editor it runs (domain, workbench, file-backed) and the backend(s) compiled in are
fixed at build time by `build_executable` (`ProjecturedBuilder`), which writes the
`AppConfig.jl` this module includes. `julia_main` then parses the runtime arguments
(a file to edit, and `--backend` when the build exposed it) and opens the editor.
"""
module ProjecturedExecutable

using ProjecturedExample                       # run_file_editor, build_file_editor, …
using Projectured: write_image


include("../../../source/executable/Executable.jl")

end # module
