# The shell front end of the builder: the first argument names a binary, and the
# options go to its build function, through `run_build_command`.
#
#     julia --project=environment/build tool/build-binary.jl --help
#     julia --project=environment/build tool/build-binary.jl projectured
#     julia --project=environment/build tool/build-binary.jl projectured --distribution
#
# `bin/build_projectured` runs it for the application. A build uses much memory:
# do not start a build beside another build.

using Pkg

# The build environment must load `ProjecturedBuilder` before this script can use
# it. `resolve` also finds a dependency that a package of this repository added
# since the last build, which `instantiate` alone does not.
Pkg.resolve(; io = devnull)
Pkg.instantiate(; io = devnull)

using ProjecturedBuilder
exit(run_build_command(ARGS))
