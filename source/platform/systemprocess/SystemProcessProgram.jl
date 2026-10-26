# Fragment of `SystemProcessModule` — the processes as code and a language model
# use them: the verb that shows the tree of the processes under a set of roots in
# a tab, and the verb that writes it as text.

"""
    show_system_process_tree!(root_process_ids; title = "Processes of …", editor = get_evaluation_editor())
        -> ReferencedDocument

Show the processes under `root_process_ids` as a tree in a tab of the window of
`editor`, and answer the tree in its window. Each node says the process id, the
command, the processor load and the memory, and a double click on a node opens
the page of its process, with its facts and the buttons Interrupt and Stop. The
tree reads `/proc` once a second while the tab shows it.

Use it to watch what a program started: the compilers of a build, the workers
of a simulation, the shells and the commands of a terminal.

# Example

    show_system_process_tree!([getpid()]; title = "This session")

See also `describe_system_process_tree`, which writes the same tree once as
text, and `show_document_tree!`.
"""
function show_system_process_tree! end

function show_system_process_tree!(root_process_ids; title::AbstractString = _format_tree_title(root_process_ids),
                                   editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "show_system_process_tree!") do
        tree = SystemProcessTree(root_process_ids; title)
        push!(_get_system_process_feed(editor).trees, tree)
        show_document_tree!(tree; title, editor)
    end
end

# The feed of the trees of processes of `editor`, which the editor got when it
# was made.
function _get_system_process_feed(editor)
    for feed in editor.feeds
        feed isa SystemProcessFeed && return feed
    end
    throw(ArgumentError("The editor has no SystemProcessFeed, so a tree would not follow " *
                        "its processes. Make it with build_editor, whose wrapper " *
                        "system_process gives the feed."))
end

"""
    describe_system_process_tree(root_process_ids) -> Text

The processes under `root_process_ids` as text, read from `/proc` once: a line
for each process, indented under its parent, with the process id, the command,
the state and the resident memory. A process id that does not run has no line,
and a system with no `/proc` says so. It reads no document, so it runs on the
task that calls it.

Use it to see in one call what a program started, and what each part of it
does now.

# Example

    describe_system_process_tree([getpid()])

See also `show_system_process_tree!`, which shows the tree in a tab and keeps it
up to date.
"""
function describe_system_process_tree end

function describe_system_process_tree(root_process_ids)
    isdir("/proc") || return Text("This system has no /proc, so no process can be read.")
    records = read_system_processes(root_process_ids)
    isempty(records) && return Text(string("No process of ", join(root_process_ids, ", "), " runs."))
    by_id = Dict(record.process_id => record for record in records)
    lines = String[]
    for process_id in root_process_ids
        haskey(by_id, process_id) && _describe_process!(lines, by_id, by_id[process_id], 0)
    end
    Text(join(lines, "\n"))
end

function _describe_process!(lines, by_id, record::SystemProcessRecord, depth::Int)
    push!(lines, string("  "^depth, record.process_id, " ", record.command, " — ",
                        replace(String(record.state), "_" => " "), ", ", format_memory_size(record.memory)))
    for child in record.children
        haskey(by_id, child) && _describe_process!(lines, by_id, by_id[child], depth + 1)
    end
end
