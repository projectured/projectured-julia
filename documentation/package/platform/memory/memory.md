# Memory

> **Kind:** design · **For:** developer · **Status:** current · **Stands on:** [cell.md](../../kernel/cell.md)

`MemoryModule` is the slice of the platform that says what holds the memory of an editor. `compute_held_memory(root)` walks the objects that `root` reaches through strong references, and gives the bytes that each holder keeps, with the path of the holder from the root. `describe_held_memory()` gives the same report as text for the editor of the session, as a verb of the assistant.

```julia
report = compute_held_memory(editor)
report.total_bytes             # the bytes that the editor reaches
report.object_count            # the count of those objects
first(report.holders)          # MemoryHolder(".document…navigator.back", Vector{NavigatorVisit}, bytes, count)
first(report.types)            # HeldType(ReactiveCell{Any}, bytes, count): the bytes of each type
println(describe_held_memory())
```

## Why it is so

The memory of a long editor session grows, and a reading of the code can find a store that keeps too much, but it can not say how much each store keeps. A heap snapshot of the process (`Profile.take_heap_snapshot`) holds the whole process, names no field of a document, and needs a second tool to read it. The report names the fields of the documents, and the IDE can run it.

**A holder keeps an object when every path from the root to the object goes through the holder.** This is the immediate dominator of the object in the graph of the walk. So no object counts two times, and a growth goes to the store that keeps it. The first path of a breadth-first walk would name a holder that another path also passes, and a removal of that holder could free nothing. The dominators come from the iterative algorithm of Cooper, Harvey and Kennedy ("A Simple, Fast Dominance Algorithm", 2001).

## How it works

The walk is breadth-first from the root. It gives each object one number, so the root is 1, and the object that the walk reached an object from first has a smaller number. It keeps, for each object, the object, its own bytes, that first object, its type, and its edges. The address of each object finds its number while the walk runs.

- **What the walk follows.** Each pointer of an object, as `Base.summarysize` follows them (`Base.datatype_npointers`, `Base.get_nth_pointer`), so it follows the pointers of every kind of object. It does not follow the value of a `WeakRef`. It does not walk into a module, a type, a method or compiled code: each counts by its own size, and a module counts no bytes. Their total is `unwalked_bytes`. It walks into a `Task` through `code`, `result` and `storage` only, and into a closure through its captured fields. A symbol and a value of a type with one value, such as `nothing`, belong to no holder.
- **The bytes of an object** are those that `Base.summarysize` counts: a string its length and one word, a memory its data and two words, a list its own struct, and any other object `Core.sizeof`.
- **The holders.** The dominators are computed in reverse postorder of a depth-first walk of the edges. The holder of an object has a smaller number than the object, because every path to the object passes the holder, and the shortest path too. So one pass from the last object to the first adds the bytes of each object to its holder.
- **The lines of the report.** A holder is listed when it keeps at least `minimum_bytes` or the share `minimum_share` of the total, and no object below it keeps 90 % of its bytes. So a line names a store and not each object on the path to it. The memory that holds the elements of a list or of a dictionary is a part of its owner: the line names the list, and the largest part of the list is its largest element.
- **The path of a holder** is the shortest path from the root, along the objects that the walk reached each object from first. A step is the name of a field, `.back`, or an index of a list, `[3]`. A field of a cell, a `Core.Box` of a captured variable, and the memory of a list or a dictionary give no step. An entry of a dictionary gives the step of its key when the key is a string, a symbol, a number or a type, `["name"]`, and otherwise the type of its key with a mark of the identity of the key, `[#3fa91c JsonObject]`; its key adds `.key`. The place of the entry in its table would change when the table grows, and with it the path of each holder below, so two reports could not be compared. The mark stays while the key lives. The walk reads no interface of a document, so it can not make a view or compute a cell, and a list document shows its storage: `.elements[3]`.

## What it costs

The walk holds the process for its time. `walk_bytes` of a report gives the bytes of the tables at their largest.

| Root | Objects | Edges | Time | Tables, for each object | Allocated, for each object |
| --- | --- | --- | --- | --- | --- |
| a synthetic graph of cells, structs and lists | 5.0 million | | 4.8 s | 86 bytes | 253 bytes |
| the window of the memory test after 3 cycles, a second report | 1.9 million | 10.7 million | 4.9 s, of which the walk 2.0 s and the dominators 0.9 s | 121 bytes | 372 bytes |
| the window of the memory test after 130 cycles | 56.3 million | | 120 s | 92 bytes | |

The tables double as they grow, so the walk allocates more than they hold. The first report of a process also compiles the code of the walk: 24 s of the first 30 s. So the assistant runs `describe_held_memory` only when the person asks.

## How it fits

The source is `source/platform/memory/`: `MemoryModule.jl`, the walk in `MemoryGraph.jl`, the dominators in `MemoryDominators.jl`, and the report with the verb in `HeldMemory.jl`. The slice uses no other slice (`PLATFORM_SLICE_EDGES`), and three modules of the kernel: `CellModule`, `AgentModule` for `run_on_editor_task!`, and `ToolModule` for `get_evaluation_editor`.

## Tests

- `test_held_memory()` of `ProjecturedPlatformTest`: the walk on small graphs whose bytes are known: a chain, a diamond, a weak reference, a cycle, closures, lists, dictionaries, a cell, a task, a type and a module.
- The case "read: what holds the memory of the window" of `test_assistant_verbs()`: the report of a window, and the verb through the code of the assistant.
- `test_editor_memory_cycle()` of `ProjecturedTest`, a slow part: one cycle of gestures runs 230 times in one window, and no holder grows in each cycle, but the known growths (testing guide).
