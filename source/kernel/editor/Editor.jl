# Fragment of `EditorModule` — the `Editor` itself: the struct, its construction, the projection invalidation hook, and the editor as the start of a reference.

"""
    Editor(backend, document, projection, devices;
           clock = Clock(), tools = ToolSet(), feeds = Feed[])

Holds the state for a read-eval-print loop:
  - `backend`    — the display/input backend (e.g. SdlBackend)
  - `document`   — the reactive document being edited
  - `projection` — the projection (or a chaining projection)
  - `devices`    — input/output devices (e.g. display, keyboard)
  - `clock`      — this editor's private animation clock (fresh `Clock()` by
                   default); `run_editor!` ticks it once per frame from OS
                   time so subscribers reanimate, independently of any other
                   editor running in the same process.
  - `tools`      — what *this* editor exposes to an agent: the `ToolSet` an agent
                   loop drives and an MCP server publishes. Empty by default;
                   `register_default_tools!(editor.tools)` fills it with the
                   built-ins on first use. Per editor, so two editors in one
                   process neither share a tool list nor evaluate code into each
                   other's namespace.
  - `inbox`      — operations posted from outside this editor's task; drained and
                   applied once per frame by `run_editor!`. See
                   [`post_operation!`](@ref).
  - `iomap`      — the latest IoMap from the printer (internal)
  - `operation`  — the latest operation from the reader (internal)
  - `recognizer` — the event → gesture recogniser (internal)
  - `faults`     — the per-editor `FaultStore` every barrier writes to, and the
                   frame drains once. Per editor, so two editors in one process
                   never read each other's faults.
  - `fault_policy` — what this editor does with a fault. **It starts strict: a
                   barrier catches nothing.** A programmatic editor — every one
                   a test builds — therefore behaves exactly as it does without
                   this feature, and a broken projection fails its test rather
                   than passing quietly. [`run_editor!`](@ref) is what turns the
                   barriers on, because a loop a person is sitting in front of
                   is the thing that must survive.
  - `replaced_projection` — the projection the safe mode put aside, or
                   `nothing` when the editor is not in the safe mode.
  - `feeds`      — the registered inflows, drained once per frame by
                   [`drain_feeds!`](@ref). The built-in [`InboxFeed`](@ref) is
                   always first; the rest is given at construction and fixed
                   from then on.
  - `wake_pending` — set by [`wake_editor!`](@ref) from any task; each frame
                   takes ownership of every wake posted before it (internal).
  - `frame_measurements` — the `FrameMeasurementStore` that keeps the
                   measurements of the last frames: always the frame time,
                   plus the performance counters when they are compiled in. A
                   statistics feed flushes it into a document on its own
                   deadline.
  - `loop_task`  — the task that runs [`run_editor!`](@ref), or `nothing` while
                   no loop runs. [`run_on_editor_task!`](@ref) reads it to
                   know whether a call from another task must wait for a frame
                   (internal).
"""
mutable struct Editor
    backend::Backend
    document::Document
    projection::Projection
    devices::Vector{Device}
    clock::Clock
    tools::ToolSet
    inbox::Channel{Operation}
    iomap::Union{IoMap, Nothing}
    operation::Union{Operation, Nothing}
    recognizer::GestureRecognizer
    faults::FaultStore
    fault_policy::FaultPolicy
    replaced_projection::Union{Projection, Nothing}
    feeds::Vector{Feed}
    wake_pending::Threads.Atomic{Bool}
    frame_measurements::FrameMeasurementStore
    loop_task::Union{Task, Nothing}
end

# The inbox is bounded: a producer that outruns the editor should wait for it,
# not build a queue of syncs that are stale by the time they are applied.
const INBOX_CAPACITY = 64

# @positional: what an editor is made of, in the order of the layers: the backend,
# the document, the projection it draws through, and the devices it reads.
function Editor(backend, document, projection, devices;
                clock::Clock = Clock(), tools::ToolSet = ToolSet(),
                faults::FaultStore = FaultStore(),
                fault_policy::FaultPolicy = make_strict_fault_policy(),
                feeds::Vector{Feed} = Feed[])
    editor = Editor(backend, document, projection, devices, clock, tools,
                    Channel{Operation}(INBOX_CAPACITY),
                    nothing, nothing, GestureRecognizer(), faults, fault_policy, nothing,
                    # The wake starts pending: the first frame runs before the
                    # first wait, so the editor paints once before anything
                    # has happened.
                    Feed[InboxFeed(); feeds], Threads.Atomic{Bool}(true),
                    FrameMeasurementStore(), nothing)
    # Registration is the one moment a feed meets its editor. The callback is
    # the only handle a producer-side store gets: a store lives below the
    # editor layer and must not name `Editor`.
    wake = () -> wake_editor!(editor)
    for feed in editor.feeds
        attach_wake_callback!(feed, wake)
    end
    # The fault store wakes the same way: a fault recorded while the editor
    # sleeps — or during the frame, from inside a thunk — reaches the log on
    # the very next frame rather than on the next unrelated event.
    attach_fault_wake!(faults, wake)
    editor
end

# Drop the cached IoMap so the next `print!` rebuilds the projection from scratch.
# `invalidate_projection!` is a no-op for an object that caches nothing; this method
# is what an operation like a whole-root `ReplaceReferencedValueOperation` swap
# actually reaches when it runs against a real `Editor`.
OperationModule.invalidate_projection!(editor::Editor) = (editor.iomap = nothing)

# An editor is where a model reads a reference from: its document, read at the
# call, so a reference is read from the document the editor holds now and not
# from one that it replaced.
ReferenceModule.get_parent(editor::Editor, x::Union{Reference, ReferencedDocument}) =
    get_parent(editor.document, x)
ReferenceModule.find_referenced_document(locator::DocumentLocator{<:Editor}) =
    find_referenced_document(DocumentLocator(locator.start.document, locator.reference))
