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
# `source/tool/builder/build_binary.jl` gives the same builds from a shell.
#
# `PackageRelease.jl` writes the other form a user can install: a copy of the
# packages in which each package folder holds everything it reads, for a
# registry. `build_projectured_package_release!(output)` writes the one of this
# repository.
# ═══════════════════════════════════════════════════════════════════════════

module ProjecturedBuilder

import Dates
import Pkg
import TOML
using SHA: sha256
using Preferences: set_preferences!

include("../../../source/tool/builder/BuildContext.jl")
include("../../../source/tool/builder/Preference.jl")
include("../../../source/tool/builder/Usage.jl")
include("../../../source/tool/builder/AppPackage.jl")
include("../../../source/tool/builder/Executable.jl")
include("../../../source/tool/builder/Distribution.jl")
include("../../../source/tool/builder/LicenceTexts.jl")
include("../../../source/tool/builder/SourceArchive.jl")
include("../../../source/tool/builder/PackageRelease.jl")
include("../../../source/tool/builder/ProjecturedProgram.jl")

export BuildContext, get_package_directory, get_package_uuid, make_projectured_build_context
export has_package_directory, collect_missing_sources
export Preference, make_baked_preference, make_exposed_preferences, write_preferences
export Usage, format_usage, format_version_line, collect_option_flags
export write_app_package, write_if_changed, StandIn, get_app_module_name, LOG_LEVEL_NAMES
export build_executable, compile_app!, resolve_app_project, build_info, get_smoke_flag
export bundle_fonts!, bundle_assets!, print_build_report!, INCREMENTAL_MARK, PORTABLE_CPU_TARGET
export build_distribution, collect_missing_libraries, GLIBC_LIBRARIES, get_staging_root,
       check_relocation, write_readme, report_distribution
export get_hidden_directories, make_hidden_command
export bundle_licence_texts!, SourceOffer, build_source_archive
export build_package_release!, collect_outside_paths
export PROJECTURED_BACKENDS, PROJECTURED_STAND_INS, PROJECTURED_OPTIONS,
       PROJECTURED_REQUIREMENTS, PROJECTURED_LICENCES, PROJECTURED_SOURCE,
       PROJECTURED_CREDITS, PROJECTURED_EXTRA_TEXTS, PROJECTURED_SOURCE_OFFERS,
       make_projectured_usage
export build_projectured_executable, build_projectured_distribution
export PROJECTURED_ASSETS, check_projectured_copy
export PROJECTURED_RELEASE_EXCLUSIONS, PROJECTURED_PACKAGE_ASSETS,
       PROJECTURED_JULIA_COMPAT, collect_projectured_release_packages,
       build_projectured_package_release!

end # module ProjecturedBuilder
