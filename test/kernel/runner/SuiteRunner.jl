# ============================================================================
# The runner of a suite.
#
# A suite is a value: the name of its testset and a table of its parts. The
# runner calls each part through the table, at run time. So Julia compiles a
# part only when the part runs, and the memory of that compile is free again
# for the next part. A function that names each of its parts in its body makes
# Julia compile every part before the first test runs.
# ============================================================================

"""
    TestPart(run; name = String(nameof(run)))

One part of a [`TestSuite`](@ref): `run`, a function with no argument that runs
tests, and the name of the part. A plain function in the table of a suite becomes
a part with the name of the function. A test that takes an argument becomes a
part through a function with no argument and a name:

```julia
TestPart(() -> test_part_click(text_example); name = "test_part_click(text_example)")
```
"""
struct TestPart
    name::String
    run::Any
end

TestPart(run; name::AbstractString = String(nameof(run))) = TestPart(String(name), run)

"""
    TestSuite(name, entries)

A suite of tests as a value: `name`, the name of its testset, and `entries`, its
parts and the suites inside it, in the order they run. A plain function in
`entries` becomes a [`TestPart`](@ref) with the name of the function. A suite in
`entries` runs as a testset inside the testset of this suite.

Call the suite to run it, with the keywords of [`run_suite`](@ref):

```julia
const test_json = TestSuite("ProjecturedJSON", [test_json_layering, test_json_document])
test_json()
test_json(only = "document", record = "/var/tmp/json.tsv")
```

Each part runs in a testset of its own, with the name of the part. So a part
that throws records an error, and the parts after it still run.
"""
struct TestSuite
    name::String
    entries::Vector{Union{TestPart, TestSuite}}
end

TestSuite(name::AbstractString, entries::AbstractVector) =
    TestSuite(String(name), Union{TestPart, TestSuite}[_suite_entry(entry) for entry in entries])

_suite_entry(entry::Union{TestPart, TestSuite}) = entry
_suite_entry(run) = TestPart(run)

"""
    PartRecord

What one run of a part gave. `suite` is the path of the names of the suites that
hold the part, such as `"Projectured/ProjecturedPlatform"`, and `part` its name.
`result` is `"done"` for a part that ended. The times are in seconds and the sizes
in bytes: `compile_seconds` is the time of the compile while the part ran,
`live_bytes` the memory that the last garbage collection kept, and `peak_bytes` the
peak resident memory of the process so far.
"""
Base.@kwdef struct PartRecord
    repository::String = ""
    commit::String = ""
    suite::String = ""
    part::String
    pass::Int = 0
    fail::Int = 0
    error::Int = 0
    broken::Int = 0
    result::String = "done"
    seconds::Float64 = 0.0
    compile_seconds::Float64 = 0.0
    gc_seconds::Float64 = 0.0
    allocated_bytes::Int = 0
    live_bytes::Int = 0
    peak_bytes::Int = 0
end

"The columns of a record file, in their order: the fields of a `PartRecord`."
const PART_RECORD_COLUMNS = fieldnames(PartRecord)

"""
    run_suite(suite::TestSuite; only = nothing, skip = nothing, record = nothing)
        -> Test.AbstractTestSet

Run the entries of `suite` in their order, inside the testset of the suite, and
give that testset, or `nothing` when no part is chosen.

- `only`: a `String` or a `Regex`. Run only the parts whose name, or the name of a
  suite that holds them, matches it. A `String` matches a name that holds it.
- `skip`: the same form. Leave out each part and each suite whose name matches it.
- `record`: the path of a file. Add one line for each part that runs to it, as
  tab-separated values in the columns of `PART_RECORD_COLUMNS`. A new file starts
  with a line of the column names.

When a part ends, the runner prints one line with its counts and its times. At
the end of the outermost suite, it prints the ten slowest parts.
"""
function run_suite(suite::TestSuite; only = nothing, skip = nothing, record = nothing)
    is_outermost = Test.get_testset_depth() == 0
    chosen = select_parts(suite; only, skip)
    chosen === nothing && (println("No part of $(suite.name) matches."); return nothing)
    records = PartRecord[]
    source = _source_commit(chosen)
    try
        _run_entries(chosen, "", records, source, record)
    finally
        is_outermost && _print_slowest(records)
    end
