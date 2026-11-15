"""
    PrecompileModule

The one mechanism that compiles the packages of this repository ahead of time,
and the packages of each repository that builds on them. The entry file of a
package calls [`@compile_ahead`](@ref) once. When the package precompiles, that
call reads the two preferences of the package, `precompile_calls` and
`precompile_failure`, and then compiles the recorded calls of the package, runs
its workload, or does nothing. The recording runs the workload of a package or
of an application in a new process and writes the calls that it compiled into
the folder `precompile/` of the package that owns them. The measurements that
each repository takes the same way, the images of its packages and the build of
a binary, are here too.

`documentation/design/compile-ahead.md` holds the design: the requirements, the
decisions, and why there is one mechanism.
"""
module PrecompileModule

import PrecompileTools
using Preferences: load_preference
using TOML

export @compile_ahead,
       PRECOMPILE_CALLS_VALUES, PRECOMPILE_FAILURE_VALUES, PRECOMPILE_STALE_SHARE,
       get_precompile_calls, get_precompile_failure,
       compile_recorded_calls, read_recorded_calls, report_precompile_failure!,
       collect_traced_calls, write_recorded_calls!, collect_package_closures,
       is_compiling_package, has_package_workload, collect_compiling_packages,
       find_call_owner, compute_call_owners,
       find_repository_root, trace_package_calls,
       record_package_calls!, record_repository_calls!, record_application_calls!,
       compare_display_recordings,
       measure_folder_bytes, print_measurement_row, measure_package_images,
       measure_process_median, measure_binary_build

include("PrecompilePreferences.jl")
include("PrecompilePackage.jl")
include("PrecompileFailure.jl")
include("PrecompileRecording.jl")
include("PrecompileMeasurement.jl")

end # module PrecompileModule
