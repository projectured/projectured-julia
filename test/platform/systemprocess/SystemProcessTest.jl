# The processes of the system as documents: a read of a fixture folder that is
# laid out as `/proc`, the sync that keeps a document by its process id and its
# start ticks, a sync that writes nothing when nothing changed, the drain that
# reads only while a view reads the tree, a real tree of `sleep`, the guard of a
# signal, and the detail of a running task. The editor of the navigator is the
# one of `NavigatorToWidgetTest.jl`, and the task and its pane are those of
# `TaskGroupTest.jl` and `TaskGroupToWidgetTest.jl`.

# One process of a fixture folder: its stat line, its statm, its command line, its
# working folder, and the children that each of its threads lists.
struct _SysprocFixture
    process_id::Int
    parent_process_id::Int
    name::String
    arguments::Vector{String}
    state::Char
    processor_ticks::Int
    thread_count::Int
    start_ticks::Int
    resident_pages::Int
    folder::String
    children::Vector{Pair{Int,Vector{Int}}}
end

_sysproc_fixture(process_id, parent_process_id, name, arguments; state = 'S', processor_ticks = 0,
                 thread_count = 1, start_ticks = 5000, resident_pages = 100, folder = "",
                 children = [process_id => Int[]]) =
    _SysprocFixture(process_id, parent_process_id, name, arguments, state, processor_ticks,
                    thread_count, start_ticks, resident_pages, folder, children)

# A folder laid out as `/proc`, in a folder of its own under TMPDIR, with a boot
# time of 1000.
function _sysproc_write(processes)
    root = mktempdir(get(ENV, "TMPDIR", tempdir()))
    write(joinpath(root, "stat"), "cpu  1 2 3 4\nbtime 1000\n")
    for p in processes
        folder = joinpath(root, string(p.process_id))
        mkpath(folder)
        write(joinpath(folder, "stat"),
              "$(p.process_id) ($(p.name)) $(p.state) $(p.parent_process_id) $(p.process_id) " *
              "$(p.process_id) 0 -1 4194304 0 0 0 0 $(p.processor_ticks) 0 0 0 20 0 " *
              "$(p.thread_count) 0 $(p.start_ticks) 1000 $(p.resident_pages) 0\n")
        write(joinpath(folder, "statm"), "200 $(p.resident_pages) 10 5 0 20 0\n")
        write(joinpath(folder, "cmdline"), isempty(p.arguments) ? "" : join(p.arguments, '\0') * '\0')
        isempty(p.folder) || symlink(p.folder, joinpath(folder, "cwd"))
        for (thread, children) in p.children
            mkpath(joinpath(folder, "task", string(thread)))
            write(joinpath(folder, "task", string(thread), "children"), join(string.(children) .* " "))
        end
    end
    root
end

# A shell whose second thread started a worker, a worker with a zombie child and a
# child that ended during the read, and a kernel thread.
function _sysproc_processes(; sleep_start = 5100, sleep_ticks = 0, worker = true)
    processes = [
        _sysproc_fixture(100, 1, "bash", ["bash", "-c", "x"]; thread_count = 2, folder = "/home/x",
                         children = [100 => [200], 101 => (worker ? [300] : Int[])]),
        _sysproc_fixture(200, 100, "sleep", ["sleep", "30"]; start_ticks = sleep_start,
                         processor_ticks = sleep_ticks, resident_pages = 50, folder = "/tmp"),
        _sysproc_fixture(2, 0, "kthreadd", String[]; start_ticks = 1, resident_pages = 0)]
    worker && append!(processes, [
        _sysproc_fixture(300, 100, "a (b) c", ["worker", "--fast"]; state = 'R', start_ticks = 5200,
                         children = [300 => [400, 500]]),
        _sysproc_fixture(400, 300, "zz", ["zz"]; state = 'Z', start_ticks = 5300)])
    processes
end

_sysproc_page_size() = Int(ccall(:getpagesize, Cint, ()))

# Every process of a tree, a parent before its children.
function _sysproc_collect(tree)
    found = Any[]
    collect_below(process) = (push!(found, process); foreach(collect_below, process.children))
    foreach(collect_below, tree.roots)
    found
end

_sysproc_keys(tree) = [(p.process_id, p.start_ticks) for p in _sysproc_collect(tree)]

# Drain `tree` until `done()` holds, at most `seconds`.
function _sysproc_drain_until(done, tree; seconds = 10)
    deadline = time() + seconds
    while !done() && time() < deadline
        drain_system_process_tree!(tree; interval = 0.05)
        sleep(0.05)
    end
    done()
