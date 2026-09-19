# Fragment of `EditorModule` — the inbox: the one operation door into a running editor, and the wake that ends its wait.

# ── The inbox ─────────────────────────────────────────────────────────
#
# The one door into a running editor from outside its own task. A frame reads the
# document, evaluates against it and paints it, so anything that writes it from
# another task races the frame — and a reactive thunk cannot write at all
# (PAR-NO-WRITE-IN-THUNK). An operation posted here is applied by the editor's own
# task at a defined point in the frame, which is the same guarantee an operation
# from the reader already has.

"""
    post_operation!(editor, operation) -> operation

Hand `editor` an operation to apply on its next frame. Thread-safe, and the only
supported way for anything outside the editor's task — a driver advancing a
simulation, a file watcher, an agent, a timer — to change what it shows.

Blocks once `INBOX_CAPACITY` operations are waiting, so a producer faster than
the editor is slowed down rather than allowed to queue work that will be stale
before it is applied.

Wakes the editor after the `put!`, so a posted operation is applied on the
next frame rather than on the next tick of a timer.
"""
post_operation!(editor::Editor, operation::Operation) =
    (put!(editor.inbox, operation); wake_editor!(editor); operation)

"""
    wake_editor!(editor) -> Nothing

Ask `editor` to run a frame now. Thread-safe, non-blocking and coalescing:
any number of calls before the next frame cost one frame, because the frame
takes the whole flag at once. [`post_operation!`](@ref) calls it after
`put!`; a feed's producer-side store calls it through the callback
[`attach_wake_callback!`](@ref) gave it.

The flag is the truth and the backend wake is only the kick that ends a wait
in progress. Only the false-to-true transition kicks, so the backend holds at
most one pending wake however often producers call this. A kick a frame
happens to consume costs nothing: the flag still skips the next wait.
"""
function wake_editor!(editor::Editor)
    Threads.atomic_xchg!(editor.wake_pending, true) && return nothing
    wake_backend!(editor.backend)
    nothing
end

"""
    drain_operations!(editor) -> Int

Apply every operation waiting in the inbox and answer how many there were.
Called once per frame by `run_editor!`, before `read!`, so the frame paints what
it just applied.

Applied through `evaluate_operation` rather than [`evaluate!`](@ref): posted
operations do not become `editor.operation`, because that field means "what the
reader made of this frame's input" and is what `perf!` uses to tell a frame in
which the user did something from an idle one. It also keeps a sync arriving ten
times a second out of the operation log.
"""
function drain_operations!(editor::Editor)
    count = 0
    while isready(editor.inbox)
        evaluate_operation(editor, take!(editor.inbox))
        count += 1
    end
    count
end
