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
#     build_executable(make_workbench_app(SdlBackend))
#
# Generation (step 1) is separated from compilation (steps 2-3) so it can be
# tested without the multi-minute `create_app`: call `build_executable(spec;
# compile=false)` (or `render_app_config(spec)` directly).
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedBuilder

import Dates
import Pkg
import TOML
using SHA: sha256
using Preferences: set_preferences!

include("../../../source/builder/BuildContext.jl")
include("../../../source/builder/Preference.jl")
include("../../../source/builder/Usage.jl")
include("../../../source/builder/AppPackage.jl")
include("../../../source/builder/Executable.jl")
include("../../../source/builder/Distribution.jl")
include("../../../source/builder/Builder.jl")

export BuildContext, get_package_directory, get_package_uuid, make_projectured_build_context
export Preference, make_baked_preference, make_exposed_preferences, write_preferences
export Usage, format_usage, format_version_line, collect_option_flags
export write_app_package, write_if_changed, LOG_LEVEL_NAMES
export build_executable, compile_app!, resolve_app_project, build_info, get_smoke_flag
export bundle_fonts!, bundle_assets!, print_build_report!, INCREMENTAL_MARK, PORTABLE_CPU_TARGET
export build_distribution, get_staging_root, check_relocation, write_readme, report_distribution

end # module ProjecturedBuilder
