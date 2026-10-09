"""
    ReplModule

The leaf that a person loads to work: what this build compiled ahead of time,
the recorded precompile statements that it replays, and the recorder that writes
them again. A package image is built with exactly the dependencies of its
package present, so compiled code is only safe in a package that nothing
depends on and nothing loads after; this is that package's code.
"""
module ReplModule

using PrecompileTools: @setup_workload, @compile_workload
using Preferences: @load_preference, set_preferences!
using ProjecturedExample
using TOML

"""
    StatementScope

Where a recorded statement is resolved. It is a module of *this* package because
`replay_precompile_statements` binds every loaded module into it by name, and
binding names into a dependency's module while this one precompiles would be one
build writing into another package's image.
"""
module StatementScope end

export PRECOMPILE_RECORDINGS, split_precompile_statements,
       write_precompile_statement_files, PRECOMPILE_STATEMENTS
export WORKLOAD, set_workload!, get_workload, replay_precompile_statements,
       record_precompile_statements

include("ReplStatementFiles.jl")
include("ReplWorkload.jl")

end # module ReplModule
