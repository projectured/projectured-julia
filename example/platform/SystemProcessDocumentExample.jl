# The system process example: the processes of an agent, read from a folder that
# the example writes as `/proc` lays it out, so the tree is the same on every
# machine and reads nothing of the machine. Two reads one second apart give each
# process a processor load.

# The boot time of the folder, in seconds since the epoch.
const _EXAMPLE_BOOT_TIME = 1_760_000_000

# The processes of the folder: an agent that runs the tests of a project through a
# shell and make, and the server of its tools. `ticks` is the processor time of the
# two reads, and `start_ticks` the start after the boot, in clock ticks. The
# process ids are above 4194304, the limit of the process ids of Linux, so
# Interrupt and Stop on the page of one of them reach no process of the machine.
const _EXAMPLE_PROCESSES = [
    (process_id = 5_100_000, parent = 1, name = "claude",
     arguments = ["claude", "--output-format", "stream-json"], state = 'S',
     threads = 14, start_ticks = 360_000, resident_pages = 76_800,
     ticks = (2_000, 2_005), children = [5_100_100, 5_100_300]),
    (process_id = 5_100_100, parent = 5_100_000, name = "bash",
     arguments = ["/bin/bash", "-c", "make test"], state = 'S',
     threads = 1, start_ticks = 450_000, resident_pages = 900,
     ticks = (3, 3), children = [5_100_200]),
    (process_id = 5_100_200, parent = 5_100_100, name = "make",
     arguments = ["make", "test"], state = 'S',
     threads = 1, start_ticks = 450_010, resident_pages = 600,
     ticks = (2, 2), children = [5_100_210]),
    (process_id = 5_100_210, parent = 5_100_200, name = "julia",
     arguments = ["julia", "--project", "test/runtests.jl"], state = 'R',
     threads = 4, start_ticks = 450_050, resident_pages = 131_072,
     ticks = (1_000, 1_090), children = Int[]),
    (process_id = 5_100_300, parent = 5_100_000, name = "node",
     arguments = ["node", "mcp-server.js"], state = 'S',
     threads = 7, start_ticks = 360_500, resident_pages = 20_000,
     ticks = (300, 302), children = Int[]),
]

# Write the processes into `root` with the processor ticks of the read `read`.
function _write_example_process_folder!(root::AbstractString, read::Int)
    write(joinpath(root, "stat"), "cpu  1 2 3 4\nbtime $(_EXAMPLE_BOOT_TIME)\n")
    for p in _EXAMPLE_PROCESSES
        id = p.process_id
        folder = mkpath(joinpath(root, string(id)))
        write(joinpath(folder, "stat"),
              "$id ($(p.name)) $(p.state) $(p.parent) $id $id 0 -1 4194304 0 0 0 0 " *
              "$(p.ticks[read]) 0 0 0 20 0 $(p.threads) 0 $(p.start_ticks) 1000 " *
              "$(p.resident_pages) 0\n")
        write(joinpath(folder, "statm"), "200 $(p.resident_pages) 10 5 0 20 0\n")
        write(joinpath(folder, "cmdline"), join(p.arguments, '\0') * '\0')
        cwd = joinpath(folder, "cwd")
        islink(cwd) || symlink("/home/user/parser", cwd)
        thread = mkpath(joinpath(folder, "task", string(id)))
        write(joinpath(thread, "children"), join(string.(p.children) .* " "))
    end
    root
end

# The tree of the processes of the agent, after two reads of a folder of its own
# in `tempdir()`, at fixed times.
function make_system_process_tree_document_example()
    root = mktempdir()
    tree = SystemProcessTree([5_100_000]; title = "Processes of claude", root)
    for read in 1:2
        _write_example_process_folder!(root, read)
        records = read_system_processes([5_100_000]; root)
        sync_system_process_tree!(tree, records;
                                  now = _EXAMPLE_BOOT_TIME + 4_600.0 + read)
    end
    tree
end

# The agent process of the tree, for the catalog: its page shows its facts and
# the buttons that interrupt and stop it.
make_system_process_document_example() =
    make_system_process_tree_document_example().roots[1]