end

function _run_entries(suite::TestSuite, path::String, records, source, record)
    here = isempty(path) ? suite.name : path * "/" * suite.name
    @testset Test.DefaultTestSet "$(suite.name)" begin
        for entry in suite.entries
            if entry isa TestSuite
                _run_entries(entry, here, records, source, record)
            else
                part_record = run_part(entry; suite = here, repository = source[1],
                                       commit = source[2])
                push!(records, part_record)
                record === nothing || write_part_record(record, part_record)
            end
        end
    end
end

"""
    select_parts(suite::TestSuite; only = nothing, skip = nothing) -> Union{TestSuite, Nothing}

The suite with only the entries that `only` and `skip` choose, as
[`run_suite`](@ref) reads them, or `nothing` when no part is left. A suite inside
it that keeps no part is left out.
"""
select_parts(suite::TestSuite; only = nothing, skip = nothing) =
    _select(suite, only, skip, only === nothing)

function _select(suite::TestSuite, only, skip, is_chosen::Bool)
    _name_matches(skip, suite.name) && return nothing
    is_chosen = is_chosen || _name_matches(only, suite.name)
    kept = Union{TestPart, TestSuite}[]
    for entry in suite.entries
        if entry isa TestSuite
            inner = _select(entry, only, skip, is_chosen)
            inner === nothing || push!(kept, inner)
        elseif !_name_matches(skip, entry.name) && (is_chosen || _name_matches(only, entry.name))
            push!(kept, entry)
        end
    end
    isempty(kept) ? nothing : TestSuite(suite.name, kept)
end

_name_matches(::Nothing, ::AbstractString) = false
_name_matches(pattern::Union{AbstractString, Regex}, name::AbstractString) = occursin(pattern, name)

"""
    select_by_name(items; only = nothing, skip = nothing) -> Vector

The items whose name matches `only` and does not match `skip`, in their order,
with the forms of [`run_suite`](@ref). The name of an item is its field `name`,
or the item itself when it is a `String`. A walk over the examples uses it:

```julia
function test_printers(; only = nothing, skip = nothing)
    for example in select_by_name(examples; only, skip)
        test_printer(example)
    end
end
```
"""
select_by_name(items; only = nothing, skip = nothing) =
    [item for item in items
     if (only === nothing || _name_matches(only, _item_name(item))) &&
        !_name_matches(skip, _item_name(item))]

_item_name(item::AbstractString) = item
_item_name(item) = item.name

"""
    run_part(part::TestPart; suite = "", repository = "", commit = "") -> PartRecord

Run `part` in a `Test.DefaultTestSet` with its name, print one line with its
counts and its times, and give its record. The testset of a part and of a suite
is a `DefaultTestSet` under a parent of any type, because the record reads its
counts. The call goes through `invokelatest`, so the part runs
in its newest form and Julia compiles it only now.
"""
function run_part(part::TestPart; suite::AbstractString = "", repository::AbstractString = "",
                  commit::AbstractString = "")
    stats = @timed @testset Test.DefaultTestSet "$(part.name)" begin
        Base.invokelatest(part.run)
    end
    counts = _test_counts(stats.value)
    part_record = PartRecord(; repository = String(repository), commit = String(commit),
                     suite = String(suite), part = part.name,
                     pass = counts[1], fail = counts[2], error = counts[3], broken = counts[4],
                     seconds = stats.time, compile_seconds = stats.compile_time,
                     gc_seconds = stats.gctime, allocated_bytes = Int(stats.bytes),
                     live_bytes = Int(Base.gc_live_bytes()), peak_bytes = Int(Sys.maxrss()))
    println(_part_line(part_record))
    part_record
end

