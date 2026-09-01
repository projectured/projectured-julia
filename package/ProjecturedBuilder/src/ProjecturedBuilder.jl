# ═══════════════════════════════════════════════════════════════════════════
# executable/builder/ProjecturedBuilder.jl
#
# The configurable build front-end. A `BuildSpec` describes the editor to bake
# into the native executable (which domain, workbench or not, file-backed or not,
# which backend(s) compiled in and whether the choice is exposed at runtime).
# `build_executable` turns a spec into a binary:
#
#   1. generate `source/executable/AppConfig.jl` — the baked configuration plus the
#      `using` line(s) for exactly the compiled-in backends;
#   2. develop the local packages the app needs (the meta-package, the examples,
#      and each baked backend) so they resolve regardless of a stale Manifest;
#   3. compile with PackageCompiler.
#
# The interface is plain Julia functions callable from the REPL — no CLI parsing
# and no script to run:
#
#     using ProjecturedSdl, ProjecturedBuilder
#     build_executable(workbench_app(SdlBackend))
#
# Generation (step 1) is separated from compilation (steps 2-3) so it can be
# tested without the multi-minute `create_app`: call `build_executable(spec;
# compile=false)` (or `render_app_config(spec)` directly).
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedBuilder

import Pkg

include("../../../source/builder/Builder.jl")

end # module ProjecturedBuilder
