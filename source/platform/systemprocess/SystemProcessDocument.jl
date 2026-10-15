# Fragment of `SystemProcessModule` — the documents: one process, and the tree of
# the processes under a set of roots with the sampler that reads them; how each
# is a node of a tree, its title, and the facets of a process.

"""
    SystemProcess

One process of the system, as a document that a sync of its tree keeps up to
date ([`sync_system_process_tree!`](@ref)). Each field is a cell of its own, so a
change of one fact writes one cell, and a view of another fact draws nothing
again.

# Fields
- `process_id`, `parent_process_id` — the process and its parent.
- `command` — the command line, or the name of a kernel thread in brackets.
- `folder` — the working folder, or `""` when the reader may not see it.
- `state` — `:running`, `:sleeping`, `:disk_wait`, `:stopped`, `:zombie`,
  `:idle` or `:other`.
- `start_time` — the start, in seconds since the epoch.
- `processor_load` — the processor time since the sample before, in percent of
  one processor; `nothing` at the first sample of the process.
- `memory` — the resident memory, in bytes.
- `thread_count` — the threads of the process.
- `children` — the processes that it started, a `CellVector` of `SystemProcess`.
- `start_ticks` — the start in clock ticks after the boot. With the process id
  it is the key of the document, so a process id that the system gives again is
  another document.
- `sampled_at` — the time of the last sample of the tree. The cell is the cell
  `sampled_at` of the tree itself, so one write moves the elapsed time of every
  process of the tree, and no clock is read.
"""
@document struct SystemProcess <: Document
    process_id::Int
    parent_process_id::Int
    command::String
    folder::String
    state::Symbol
    start_time::Float64
    processor_load::Union{Nothing,Float64}
    memory::Int
    thread_count::Int
    children::CellVector
    start_ticks::Int
    sampled_at::Union{Nothing,Float64}
end

"""
    SystemProcessTree(root_process_ids; title = "Processes of …")

The processes under `root_process_ids`, as a document: each root that runs is
one of `roots`, and each process holds its children. A sync brings a read of
`/proc` into it ([`sync_system_process_tree!`](@ref)), and a drain reads and
syncs once in an interval while a view reads `roots`
([`drain_system_process_tree!`](@ref)). `sampled_at` is the time of the read of
the last sync, so a view shows an elapsed time with no clock. `sampler` holds
the read that runs and what a load needs, and a walk of the documents does not
enter it.

Show it with [`show_system_process_tree!`](@ref), or alone, as the page of a
navigator, where it draws as a tree.
"""
@document struct SystemProcessTree <: Document
    root_process_ids::Vector{Int}
    title::String
    roots::CellVector
    sampled_at::Union{Nothing,Float64}
    sampler::Any
end

SystemProcessTree(root_process_ids; title::AbstractString = _format_tree_title(root_process_ids)) =
    SystemProcessTree(collect(Int, root_process_ids), String(title), CellVector(Any[]), nothing,
                      _SystemProcessSampler())

_format_tree_title(root_process_ids) = "Processes of " * join(root_process_ids, ", ")

# What the drain of a tree needs and no view shows: the lock of the result, the
# read that runs on a task of its own, the result of the last read with the time
# at which it read, the time of the last start, and the processor ticks of each
# process at the last sample, by its process id and its start ticks.
mutable struct _SystemProcessSampler
    lock::ReentrantLock
    reading::Union{Task,Nothing}
    result::Union{Nothing,Tuple{Float64,Vector{SystemProcessRecord}}}
    started_at::Float64
    processor_ticks::Dict{Tuple{Int,Int},Int}
end

_SystemProcessSampler() =
    _SystemProcessSampler(ReentrantLock(), nothing, nothing, -Inf, Dict{Tuple{Int,Int},Int}())

# A walk of the documents finds no document in a sampler, and must not enter its
# task or its lock.
is_walk_opaque(::_SystemProcessSampler) = true

get_document_title(tree::SystemProcessTree) = tree.title
get_document_title(process::SystemProcess) =
    string(process.process_id, " ", _shorten_command(process.command; limit = 40))

# ── The nodes of a tree ──────────────────────────────────────────────────────

get_tree_children_steps(::SystemProcessTree) = ((FieldReferenceStep("roots"),),)
get_tree_children_steps(::SystemProcess) = ((FieldReferenceStep("children"),),)

format_tree_node_label(process::SystemProcess) =
    string(process.process_id, "  ", _shorten_command(process.command), "  ",
           _format_processor_load(process.processor_load), "  ", format_memory_size(process.memory))

get_tree_node_icon(::SystemProcess) = :terminal

# A command as a label shows it: at most `limit` characters, the rest an ellipsis.
_shorten_command(command::AbstractString; limit::Integer = 60) =
    length(command) <= limit ? String(command) : first(command, limit - 1) * "…"

_format_processor_load(load) = load === nothing ? "–" : string(round(load; digits = 1), "%")

"""A number of bytes in the unit a person reads: `512 B`, `12.3 MB`, `1.2 GB`."""
function format_memory_size(bytes::Integer)
    bytes < 1024 && return string(bytes, " B")
    for (unit, size) in (("GB", 1024^3), ("MB", 1024^2), ("kB", 1024))
        bytes >= size && return string(round(bytes / size; digits = 1), " ", unit)
    end
end

# ── The facets ───────────────────────────────────────────────────────────────

# The facets of a process in a roster, which a roster shows, filters, sorts and
# groups by.
get_item_facets(::Type{SystemProcess}) = [
    "load" => "the processor time since the sample before, in percent of one processor",
    "elapsed" => "the seconds from the start of the process to the last sample"]
compute_item_facet(process::SystemProcess, ::Val{:load}) = process.processor_load
compute_item_facet(process::SystemProcess, ::Val{:elapsed}) = _compute_elapsed_time(process)

# The seconds from the start of a process to the last sample of its tree, or
# `nothing` before the first.
function _compute_elapsed_time(process::SystemProcess)
    sampled_at = process.sampled_at
    sampled_at === nothing ? nothing : max(0.0, sampled_at - process.start_time)
end
