# Fragment of `EditorModule` — the `Editor`, its constructor, and the hooks it answers.

"""
    Editor(document, projection; backend, devices = Device[Display(), Keyboard(), Mouse()],
           clock = Clock(), tools = ToolSet(), faults = FaultStore(),
           fault_policy = make_strict_fault_policy(), feeds = Feed[])

Holds the state for a read-eval-print loop:
  - `document`   — the reactive document being edited
  - `projection` — the projection (or a chaining projection)
  - `backend`    — the display/input backend
  - `devices`    — input/output devices (e.g. display, keyboard)
  - `clock`      — this editor's private animation clock (fresh `Clock()` by
                   default); `run_editor!` ticks it once per frame from OS
                   time so subscribers reanimate, independently of any other
                   editor running in the same process.
  - `tools`      — what *this* editor exposes to an agent: the `ToolSet` an agent
                   loop drives and an agent server publishes. Empty by default;
                   `register_default_tools!(editor.tools)` fills it with the
                   built-ins on first use. Per editor, so two editors in one
                   process neither share a tool list nor evaluate code into each
                   other's namespace.
  - `inbox`      — operations posted from outside this editor's task; drained and
                   applied once per frame by `run_editor!`. See
                   [`post_operation!`](@ref).
  - `iomap`      — the latest IoMap from the printer (internal)
  - `operation`  — the latest operation from the reader (internal)
  - `faults`     — the per-editor `FaultStore` every barrier writes to, and the
                   frame drains once. Per editor, so two editors in one process
                   never read each other's faults.
  - `fault_policy` — what this editor does with a fault. **It starts strict: a
                   barrier catches nothing.** An editor that a test builds with
                   `Editor(…)` therefore behaves exactly as it does without
                   this feature, and a broken projection fails its test rather
                   than passing quietly. [`make_editor`](@ref) and
                   [`build_editor`](@ref) start strict too; a program that a
                   person starts passes `FaultPolicy()`, because a loop that a
                   person sits in front of must survive. [`run_editor!`](@ref)
                   keeps the policy of its editor.
  - `replaced_projection` — the projection the safe mode put aside, or
                   `nothing` when the editor is not in the safe mode.
  - `noted_barriers` — the fault barriers that took a fault since the last
                   frame. The printer context carries it under
                   `:noted_barriers`, a barrier puts itself on it from inside a
                   computation, and the next frame shows the mark of each one
                   ([`show_barrier_mark!`](@ref)) (internal).
  - `marked_barriers` — the fault barriers that show a mark, held weakly, so a
                   part that is printed no more is not kept. The editor tries
                   each one again after an operation
                   ([`retry_barrier_print!`](@ref)) (internal).
  - `is_retry_pending` — an operation was applied since the editor last tried
                   the marks (internal).
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
  - `timers`     — the timers that readers set with `SetTimerOperation`: the
                   time of each, by its name. The loop wakes at the earliest,
                   and [`run_read_stage!`](@ref) reads a `TimerExpire` for each one whose
                   time has come (internal).
  - `stop_steps` — the functions `editor -> nothing` that run when the loop of
                   [`run_editor!`](@ref) ends, such as the removal of a log
                   capture that a wrapper of [`build_editor`](@ref) installed.
                   An editor whose loop never runs never runs them.
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
    faults::FaultStore
    fault_policy::FaultPolicy
    replaced_projection::Union{Projection, Nothing}
    noted_barriers::Vector{Any}
    marked_barriers::Vector{WeakRef}
    is_retry_pending::Bool
    feeds::Vector{Feed}
    wake_pending::Threads.Atomic{Bool}
    frame_measurements::FrameMeasurementStore
    loop_task::Union{Task, Nothing}
    timers::Dict{Symbol, Float64}
    stop_steps::Vector{Any}
end

# The inbox is bounded: a producer that outruns the editor should wait for it,
# not build a queue of syncs that are stale by the time they are applied.
const INBOX_CAPACITY = 64

# The devices of an editor when the caller names none: a display, a keyboard
# and a mouse, made new for each editor.
_make_default_devices() = Device[Display(), Keyboard(), Mouse()]

# The document and the projection are what the editor edits and how it shows
# it, as in `make_editor`; the backend, the devices and the services of the
# editor take names.
function Editor(document, projection; backend::Backend,
                devices::Vector{Device} = _make_default_devices(),
                clock::Clock = Clock(), tools::ToolSet = ToolSet(),
                faults::FaultStore = FaultStore(),
                fault_policy::FaultPolicy = make_strict_fault_policy(),
                feeds::Vector{Feed} = Feed[])
    editor = Editor(backend, document, projection, devices, clock, tools,
                    Channel{Operation}(INBOX_CAPACITY),
                    nothing, nothing, faults, fault_policy, nothing,
                    Any[], WeakRef[], false,
                    # The wake starts pending: the first frame runs before the
                    # first wait, so the editor paints once before anything
                    # has happened.
                    Feed[InboxFeed(); feeds], Threads.Atomic{Bool}(true),
                    FrameMeasurementStore(), nothing, Dict{Symbol, Float64}(), Any[])
    # Registration is the one moment a feed meets its editor. The callback is
    # the only handle a producer-side store gets: a store lives below the
    # editor layer and must not name `Editor`.
    wake = () -> wake_editor!(editor)
    for feed in editor.feeds
        attach_wake_callback!(feed, wake)
    end
    # The fault store wakes the same way: a fault recorded while the editor
    # sleeps — or during the frame, from inside a computation — reaches the log on
    # the very next frame rather than on the next unrelated event.
    attach_fault_wake!(faults, wake)
    editor
end

# A timer set again under the same name replaces the one before.
function OperationModule.evaluate_operation(editor::Editor, operation::SetTimerOperation)
    editor.timers[operation.name] = operation.time
    nothing
end

# Drop the cached IoMap so the next `run_print_stage!` rebuilds the projection from
# scratch.
# `invalidate_projection!` is a no-op for an object that caches nothing; this method
# is what an operation like a whole-root `ReplaceReferencedValueOperation` swap
# actually reaches when it runs against a real `Editor`.
# A print from the start makes every barrier new, so the barriers of the IoMap
# that goes are forgotten with it.
function OperationModule.invalidate_projection!(editor::Editor)
    editor.iomap = nothing
    empty!(editor.noted_barriers)
    empty!(editor.marked_barriers)
    nothing
end

# An editor is where a model reads a reference from: its document, read at the
# call, so a reference is read from the document the editor holds now and not
# from one that it replaced.
ReferenceModule.get_parent(editor::Editor, x::Union{Reference, ReferencedDocument}) =
    get_parent(editor.document, x)
ReferenceModule.find_referenced_document(locator::DocumentLocator{<:Editor}) =
    find_referenced_document(DocumentLocator(locator.start.document, locator.reference))

# An editor is what keeps faults, and this is how code that holds one without
# being able to name its type reaches them. The kernel's agent layer drives a
# tool against a target it knows only as `Any`.
FaultModule.get_fault_store(editor::Editor) = editor.faults
