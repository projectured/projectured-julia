"""
    BuilderModule

The builder of native binaries. The core makes one binary from a list of
packages and the body of `julia_main`: it writes a package for the binary under
`build/app/<name>/`, compiles it with PackageCompiler into `build/<name>/`, and
can make a distribution archive from that bundle. The core knows no program of
this repository.

`ProjecturedProgram.jl` names the binaries of this repository:

    using ProjecturedBuilder
    build_projectured_executable()                    # build/projectured/
    build_projectured_executable(compile = false)     # the package only
    build_projectured_distribution()                  # build/projectured-*.tar.gz

`BuildCommand.jl` is the same builds from a shell, which `tool/build-binary.jl`
runs. `PackageRelease.jl` writes the other form a user can install: a copy of the
packages in which each package folder holds everything it reads, for a registry.
`build_projectured_package_release!(output)` writes the one of this repository.
"""
module BuilderModule

import Dates
import Pkg
import TOML
using SHA: sha256
using Preferences: set_preferences!

export BuildContext, get_package_directory, has_package_directory,
       collect_missing_sources, get_package_uuid, make_projectured_build_context
export Preference, make_baked_preference, make_exposed_preferences, write_preferences
export Usage, format_usage, format_version_line, collect_option_flags
export get_app_module_name, LOG_LEVEL_NAMES, write_app_package, StandIn,
       write_if_changed
export INCREMENTAL_MARK, PORTABLE_CPU_TARGET, resolve_app_project, build_executable,
       compile_app!, get_smoke_flag, build_info, bundle_fonts!, bundle_assets!,
       print_build_report!
export build_distribution, GLIBC_LIBRARIES, collect_missing_libraries, get_staging_root,
       get_hidden_directories, make_hidden_command, check_relocation, write_readme,
       report_distribution
export bundle_licence_texts!
export SourceOffer, build_source_archive
export build_package_release!, collect_outside_paths
export PROJECTURED_BACKENDS, PROJECTURED_STAND_INS, PROJECTURED_SOURCE_OFFERS,
       PROJECTURED_OPTIONS, PROJECTURED_REQUIREMENTS, PROJECTURED_LICENCES,
       PROJECTURED_CREDITS, PROJECTURED_EXTRA_TEXTS, PROJECTURED_DATA_TEXTS,
       PROJECTURED_SOURCE,
       PROJECTURED_ASSETS, make_projectured_usage, PROJECTURED_APPLICATION_IMPORTS,
       build_projectured_executable,
       build_projectured_distribution, PROJECTURED_RELEASE_EXCLUSIONS,
       PROJECTURED_PACKAGE_ASSETS, PROJECTURED_JULIA_COMPAT,
       PROJECTURED_CI_JULIA_VERSIONS, PROJECTURED_REGISTRY_URL, PROJECTURED_RELEASE_URL,
       AUTOINTEGRATION_URL, AGENT_CLIENT_PROTOCOL_URL, AUTOPRECOMPILE_URL, GENERAL_REGISTRY_URL,
       MOZILLA_PUBLIC_LICENSE_URL,
       PROJECTURED_JOINED_PACKAGE_URLS, PROJECTURED_PACKAGE_READMES,
       collect_projectured_release_packages, build_projectured_package_release!,
       check_projectured_copy
export get_fixed_build_binary, get_build_invocation, BUILD_BINARIES, BUILD_OPTIONS,
       format_build_usage, parse_build_arguments, run_build_command

include("BuildContext.jl")
include("Preference.jl")
include("Usage.jl")
include("AppPackage.jl")
include("Executable.jl")
include("Distribution.jl")
include("LicenceTexts.jl")
include("SourceArchive.jl")
include("PackageRelease.jl")
include("ProjecturedProgram.jl")
include("BuildCommand.jl")

end # module BuilderModule
