# Fragment of `SystemProcessModule` — the processes of a tree as the rows of a
# roster.

"""
    SystemProcesses(tree)

The source of a roster of every process of the [`SystemProcessTree`](@ref)
`tree`, at every depth, a parent before its children. The row of a process holds
its parent as `within`, and a root holds `nothing`. A process has the facets
`load` and `elapsed`; the other keys are its fields, such as `command` and
`memory`. The tree is the one part, so a sample gathers the rows again.

# Example

    Roster(SystemProcesses(tree); columns = ["process_id", "command", "load", "within.process_id"])
"""
struct SystemProcesses
    tree::Any
end

get_roster_item_type(::SystemProcesses) = SystemProcess
collect_roster_parts(source::SystemProcesses, link) = Any[source.tree]

function collect_roster_items(source::SystemProcesses, link, tree)
    items = RosterItem[]
    for process in tree.roots
        _collect_process_items!(items, process, nothing)
    end
    items
end

function _collect_process_items!(items, process, parent)
    push!(items, RosterItem(process, parent))
    for child in process.children
        _collect_process_items!(items, child, process)
    end
end