function _test_counts(ts)
    ts isa Test.AbstractTestSet || return (0, 0, 0, 0)
    c = Test.get_test_counts(ts)
    (c.passes + c.cumulative_passes, c.fails + c.cumulative_fails,
     c.errors + c.cumulative_errors, c.broken + c.cumulative_broken)
end

_seconds_text(seconds::Real) = string(round(seconds; digits = 1), " s")

# The path of a part in its suites, such as "ProjecturedPlatform/test_text".
_part_place(part_record::PartRecord) =
    isempty(part_record.suite) ? part_record.part : part_record.suite * "/" * part_record.part

function _part_line(r::PartRecord)
    "  part $(_part_place(r)): $(r.pass) pass, $(r.fail) fail, $(r.error) error, " *
        "$(r.broken) broken, $(_seconds_text(r.seconds)), " *
        "compile $(_seconds_text(r.compile_seconds))"
end

function _print_slowest(records::Vector{PartRecord}; count::Int = 10)
    isempty(records) && return
    slowest = first(sort(records; by = part_record -> part_record.seconds, rev = true), count)
    println("The $(length(slowest)) slowest parts:")
    for part_record in slowest
        println(lpad(_seconds_text(part_record.seconds), 10), "  ", _part_place(part_record))
    end
end

"""
    write_part_record(path, part_record::PartRecord) -> Nothing

Add `part_record` to the record file at `path` as one line of tab-separated
values. A new or empty file first gets the line of the column names.
"""
function write_part_record(path::AbstractString, part_record::PartRecord)
    is_new = !isfile(path) || filesize(path) == 0
    open(path, "a") do io
        is_new && println(io, join(PART_RECORD_COLUMNS, '\t'))
        values = (_record_text(getfield(part_record, column)) for column in PART_RECORD_COLUMNS)
        println(io, join(values, '\t'))
    end
    nothing
end

_record_text(value::AbstractFloat) = string(round(value; digits = 3))
_record_text(value) = replace(string(value), '\t' => ' ', '\n' => ' ')

"""
    read_part_records(path) -> Vector{PartRecord}

The records of the file at `path`, in the order of its lines.
"""
function read_part_records(path::AbstractString)
    lines = readlines(path)
    isempty(lines) && return PartRecord[]
    columns = Symbol.(split(first(lines), '\t'))
    records = PartRecord[]
    for line in lines[2:end]
        isempty(line) && continue
        values = Dict(zip(columns, split(line, '\t')))
        fields = Dict{Symbol, Any}()
        for (name, type) in zip(fieldnames(PartRecord), fieldtypes(PartRecord))
            haskey(values, name) || continue
            text = values[name]
            fields[name] = type === String ? String(text) : parse(type, text)
        end
        push!(records, PartRecord(; fields...))
    end
    records
end

# The repository and the commit of the file of the first part, and a "+" after a
# commit whose tree has changes that are not committed.
function _source_commit(suite::TestSuite)
    part = _first_part(suite)
    file = part === nothing ? "" : _method_file(part.run)
    folder = isfile(file) ? dirname(file) : pwd()
    top = _git_text(folder, `rev-parse --show-toplevel`)
    commit = _git_text(folder, `rev-parse --short=12 HEAD`)
    isempty(commit) || isempty(_git_text(folder, `status --porcelain --untracked-files=no`)) ||
        (commit *= "+")
    (isempty(top) ? "" : basename(top), commit)
end

_first_part(part::TestPart) = part
function _first_part(suite::TestSuite)
    for entry in suite.entries
        found = _first_part(entry)
        found === nothing || return found
    end
    nothing
end

function _method_file(run)
    found = methods(run)
    isempty(found) ? "" : string(first(found).file)
end

_git_text(folder::AbstractString, arguments::Cmd) =
    try
        readchomp(pipeline(`git -C $folder $arguments`; stderr = devnull))
    catch
        ""
    end

(suite::TestSuite)(; keywords...) = run_suite(suite; keywords...)
