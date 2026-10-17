# System processes

> **Kind:** design · **Status:** current · **Stands on:** [cell.md](../../kernel/cell.md), [tree.md](../tree/tree.md), [roster.md](../roster/roster.md), [widget.md](../widget/widget.md)

The system process slice of `ProjecturedPlatform` shows the processes of the operating system as documents: a tree of the processes below a set of roots, and a page for each process with its facts and the buttons Interrupt and Stop. This document says how a read of `/proc` becomes documents without a cost for a window that shows none, who drains a tree, how the page guards a signal, and what the slice needs from the system. Only Linux has `/proc`.

## How it works

### The read

`read_system_processes(root_process_ids; root = "/proc")` answers a `Vector{SystemProcessRecord}`: each root and its children at every depth, a parent before its children. A record is a plain value that no later read changes. The read writes nothing and runs on any task.

| Field of a record | Read from |
| --- | --- |
| `process_id`, `parent_process_id`, `state`, `thread_count`, `start_ticks`, `processor_ticks` | `<pid>/stat` |
| `memory` | the resident pages of `<pid>/statm`, in bytes |
| `command` | `<pid>/cmdline`; the name of a kernel thread in brackets when the command line is empty |
| `folder` | the link `<pid>/cwd`; empty when the reader may not see it |
| `children` | the file `children` of each thread in `<pid>/task/`, because a child that another thread started is listed only there |
| `start_time` | `btime` of `<root>/stat` plus `start_ticks` over the clock ticks of a second |

`start_ticks` is the start of the process after the boot, in clock ticks. With the process id it names one process, because the system gives a process id again only to a process that starts later. A process that ended during the read is left out, with the children that only it named. A folder with no `stat` file answers no record, as a missing folder does. The keyword `root` lets a test read a folder of fixed files.

`read_system_process_usage(process_id; root)` answers the processor ticks and the resident memory of one process, or `nothing`. `get_clock_ticks_per_second()` answers the clock ticks of a second. The task slice and this slice divide by it.

### The documents

`SystemProcess` is one process. Each field is a cell of its own, so a change of one fact writes one cell.

| Field | Meaning |
| --- | --- |
| `process_id`, `parent_process_id` | the process and its parent |
| `command`, `folder` | the command line and the working folder |
| `state` | `:running`, `:sleeping`, `:disk_wait`, `:stopped`, `:zombie`, `:idle` or `:other` |
| `start_time`, `start_ticks` | the start in seconds since 1970, and in clock ticks after the boot |
| `processor_load` | the processor time since the sample before, in percent of one processor; `nothing` at the first sample of the process |
| `memory`, `thread_count` | the resident memory in bytes, and the threads |
| `children` | a `CellVector` of `SystemProcess` |
| `sampled_at` | the time of the last sample of the tree |

`SystemProcessTree(root_process_ids; title, root)` holds the processes below a set of roots: `roots` is a `CellVector` of the roots that run, and each process holds its children. `sampler` holds the read that runs and what a load needs, and a walk of the documents does not enter it (`is_walk_opaque`). `sampled_at` of each process is the cell `sampled_at` of its tree itself, so one write moves the elapsed time of every process, and no view reads a clock.

### The sync keeps documents by their key

`sync_system_process_tree!(tree, records; now)` brings one read into the tree, on the editor task.

- **A document stays the document of its process.** The sync keeps it by the process id and the start ticks, and writes only the fields that changed. A process id with other start ticks is another process and gets a document of its own.
- **A process that is in no record has ended**, and leaves the tree.
- **A list stays the same list** while its members are the same documents in the same order. A sync with no change writes no cell but `sampled_at`, and a sync at the same time writes none.
- **The load** is the processor time since the sync before, over the time since then. The sync writes the time at which the read began, not the time of the drain, so the load and the elapsed time are those of the read.

### The read runs off the editor task

The editor task never reads `/proc`. `drain_system_process_tree!(tree; now, interval = 1.0)` does the step on the editor task:

