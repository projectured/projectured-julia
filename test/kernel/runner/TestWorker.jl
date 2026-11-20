# ============================================================================
# The worker process of the runner of the suites.
#
# `tool/run-tests.jl` starts a worker with `run_test_worker()`. The worker loads
# the test packages, lists the parts of a suite, and runs one part at a time,
# as the supervisor asks. The supervisor stops a worker that takes too long or
# uses too much memory, and starts a new one for the next part, so a part that
# hangs or crashes loses no result of another part.
# ============================================================================

"""
    WORKER_LINE_PREFIX

The start of each line that a worker writes for the supervisor. The output of
the tests goes to the same stream, so the supervisor reads only these lines.
"""
const WORKER_LINE_PREFIX = "@@test-worker@@\t"

"""
    HeldTestSet(description)

A testset that keeps the results of its children and gives them to no parent,
and prints no summary. A worker runs each part inside one, so a part that fails
ends nothing but its own testset. A test of the runner uses one to run a suite
that fails on purpose.
"""
mutable struct HeldTestSet <: Test.AbstractTestSet
    description::String
    results::Vector{Any}
end

HeldTestSet(description::AbstractString; _...) = HeldTestSet(String(description), Any[])
Test.record(ts::HeldTestSet, result) = (push!(ts.results, result); result)
Test.finish(ts::HeldTestSet) = ts

_worker_answer(output::IO, fields...) =
    (println(output, WORKER_LINE_PREFIX, join(fields, '\t')); flush(output))

# The form of a filter on a command line: empty for none, `r"…"` for a Regex,
# any other text for a part of a name.
function read_name_filter(text::AbstractString)
    isempty(text) && return nothing
    startswith(text, "r\"") && endswith(text, "\"") && length(text) >= 3 &&
        return Regex(text[3:end-1])
    String(text)
end

# The module of a package, or of a file whose module has the name of the file.
_package_package_modulename(package::AbstractString) =
    Symbol(endswith(package, ".jl") ? first(splitext(basename(package))) : package)

# The suite `name` of `package`. A plain test function is a suite of one part.
function _worker_suite(package::AbstractString, name::AbstractString)
    suite = getglobal(getglobal(Main, _package_package_modulename(package)), Symbol(name))
    suite isa TestSuite && return suite
    suite isa Function && return TestSuite(String(name), [TestPart(suite)])
    error("$package.$name is no TestSuite and no function")
end

_index_text(index::Vector{Int}) = join(index, '.')
_read_index(text::AbstractString) = parse.(Int, split(text, '.'))

"""
    run_test_worker(input::IO = stdin, output::IO = stdout) -> Nothing

The loop of a worker process. It reads one command on each line of `input`,
with its fields separated by tabs, and answers with lines that start with
[`WORKER_LINE_PREFIX`](@ref) on `output`:

- `load PACKAGE`: load the package, or include the file when `PACKAGE` ends with
  `.jl`, with `Revise.includet` when Revise is loaded; answer `loaded PACKAGE SECONDS`.
- `revise`: apply the changes of the files with Revise; answer `revised yes`, or
  `revised no` when Revise is not loaded. A change that Revise can not apply
  gets the answer `failed`.
- `list PACKAGE SUITE ONLY SKIP BASE`, where a plain test function is a suite of
  one part: answer one line `part INDEX SUITEPATH NAME LIMIT ALONE` for each part
  that [`list_parts`](@ref) chooses, then `listed COUNT`. A filter is empty for
  none, `r"…"` for a `Regex`, or a part of a name. A `BASE` that is not empty
  keeps only the parts that the changes since `BASE` reach
  ([`reached_test_paths`](@ref)), with the `TEST_SLICE_EDGES` of the package when
  it has them.
- `run PACKAGE SUITE INDEX`: run the part at `INDEX`, with no standard input;
  answer `record` and the values of its [`PartRecord`](@ref), in the order of
  `PART_RECORD_COLUMNS`.
- `quit`: end the loop.

When it starts, the worker answers `columns` and the names of
`PART_RECORD_COLUMNS`, and `ready`. A command that throws gets the answer
`failed` and the message of the error.
"""
function run_test_worker(input::IO = stdin, output::IO = stdout)
    _worker_answer(output, "columns", PART_RECORD_COLUMNS...)
    _worker_answer(output, "ready")
    for line in eachline(input)
        fields = split(line, '\t')
        command = first(fields)
        command == "quit" && break
        try
            # The newest world, so a command sees what an earlier `load` defined.
            Base.invokelatest(_worker_command, output, command, fields[2:end])
        catch error
            _worker_answer(output, "failed", replace(sprint(showerror, error), r"\s+" => " "))
        end
    end
    nothing
end

function _worker_command(output::IO, command, arguments)
    if command == "load"
        package = arguments[1]
        seconds = @elapsed if endswith(package, ".jl")
            if isdefined(Main, :Revise)
                Base.invokelatest(getglobal(Main, :Revise).includet, Main, package)
            else
                Base.include(Main, package)
            end
        else
            Core.eval(Main, Expr(:using, Expr(:., Symbol(package))))
        end
        _worker_answer(output, "loaded", package, round(seconds; digits = 1))
    elseif command == "revise"
        if isdefined(Main, :Revise)
            sleep(1.0)                                   # Revise sees a write a moment later
            Base.invokelatest(getglobal(Main, :Revise).revise; throw = true)
            _worker_answer(output, "revised", "yes")
        else
            _worker_answer(output, "revised", "no")
        end
    elseif command == "list"
        package, name, only_text, skip_text, base = arguments
        suite = _worker_suite(package, name)
        parts = list_parts(suite; only = read_name_filter(only_text),
                           skip = read_name_filter(skip_text))
        if !isempty(base)
            package_module = getglobal(Main, _package_package_modulename(package))
            edges = isdefined(package_module, :TEST_SLICE_EDGES) ?
                getglobal(package_module, :TEST_SLICE_EDGES) : Dict{String, Any}()
            first_part = _first_part(suite)
            file = first_part === nothing ? "" : _method_file(first_part.run)
            root = _git_text(isfile(file) ? dirname(file) : pwd(), `rev-parse --show-toplevel`)
            reached = reached_test_paths(root, changed_files(root; base); slice_edges = edges)
            filter!(listed -> _is_reached(_part_path(listed.part, root), reached), parts)
        end
        for listed in parts
            _worker_answer(output, "part", _index_text(listed.index), listed.suite,
                           listed.part.name, listed.part.limit, listed.part.is_alone)
        end
        _worker_answer(output, "listed", length(parts))
    elseif command == "run"
        package, name, index = arguments
        suite = _worker_suite(package, name)
        part = find_part(suite, _read_index(index))
        path = only(listed.suite for listed in list_parts(suite)
                    if _index_text(listed.index) == index)
        source = _source_commit(suite)
        part_record = nothing
        redirect_stdin(devnull) do
            @testset HeldTestSet "worker" begin
                part_record = run_part(part; suite = path, repository = source[1],
                                       commit = source[2])
            end
        end
        values = (_record_text(getfield(part_record, column)) for column in PART_RECORD_COLUMNS)
        _worker_answer(output, "record", values...)
    else
        error("no command $command")
    end
end
