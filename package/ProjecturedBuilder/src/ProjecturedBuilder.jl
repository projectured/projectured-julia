# ═══════════════════════════════════════════════════════════════════════════
# The builder of native binaries.
#
# The core makes one binary from a list of packages and the body of
# `julia_main`. It writes a package for the binary under
# `build/app/<name>/`, compiles it with PackageCompiler into
# `build/<name>/`, and can make a distribution archive from that bundle. The
# core knows no program of this repository.
#
# `ProjecturedProgram.jl` names the binaries of this repository:
#
#     using ProjecturedBuilder
#     build_projectured_executable()                    # build/projectured/
#     build_projectured_executable(compile = false)     # the package only
#     build_projectured_distribution()                  # build/projectured-*.tar.gz
#
# `source/builder/build_binary.jl` gives the same builds from a shell.
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
include("../../../source/builder/ProjecturedProgram.jl")

export BuildContext, get_package_directory, get_package_uuid, make_projectured_build_context
export Preference, make_baked_preference, make_exposed_preferences, write_preferences
export Usage, format_usage, format_version_line, collect_option_flags
export write_app_package, write_if_changed, LOG_LEVEL_NAMES
export build_executable, compile_app!, resolve_app_project, build_info, get_smoke_flag
export bundle_fonts!, bundle_assets!, print_build_report!, INCREMENTAL_MARK, PORTABLE_CPU_TARGET
export build_distribution, get_staging_root, check_relocation, write_readme, report_distribution
export PROJECTURED_BACKENDS, PROJECTURED_OPTIONS, PROJECTURED_REQUIREMENTS, make_projectured_usage
export build_projectured_executable, build_projectured_distribution

end # module ProjecturedBuilder