1. When no view reads `roots` of the tree (`has_dependent_cells`), it does nothing. A tree that nobody looks at costs no read.
2. When a read ended, it takes the result from the sampler under its lock and syncs it.
3. When no read runs and `interval` seconds passed since the last start, it starts the next read on a task of the default pool (`Threads.@spawn :default`), never on the thread of the loop. The task writes only into the sampler, under its lock. A read that throws is a warning, and the next interval reads again.

A view shows a sample at most one interval old. `compute_system_process_tree_deadline` answers the seconds until the next sample, or `nothing` while no view reads the tree, so a window that shows no tree sleeps.

### The owner of a tree drains it

No registry of trees exists. Each owner drains its own trees from a feed that its window has already:

| Owner | Feed |
| --- | --- |
| `show_system_process_tree!` | `SystemProcessFeed`: the first tree adds one to `editor.feeds`, and the next trees reuse it |
| the tree of a running task | the feed of the tasks, `drain_task_feed!`, which finds the tree through the owner of each execution that changed; the sampler of the process writes the execution four times a second ([task.md](../task/task.md)) |
| the tree of the processes of an agent | the feed of the agent events ([assistant.md](../assistant/assistant.md)) |

The feed holds its trees strongly, because a tree is an immutable struct and a `WeakRef` to it does not hold its identity. A tree that no view reads costs one check in each drain.

### The views

A tree of processes draws as a tree of the tree slice. `SystemProcessTreeToDocumentTree` prints it as a `DocumentTree` whose root is the tree of processes, so a path of the tree is the same path below `root`. The label of a process node says the process id, the command, the load and the memory, and its icon is `:terminal`. A double click on a node opens the page of its process in a navigator ([tree.md](../tree/tree.md)).

A tree whose folder is not there says why in the text of its root node: "No /proc on this system: the processes can not be read." The text is the label of the root, so a leaf with no process under the root is not needed.

### The page of a process

`SystemProcessToWidget` prints a process as lines of facts: the process id and the command, the folder, the state, the start time and the time since it, the load, the memory and the threads. Each line reads only its cells, so a sample that changes the load draws one line again. Two buttons follow the lines:

- **Interrupt** calls `interrupt_system_process!`, which sends `SIGINT`, as Ctrl+C does.
- **Stop** calls `stop_system_process!`, which sends `SIGTERM`, which asks the process to end.

**The guard.** The system gives a process id again once its process ended. So a signal reads `start_ticks` of the process id from `<root>/<pid>/stat` first, and sends nothing when they differ from the start ticks of the document. A process that ended answers `false`. The keyword `root` is what a test of the guard sets to a folder of fixed files. The check and the send are two calls, so the guard narrows the risk and does not remove it.

### The roster source

`SystemProcesses(tree)` lists every process of a tree, at every depth, a parent before its children, as the rows of a roster. The row of a process holds its parent as `within`, and a root holds `nothing`. The tree is the one part, so a sample gathers the rows again.

`load` and `elapsed` are facets of `SystemProcess`; the other keys are its fields, such as `command` and `memory`.

```julia
Roster(SystemProcesses(tree); columns = ["process_id", "command", "load", "within.process_id"])
```

### What a file keeps

`pred_arguments` of a `SystemProcessTree` writes its title, its folder (`root`) and its process ids. A tree of the process of the editor writes that it shows that process (`editor_process`), and a loaded tree shows the process of the editor that loads it.

### The tree of a running task

The task slice makes a `SystemProcessTree` of the process of the current execution of a task, as the computed field `process_tree` of `TaskDocument`. The detail of the task shows it in a card while the task runs. A build or a simulation run shows its compilers or its workers, with no code in its domain.

### The verbs

`show_system_process_tree!(root_process_ids; title, editor)` shows the tree in a tab and answers it in its window. It runs through `run_on_editor_task!`, so any task can call it. `describe_system_process_tree(root_process_ids)` reads `/proc` once, on the task that calls it, because it reads no document, and answers a `Text`: a line for each process, indented under its parent, with the process id, the command, the state and the memory. A system with no `/proc` and a process id that does not run each get a sentence. Both verbs are declared to the assistant.

