# Fragment of `SystemProcessModule` — the read of the processes of the system from
# a folder that the kernel fills as it fills `/proc`. A read answers plain records
# and writes nothing, so it runs on any task.

"""
    SystemProcessRecord

One process as one read of `/proc` saw it, a plain value that no later read
changes. `start_ticks` is the start of the process after the boot, in clock
ticks: with the process id it names one process, because the system gives a
process id again only to a process that starts later. `start_time` is the same
start in seconds since the epoch. `processor_ticks` is the processor time of the
process in user and in system mode, `memory` its resident memory in bytes, and
`children` the process ids of its children that the read found, in order.
"""
struct SystemProcessRecord
    process_id::Int
    parent_process_id::Int
    command::String
    folder::String
    state::Symbol
    start_ticks::Int
    start_time::Float64
    processor_ticks::Int
    memory::Int
    thread_count::Int
    children::Vector{Int}
end

"""
    read_system_processes(root_process_ids; root = "/proc") -> Vector{SystemProcessRecord}

Read the processes under `root_process_ids` from `root`: each root and its
children at every depth, a parent before its children. It reads `stat`,
`statm`, `cmdline` and the link `cwd` of each process, and its children from the
`children` file of each of its threads, because a child that another thread of
the process started is listed only there. The boot time in `<root>/stat` makes
the start time.

A process that ended during the read is left out, with the children that only it
named. A kernel thread has an empty command line, so its command is its name in
brackets, such as `[kthreadd]`. A folder that the reader may not see is an empty
`folder`. With no `root` folder, as on a system with no `/proc`, the answer is
empty.
"""
function read_system_processes(root_process_ids; root::AbstractString = "/proc")
    isdir(root) || return SystemProcessRecord[]
    boot_time = _read_boot_time(root)
    boot_time === nothing && return SystemProcessRecord[]
    records = SystemProcessRecord[]
    seen = Set{Int}()
    for process_id in root_process_ids
        _read_process_subtree!(records, seen, root, Int(process_id), boot_time)
    end
    records
end

"""
    read_system_process_usage(process_id; root = "/proc") -> (processor_ticks, memory) or nothing

The processor time of one process in clock ticks, in user and in system mode,
and its resident memory in bytes; `nothing` when the process is gone or the
system has no `/proc`.
"""
function read_system_process_usage(process_id::Integer; root::AbstractString = "/proc")
    folder = joinpath(root, string(process_id))
    parsed = _parse_stat(_read_text(joinpath(folder, "stat")))
    parsed === nothing && return nothing
    memory = _parse_resident_memory(_read_text(joinpath(folder, "statm")))
    memory === nothing && return nothing
    (parsed.processor_ticks, memory)
end

"""
    get_clock_ticks_per_second() -> Int

The clock ticks of the system in one second, `sysconf(_SC_CLK_TCK)`: the unit of
the processor time and of the start of a process in `/proc`.
"""
get_clock_ticks_per_second() = Int(ccall(:sysconf, Clong, (Cint,), 2))

# ── One process ──────────────────────────────────────────────────────────────

# Read the process `process_id` and the processes under it into `records`, a
# parent before its children. A process seen already is not read again.
function _read_process_subtree!(records, seen::Set{Int}, root, process_id::Int, boot_time::Float64)
    process_id in seen && return false
    push!(seen, process_id)
    record = _read_process(root, process_id, boot_time)
    record === nothing && return false
    push!(records, record)
    for child in _read_child_process_ids(root, process_id)
        _read_process_subtree!(records, seen, root, child, boot_time) && push!(record.children, child)
    end
    true
end

# The record of one process with no children yet, or `nothing` when the process
# ended before its files were read.
function _read_process(root, process_id::Int, boot_time::Float64)
    folder = joinpath(root, string(process_id))
    parsed = _parse_stat(_read_text(joinpath(folder, "stat")))
    parsed === nothing && return nothing
    memory = _parse_resident_memory(_read_text(joinpath(folder, "statm")))
    memory === nothing && return nothing
    arguments = try
        read(joinpath(folder, "cmdline"))
    catch
        return nothing
    end
    words = split(String(arguments), '\0'; keepempty = false)
    command = isempty(words) ? "[" * parsed.name * "]" : join(words, " ")
    working_folder = try
        readlink(joinpath(folder, "cwd"))
    catch
        ""
    end
    SystemProcessRecord(process_id, parsed.parent_process_id, command, working_folder, parsed.state,
                        parsed.start_ticks, boot_time + parsed.start_ticks / get_clock_ticks_per_second(),
                        parsed.processor_ticks, memory, parsed.thread_count, Int[])
end

# The process ids of the children of a process, from the `children` file of each
# of its threads, in order.
function _read_child_process_ids(root, process_id::Int)
    threads = joinpath(root, string(process_id), "task")
    names = try
        readdir(threads)
    catch
        return Int[]
    end
    found = Int[]
    for thread in names
        text = _read_text(joinpath(threads, thread, "children"))
        text === nothing && continue
        for word in split(text)
            child = tryparse(Int, word)
            child === nothing || child in found || push!(found, child)
        end
    end
    sort!(found)
end

# ── The files ────────────────────────────────────────────────────────────────

_read_text(path) = try
    read(path, String)
catch
    nothing
end

# The time of the boot in seconds since the epoch, the line `btime` of `<root>/stat`.
function _read_boot_time(root)
    text = _read_text(joinpath(root, "stat"))
    text === nothing && return nothing
    for line in eachline(IOBuffer(text))
        startswith(line, "btime ") && return tryparse(Float64, strip(line[7:end]))
    end
    nothing
end

# The fields of a `stat` file that a record holds, or `nothing`. The name of the
# command is in parentheses and can hold spaces and parentheses, so the fields are
# counted from the last ")": the state is field 3 of the line, the parent field 4,
# the user and the system time fields 14 and 15, the threads field 20 and the start
# field 22.
function _parse_stat(text)
    text === nothing && return nothing
    opening = findfirst('(', text)
    closing = findlast(')', text)
    (opening === nothing || closing === nothing || closing < opening) && return nothing
    fields = split(text[closing + 1:end])
    length(fields) >= 20 || return nothing
    numbers = [tryparse(Int, fields[k]) for k in (2, 12, 13, 18, 20)]
    any(isnothing, numbers) && return nothing
    (parent, user, system, threads, start) = numbers
    (; name = text[nextind(text, opening):prevind(text, closing)], state = _get_process_state(fields[1]),
       parent_process_id = parent, processor_ticks = user + system, thread_count = threads,
       start_ticks = start)
end

# The resident memory in bytes, from the second field of `statm`, in pages.
function _parse_resident_memory(text)
    text === nothing && return nothing
    pages = split(text)
    length(pages) >= 2 || return nothing
    resident = tryparse(Int, pages[2])
    resident === nothing ? nothing : resident * _get_page_size()
end

# The state that the letter of `stat` names.
function _get_process_state(letter::AbstractString)
    letter == "R" && return :running
    letter == "S" && return :sleeping
    letter == "D" && return :disk_wait
    letter in ("T", "t") && return :stopped
    letter == "Z" && return :zombie
    letter == "I" && return :idle
    :other
end

_get_page_size() = Int(ccall(:getpagesize, Cint, ()))
