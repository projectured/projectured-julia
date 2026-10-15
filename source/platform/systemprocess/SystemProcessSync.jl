# Fragment of `SystemProcessModule` — a read of `/proc` brought into the documents
# of a tree. The read runs on a task of its own and writes no cell; the sync runs
# on the editor task and writes only the cells that changed. The owner of a tree
# drains it, from a feed that its window has already: a `SystemProcessFeed` for a
# tree that a verb shows, the feed of the tasks for the tree of a task.

"""
    sync_system_process_tree!(tree, records; now = time()) -> tree

Bring the records of one read ([`read_system_processes`](@ref)) into `tree`, on
the editor task. `now` is the time of the read.

A document stays the document of its process: the sync keeps it by its process
id and its start ticks, and writes only the fields that changed. A process id
with other start ticks is another process, and gets a document of its own. A
process that is in no record has ended, and leaves the tree. A list of children,
and `roots`, stays the same list while its members are the same documents. So a
sync with no change writes no cell but `sampled_at`, and a sync at the same `now`
writes none.

The processor load of a process is its processor time since the sync before,
over the time since then. The first sample of a process gives `nothing`.
"""
function sync_system_process_tree!(tree::SystemProcessTree, records; now::Real = time())
    sampler = tree.sampler
    previous = tree.sampled_at
    known = Dict{Tuple{Int,Int},Any}()
    _collect_known_processes!(known, tree.roots, Base.IdSet{Any}())
    sync = _SystemProcessSync(Dict{Int,SystemProcessRecord}(r.process_id => r for r in records),
                              known, sampler.processor_ticks, Dict{Tuple{Int,Int},Int}(),
                              previous === nothing ? nothing : now - previous,
                              getfield(tree, :sampled_at), Set{Int}())
    roots = Any[_sync_system_process!(sync, sync.records[id])
                for id in tree.root_process_ids if haskey(sync.records, id) && !(id in sync.visited)]
    _replace_members!(getfield(tree, :roots), roots)
    sampler.processor_ticks = sync.ticks
    isequal(previous, Float64(now)) || (tree.sampled_at = Float64(now))
    tree
end

# What one sync reads and gathers: the records by process id, the documents that
# the tree held by their key, the processor ticks of the sample before and of this
# one, the seconds since the sample before, the cell of the time of the sample,
# and the process ids that the sync placed.
struct _SystemProcessSync
    records::Dict{Int,SystemProcessRecord}
    known::Dict{Tuple{Int,Int},Any}
    previous_ticks::Dict{Tuple{Int,Int},Int}
    ticks::Dict{Tuple{Int,Int},Int}
    seconds::Union{Nothing,Float64}
    sampled_at::Any
    visited::Set{Int}
end

function _collect_known_processes!(known, processes, seen)
    for process in processes
        process in seen && continue
        push!(seen, process)
        known[(process.process_id, process.start_ticks)] = process
        _collect_known_processes!(known, process.children, seen)
    end
end

# The document of `record` with its children, the one the tree held when its key
# is known, with each field that changed written.
function _sync_system_process!(sync::_SystemProcessSync, record::SystemProcessRecord)
    push!(sync.visited, record.process_id)
    key = (record.process_id, record.start_ticks)
    sync.ticks[key] = record.processor_ticks
    children = Any[]
    for child in record.children
        (haskey(sync.records, child) && !(child in sync.visited)) || continue
        push!(children, _sync_system_process!(sync, sync.records[child]))
    end
    document = get(sync.known, key, nothing)
    load = _compute_processor_load(sync, key, record.processor_ticks, document)
    document === nothing &&
        return SystemProcess(record.process_id, record.parent_process_id, record.command,
                             record.folder, record.state, record.start_time, load, record.memory,
                             record.thread_count, CellVector(children), record.start_ticks,
                             sync.sampled_at)
    for (name, value) in (:parent_process_id => record.parent_process_id, :command => record.command,
                          :folder => record.folder, :state => record.state,
                          :start_time => record.start_time, :processor_load => load,
                          :memory => record.memory, :thread_count => record.thread_count)
        isequal(getproperty(document, name), value) || setproperty!(document, name, value)
    end
    _replace_members!(getfield(document, :children), children)
    document
end