## Try it

```julia
using Projectured
show_system_process_tree!([getpid()]; title = "This session")     # a tab; updates once a second
describe_system_process_tree([getpid()])                           # the same, once, as text

records = read_system_processes([getpid()])                        # plain records
tree = SystemProcessTree([getpid()])
sync_system_process_tree!(tree, records)                           # documents, with no editor
```

A test reads a folder of fixed files: write `stat`, `statm`, `cmdline` and `task/<pid>/children` for each process, and `stat` with a `btime` line at the root, and pass the folder as `root`.

## How it fits

The slice uses the collection, focus, graphics, layout, projection, roster, style, tree and widget slices of the platform. It loads after `tree`, and the task, assistant and application slices use it.

The slice owns the only reader of `/proc` of the platform. The sampler of a process of the task slice, off the loop, calls `read_system_process_usage` through `sample_task_usage!`. `format_memory_size` is a function of this slice, because the label of a process needs it, and `ProjecturedPlatform` exports it.

## Design decisions

- **The read runs off the editor task, and the sync runs on it.** A read of many processes takes time, and a write of a cell must run on the editor task. The sampler is the only thing that the two tasks share, under a lock.
- **No view, no read.** A tree reads `/proc` only while a cell reads `roots`.
- **The owner drains.** The owner of a tree has a feed in its window already. A central registry of trees would need an owner of its own.
- **The process id and the start ticks are the key.** A process id alone names another process after the system gives it again.
- **The page guards its signals.** A button that sends a signal to a process id must not hit a process that started later.

The plan with the steps and the alternatives is [the-assistant-shows-the-work-of-its-agent.md](../../../../plan/done/the-assistant-shows-the-work-of-its-agent.md).

## Limits

- **Linux only.** macOS and Windows have no `/proc`. On another system a read answers no process, the tree is empty and its root says why, and `describe_system_process_tree` says that the system has no `/proc`.
- **One sample each second.** A process that starts and ends between two samples does not show. The load of a process is an average over the interval.
- **A process that the reader can not see is left out.** A process whose `stat`, `statm` or `cmdline` can not be read counts as gone.
- **No link from a background task to a system process.** No key joins them exactly, and a match by the text of a command is a guess.
- **A signal has a short race.** The guard checks the start ticks, and then the signal goes in a second call.

## Layer structure

The slice is the folder [source/platform/systemprocess/](../../../../source/platform/systemprocess/), and `SystemProcessModule` is its module.

```
systemprocess/SystemProcessModule.jl      (SystemProcessModule): the module, its exports and its include order
    ├─ SystemProcessRead.jl               : SystemProcessRecord, the read of /proc, the usage of one process
    ├─ SystemProcessDocument.jl           : SystemProcess, SystemProcessTree, the sampler, the nodes of a tree, the facets
    ├─ SystemProcessSignal.jl             : Interrupt and Stop, with the guard
    ├─ SystemProcessSync.jl               : the sync, the drain, the wake deadline, SystemProcessFeed
    ├─ SystemProcessTreeToDocumentTree.jl : a tree of processes as a DocumentTree
    ├─ SystemProcessToWidget.jl           : the page of a process
    ├─ SystemProcessRoster.jl             : SystemProcesses, the source of a roster
    └─ SystemProcessProgram.jl            : the two verbs
```

## Tests

`test_system_process()` in `ProjecturedPlatformTest`, in `test/platform/systemprocess/SystemProcessTest.jl`:

- a fixed `/proc` folder gives a known tree, and a missing folder says why the tree is empty;
- a process id with new start ticks is a new document, and a process that ended leaves;
- a sync with no change writes no cell;
- with no view that reads the tree, no read starts;
- a real tree of `sleep` shows, and a stopped process leaves it;
- a signal goes only to the process that the document shows;
- a tree draws in a navigator, and a node opens the page of its process;
- the detail of a running task shows its process tree.
