# Fragment of `PrecompileModule` — what a package runs when it precompiles: the
# macro of its entry file, the compile of its recorded calls, the run of its
# workload, and the choice of what a failure does.

"""
    PRECOMPILE_STALE_SHARE

The share of the recorded calls of a package that may no longer resolve before
the precompilation of the package fails. A call no longer resolves when it names
a type or a method that the code does not have now.
"""
const PRECOMPILE_STALE_SHARE = 0.1

"""
    @compile_ahead
    @compile_ahead workload

Compile the package ahead of time, as its preference `precompile_calls` says.
The entry file of a package calls it once, at its end:

```julia
using ProjecturedPrecompile: @compile_ahead
@compile_ahead begin
    run_natural_rows_workload(JsonModule)
    run_file_workload(JsonModule.JsonFile)
end
```

The workload drives the package as a person does, and it throws an error when a
step fails. The call defines two names in the package:

- `run_package_workload()`, which runs the workload. The recording calls it.
- `PRECOMPILE_FAILURE`, the failure of the precompilation, or `nothing`.

At `"recorded"` the package compiles each file of its folder `precompile/`. At
`"live"` it runs the workload. At `"none"` it does nothing. The preference
`precompile_failure` says what a failure does. Outside a build the call does
nothing.
"""
macro compile_ahead(workload = nothing)
    folder = dirname(dirname(String(__source__.file)))
    esc(Expr(:toplevel,
             :(function run_package_workload()
                   $workload
                   nothing
               end),
             :(const PRECOMPILE_FAILURE =
                   $compile_package_ahead($__module__, run_package_workload; folder = $folder))))
end

"""
    compile_package_ahead(package, workload; folder) -> Union{String,Nothing}

What [`@compile_ahead`](@ref) runs while `package` precompiles: read its two
preferences, then compile its recorded calls from `folder`, run `workload`, or do
nothing, with the newly compiled code kept in the image. Answers the failure as
the preference `precompile_failure` keeps it, or `nothing`.
"""
function compile_package_ahead(package::Module, workload::Function; folder::AbstractString)
    PrecompileTools.is_generating_output() || return nothing
    calls = get_precompile_calls(package)
    choice = get_precompile_failure(package)
    calls == "none" && return nothing
    failure = _run_with_new_code_kept() do
        calls == "recorded" ? compile_recorded_calls(package, folder) :
                              _run_package_workload(package, workload)
    end
    _keep_precompile_failure(failure, choice)
end

# Run `body` so that the code it compiles stays in the image of the package that
# precompiles, the code of other packages included, as `@compile_workload` does.
function _run_with_new_code_kept(body::Function)
    PrecompileTools.tag_newly_inferred_enable()
    try
        Base.invokelatest(body)
    finally
        PrecompileTools.tag_newly_inferred_disable()
    end
end

function _run_package_workload(package::Module, workload::Function)
    try
        Base.invokelatest(workload)
        nothing
    catch exception
        string("The workload of ", nameof(package), " failed: ", sprint(showerror, exception))
    end
end

function _keep_precompile_failure(failure::Union{String,Nothing}, choice::String)
    failure === nothing && return nothing
    choice == "error" && error(failure)
    choice == "silent" && return nothing
    @warn failure
    failure
end

"""
    compile_recorded_calls(package, folder) -> Union{String,Nothing}

Compile each call of each file `precompile/*.txt` in `folder`, the folder of
`package`. Answers a failure when more than
[`PRECOMPILE_STALE_SHARE`](@ref) of the calls no longer resolve, or `nothing`.

The folder and each file are dependencies of the image, so a new recording
builds the image again. A package with no folder depends on the list of its own
folder, so that a first recording builds it again too.
"""
function compile_recorded_calls(package::Module, folder::AbstractString)
    lists = joinpath(folder, "precompile")
    if !isdir(lists)
        include_dependency(folder)
        return nothing
    end
    include_dependency(lists)
    calls = String[]
    for file in sort!(readdir(lists; join = true))
        endswith(file, ".txt") || continue
        include_dependency(file)
        append!(calls, read_recorded_calls(file))
    end
    isempty(calls) && return nothing
    modules = Dict{Symbol,Module}(nameof(loaded) => loaded for loaded in values(Base.loaded_modules))
    modules[nameof(package)] = package
    skipped = count(call -> !_compile_recorded_call(package, modules, call), calls)
    skipped / length(calls) > PRECOMPILE_STALE_SHARE || return nothing
    string(skipped, " of the ", length(calls), " recorded calls of ", nameof(package),
           " no longer resolve. Record them again with `record_package_calls!(\"",
           nameof(package), "\")`.")
end

# A recorded call names each type by the module that defines it. The first name
# of each dotted name becomes the module object of that name, the package itself
# included, which is not in `Base.loaded_modules` while it precompiles. The
# expression is then evaluated in the package, and it defines no name there.
function _compile_recorded_call(package::Module, modules::Dict{Symbol,Module},
                                call::AbstractString)
    try
        precompile(Core.eval(package, _insert_call_modules(Meta.parse(call), modules)))
    catch
        false
    end
end

function _insert_call_modules(x, modules::Dict{Symbol,Module})
    x isa Expr || return x
    if x.head === :.
        root = x.args[1]
        first = root isa Symbol ? get(modules, root, root) : _insert_call_modules(root, modules)
        return Expr(:., first, x.args[2:end]...)
    end
    Expr(x.head, (_insert_call_modules(argument, modules) for argument in x.args)...)
end

"""
    read_recorded_calls(path) -> Vector{String}

The calls of the recorded list `path`: each line that is not empty and is not a
comment.
"""
function read_recorded_calls(path::AbstractString)
    calls = String[]
    for line in eachline(path)
        line = strip(line)
        (isempty(line) || startswith(line, '#')) || push!(calls, String(line))
    end
    calls
end