# The processor time of a process since the sample before, in percent of one
# processor over the seconds between the two. A process that the sample before did
# not see has no load; a sample at the same time keeps the load that it had.
function _compute_processor_load(sync::_SystemProcessSync, key, ticks::Int, document)
    previous = get(sync.previous_ticks, key, nothing)
    previous === nothing && return nothing
    seconds = sync.seconds
    (seconds === nothing || seconds <= 0) &&
        return document === nothing ? nothing : document.processor_load
    100 * (ticks - previous) / get_clock_ticks_per_second() / seconds
end

# Write `members` into the cell of a list only when they are not the same
# documents in the same order, so a list whose members stay is the same list.
function _replace_members!(cell, members::Vector{Any})
    current = cell[]
    length(current) == length(members) && all(k -> current[k] === members[k], eachindex(members)) &&
        return nothing
    cell[] = CellVector(members)
    nothing
end

# ── The drain ────────────────────────────────────────────────────────────────

"""
    drain_system_process_tree!(tree; now = time(), interval = 1.0) -> Int

The step of the sample of `tree` on the editor task, and how many reads it
synced. While a view reads `roots` of the tree, it syncs a read that ended, and
starts a new read on a task of its own when none runs and `interval` seconds
passed since the last start. A tree that no view reads does nothing, so a tree
that nobody looks at costs no read of `/proc`.

The owner of a tree calls it from a feed of its window: a
[`SystemProcessFeed`](@ref), or the feed of the tasks for the tree of a task.
"""
function drain_system_process_tree!(tree::SystemProcessTree; now::Real = time(), interval::Real = 1.0)
    has_dependent_cells(getfield(tree, :roots)) || return 0
    sampler = tree.sampler
    synced = 0
    reading = sampler.reading
    if reading !== nothing && istaskdone(reading)
        sampler.reading = nothing
        result = lock(sampler.lock) do
            taken = sampler.result
            sampler.result = nothing
            taken
        end
        if result !== nothing
            sync_system_process_tree!(tree, last(result); now = first(result))
            synced = 1
        end
    end
    if sampler.reading === nothing && now - sampler.started_at >= interval
        sampler.started_at = Float64(now)
        root_process_ids = collect(Int, tree.root_process_ids)
        sampler.reading = Threads.@spawn _read_into_sampler!(sampler, root_process_ids)
    end
    synced
end

# The read of a task of its own: the records and the time at which it read them,
# into the sampler, under its lock. A read that fails is a warning, and the next
# interval reads again.
function _read_into_sampler!(sampler::_SystemProcessSampler, root_process_ids::Vector{Int})
    read_at = time()
    records = try
        read_system_processes(root_process_ids)
    catch exception
        @warn "a read of the system processes failed" exception
        return nothing
    end
    lock(() -> (sampler.result = (read_at, records)), sampler.lock)
    nothing
end

"""
    compute_system_process_tree_deadline(tree; now = time(), interval = 1.0) -> Float64 or nothing

The seconds until the next sample of `tree` while a view reads it, and
`nothing` while none does, so a window that shows no tree sleeps.
"""
function compute_system_process_tree_deadline(tree::SystemProcessTree; now::Real = time(),
                                              interval::Real = 1.0)
    has_dependent_cells(getfield(tree, :roots)) || return nothing
    max(0.0, tree.sampler.started_at + interval - now)
end

# ── The feed ─────────────────────────────────────────────────────────────────

"""
    SystemProcessFeed(; interval = 1.0)

The feed of a window that shows trees of processes: each drain samples each of
`trees` with [`drain_system_process_tree!`](@ref), and the window wakes for the
nearest sample of a tree that a view reads. A tree that no view reads costs one
check in each drain. [`show_system_process_tree!`](@ref) adds the feed to the
editor, and the tree to it.
"""
struct SystemProcessFeed <: Feed
    trees::Vector{Any}
    interval::Float64
end

SystemProcessFeed(; interval::Real = 1.0) = SystemProcessFeed(Any[], Float64(interval))

function drain_changes!(feed::SystemProcessFeed, editor)
    now = time()
    sum((drain_system_process_tree!(tree; now, interval = feed.interval) for tree in feed.trees); init = 0)
end

function compute_wake_deadline(feed::SystemProcessFeed, editor)
    now = time()
    deadlines = (compute_system_process_tree_deadline(tree; now, interval = feed.interval) for tree in feed.trees)
    reduce((a, b) -> b === nothing ? a : a === nothing ? b : min(a, b), deadlines; init = nothing)
end