end

function _sysproc_wait_read(tree)
    reading = tree.sampler.reading
    reading === nothing || timedwait(() -> istaskdone(reading), 10.0)
    nothing
end

function test_system_process()
@testset "system processes" begin
    ticks = get_clock_ticks_per_second()
    page = _sysproc_page_size()

    @testset "a fixed /proc folder gives a known tree" begin
        root = _sysproc_write(_sysproc_processes())
        records = read_system_processes([100, 2, 999]; root)
        # A parent before its children; a root that does not run, and a child that
        # ended during the read, are left out.
        @test [r.process_id for r in records] == [100, 200, 300, 400, 2]
        shell = records[1]
        @test shell.command == "bash -c x" && shell.folder == "/home/x" && shell.state === :sleeping
        @test shell.parent_process_id == 1 && shell.thread_count == 2 && shell.memory == 100 * page
        @test shell.start_ticks == 5000 && shell.start_time ≈ 1000 + 5000 / ticks
        # A child of the second thread of the shell is a child of the shell.
        @test shell.children == [200, 300]
        @test records[3].command == "worker --fast" && records[3].state === :running
        @test records[3].children == [400] && records[4].state === :zombie
        @test records[5].command == "[kthreadd]" && records[5].folder == ""
        @test isempty(read_system_processes([100]; root = joinpath(root, "none")))
        @test read_system_process_usage(200; root) == (0, 50 * page)
        @test read_system_process_usage(999; root) === nothing

        tree = SystemProcessTree([100, 2, 999])
        @test tree.title == "Processes of 100, 2, 999" && get_document_title(tree) == tree.title
        sync_system_process_tree!(tree, records; now = 2000.0)
        @test [p.process_id for p in tree.roots] == [100, 2]
        shell = tree.roots[1]
        @test [p.process_id for p in shell.children] == [200, 300]
        @test [p.process_id for p in shell.children[2].children] == [400]
        @test shell.processor_load === nothing && tree.sampled_at == 2000.0 && shell.sampled_at == 2000.0
        @test get_tree_children_steps(tree) == ((FieldReferenceStep("roots"),),)
        @test get_tree_children_steps(shell) == ((FieldReferenceStep("children"),),)
        @test format_tree_node_label(shell) == "100  bash -c x  –  " * format_memory_size(100 * page)
        @test get_document_decoration(shell).icon === :terminal
        @test compute_item_facet(shell, Val(:elapsed)) ≈ 2000.0 - shell.start_time
        @test compute_item_facet(shell, Val(:load)) === nothing
        # The walk of the documents finds the processes, and does not enter the sampler.
        @test length(search_documents(tree, node -> node isa SystemProcess)) == 5
        @test isempty(search_documents(tree, node -> node isa ReentrantLock; raw = true))

        # A roster has a row for each process, with its parent as `within`.
        roster = link_roster!(Roster(SystemProcesses(tree);
                                     columns = ["process_id", "command", "load", "within.process_id"]), tree)
        @test [row.values[1] for row in roster.rows] == [100, 200, 300, 400, 2]
        @test [row.values[4] for row in roster.rows][2:4] == [100, 100, 300]
        @test ["load", "elapsed"] ⊆ first.(collect_item_facets(SystemProcess))
    end

    @testset "a tree whose folder is not there says why it is empty" begin
        @test format_tree_node_label(SystemProcessTree([100]; root = _sysproc_write(_sysproc_processes()))) ==
              "Processes of 100"
        tree = SystemProcessTree([100]; root = joinpath(_sysproc_write(_sysproc_processes()), "none"))
        @test get_document_title(tree) == "Processes of 100"
        widget = print_document(DocumentTreeToWidgetTree(), nothing, DocumentTree(tree), nothing).output
        @test widget.roots[1].label == "No /proc on this system: the processes can not be read."
        @test isempty(widget.roots[1].children)
        # A read of that folder answers no process.
        view = Cell(@computation length(tree.roots))
        @test view[] == 0
        drain_system_process_tree!(tree; now = 100.0)
        _sysproc_wait_read(tree)
        @test drain_system_process_tree!(tree; now = 100.5) == 1 && view[] == 0
    end

    @testset "a tree draws as a tree in a navigator, and a node opens the page of its process" begin
        root = _sysproc_write(_sysproc_processes())
        tree = SystemProcessTree([100, 2])
        sync_system_process_tree!(tree, read_system_processes([100, 2]; root); now = 2000.0)
        navigator = Navigator(tree)
        editor, backend = _nav_editor(navigator)
        label = format_tree_node_label(tree.roots[1])
        @test _nav_has_text(backend, "Processes of 100, 2") && _nav_has_text(backend, label)
        click = _nav_click(backend, label)
        @test click !== nothing
        _nav_press!(editor, backend, click, _doctree_double(click))
        @test get_navigator_page(navigator) === tree.roots[1]
        @test _nav_has_text(backend, "folder /home/x") && _nav_has_text(backend, "state sleeping")
        @test _nav_has_text(backend, "Interrupt") && _nav_has_text(backend, "Stop")
    end

    @testset "the buttons of the page say the signal that they send" begin
        process = SystemProcess(7, 1, "sleep 100", "/tmp", :sleeping, 1.0e9, nothing, 1024, 2, CellVector(), 0, nothing)
        page = print_document(SystemProcessToWidget(), nothing, process, nothing).output
        buttons = _find_widgets_below(page, WidgetButton)
        note(label) = _read_widget_note(only(button for button in buttons if button.action.label == label))
        @test (note("Interrupt").title, occursin("SIGINT", note("Interrupt").text)) == ("Interrupt", true)
        @test occursin("SIGTERM", note("Stop").text)
    end

    @testset "a process id with new start ticks is a new document, and a process that ended leaves" begin
        tree = SystemProcessTree([100, 2])
        sync_system_process_tree!(tree, read_system_processes([100, 2]; root = _sysproc_write(_sysproc_processes()));
                                  now = 2000.0)
        shell, sleeper, kernel = tree.roots[1], tree.roots[1].children[1], tree.roots[2]
        later = _sysproc_write(_sysproc_processes(; sleep_start = 6000, worker = false))
        sync_system_process_tree!(tree, read_system_processes([100, 2]; root = later); now = 2001.0)
        @test tree.roots[1] === shell && tree.roots[2] === kernel
        @test length(shell.children) == 1
        @test shell.children[1] !== sleeper && shell.children[1].start_ticks == 6000
        @test _sysproc_keys(tree) == [(100, 5000), (200, 6000), (2, 1)]
        # A new document has no load at its first sample; a known one has its load.
        @test shell.children[1].processor_load === nothing && shell.processor_load == 0.0
    end

    @testset "a sync with no change writes no cell" begin
        root = _sysproc_write(_sysproc_processes())
        records = read_system_processes([100]; root)
        tree = SystemProcessTree([100])
        sync_system_process_tree!(tree, records; now = 10.0)
        sync_system_process_tree!(tree, records; now = 11.0)
        processes = _sysproc_collect(tree)
        @test all(p -> p.processor_load == 0.0, processes)
        reads = Ref(0)
        readers = [Cell(@computation begin
                            reads[] += 1
                            (p.process_id, p.parent_process_id, p.command, p.folder, p.state, p.start_time,
                             p.processor_load, p.memory, p.thread_count, p.start_ticks, length(p.children))
                        end) for p in processes]
        push!(readers, Cell(@computation (reads[] += 1; length(tree.roots))))
        foreach(reader -> reader[], readers)
        @test reads[] == length(readers)
        times = Ref(0)
        time_reader = Cell(@computation (times[] += 1; tree.sampled_at))
        time_reader[]
        roots = getfield(tree, :roots)[]
        children = getfield(tree.roots[1], :children)[]
        sync_system_process_tree!(tree, records; now = 12.0)
        foreach(reader -> reader[], readers)
        @test reads[] == length(readers)
        @test getfield(tree, :roots)[] === roots && getfield(tree.roots[1], :children)[] === children
        # The time of the sample is the one cell that moves.
        @test time_reader[] == 12.0 && times[] == 2
        sync_system_process_tree!(tree, records; now = 12.0)
        @test time_reader[] == 12.0 && times[] == 2
        # The load is the processor time over the time between the samples.
        busy = read_system_processes([100]; root = _sysproc_write(_sysproc_processes(; sleep_ticks = 50)))
        sync_system_process_tree!(tree, busy; now = 14.0)
        @test tree.roots[1].children[1].processor_load ≈ 100 * 50 / ticks / 2
    end

    @testset "no reader, no read" begin
        tree = SystemProcessTree([getpid()])
        @test drain_system_process_tree!(tree; now = 100.0) == 0
        @test tree.sampler.reading === nothing
        @test compute_system_process_tree_deadline(tree; now = 100.0) === nothing
        feed = SystemProcessFeed()
        push!(feed.trees, tree)
        @test drain_changes!(feed, nothing) == 0 && compute_wake_deadline(feed, nothing) === nothing
        @test tree.sampler.reading === nothing
        # A view reads the roots: a drain starts a read, and a drain after it ends
        # syncs the read.
        view = Cell(@computation length(tree.roots))
        @test view[] == 0
        @test drain_system_process_tree!(tree; now = 100.0) == 0 && tree.sampler.reading !== nothing
        @test compute_system_process_tree_deadline(tree; now = 100.25) ≈ 0.75
        _sysproc_wait_read(tree)
        @test drain_system_process_tree!(tree; now = 100.5) == 1
        @test view[] == 1 && tree.roots[1].process_id == getpid()
        # No read starts again before the interval.
        @test tree.sampler.reading === nothing
        @test drain_system_process_tree!(tree; now = 101.0) == 0 && tree.sampler.reading !== nothing
        @test compute_wake_deadline(feed, nothing) isa Float64
        _sysproc_wait_read(tree)
    end

    @testset "a real tree of sleep shows, and a stopped process leaves it" begin
        process = run(Cmd(`bash -c 'sleep 30 & sleep 30'`; detach = true); wait = false)
        process_id = Int(getpid(process))
        tree = SystemProcessTree([process_id])
        try
            view = Cell(@computation length(tree.roots))
            view[]
            sleepers() = filter(p -> p.command == "sleep 30", _sysproc_collect(tree))
            @test _sysproc_drain_until(() -> length(sleepers()) == 2, tree)
            @test tree.roots[1].command == "bash -c sleep 30 & sleep 30"
            @test occursin("sleep 30", string(describe_system_process_tree([process_id])))
            stopped = first(sleepers())
            key = (stopped.process_id, stopped.start_ticks)
            @test stop_system_process!(stopped)
            @test _sysproc_drain_until(() -> !(key in _sysproc_keys(tree)), tree)
        finally
            ccall(:kill, Cint, (Cint, Cint), -process_id, Base.SIGKILL)
            timedwait(() -> !process_running(process), 10.0)
            _sysproc_wait_read(tree)
        end
    end

    @testset "a signal goes only to the process that the document shows" begin
        process = run(Cmd(`sleep 30`; detach = true); wait = false)
        process_id = Int(getpid(process))
        try
            records = read_system_processes([process_id])
            @test length(records) == 1
            tree = SystemProcessTree([process_id])
            sync_system_process_tree!(tree, records; now = time())
            document = tree.roots[1]
            # The process id started again, as a fixture folder says it.
            root = _sysproc_write([_sysproc_fixture(process_id, 1, "sleep", ["sleep", "30"];
                                                    start_ticks = document.start_ticks + 1)])
            @test !stop_system_process!(document; root)
            @test !interrupt_system_process!(document; root)
            sleep(0.2)
            @test process_running(process)
            @test stop_system_process!(document)
            @test timedwait(() -> !process_running(process), 10.0) === :ok
        finally
            process_running(process) && kill(process, Base.SIGKILL)
        end
    end

    @testset "the detail of a running task shows its process tree" begin
        group = wrap_task_group_document(
            TaskGroup([_TaskGroupProbeTask("sleeper", "sleep 30")]; name = "processes", jobs = 1))
        select_task_document!(group, 1)
        start_task_group_document!(group)
        task = only(getfield(group, :tasks)[])
        try
            deadline = time() + 10
            while get_task_document_status(task) !== :running && time() < deadline
                drain_task_feed!()
                sleep(0.05)
            end
            process_id = get_current_task_execution(task).process_id
            projection, iomap = _print_task_view(group)
            texts() = [t[3] for t in _collect_task_view_texts(iomap.output)]
            @test "Processes of $process_id" in texts()
            tree = getfield(task, :process_tree)[]
            @test tree isa SystemProcessTree && collect(tree.root_process_ids) == [process_id]
            while !any(startswith(string(process_id, "  ")), texts()) && time() < deadline
                drain_task_feed!()
                sleep(0.1)
            end
            @test any(startswith(string(process_id, "  ")), texts())
        finally
            stop_task_group_document!(group)
            wait_task_group_document(group)
        end
        @test getfield(task, :process_tree)[] === nothing
    end
end
end
