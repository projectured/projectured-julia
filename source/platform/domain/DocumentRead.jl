# Fragment of `DomainModule` — the read of outside state for a document, such as
# the listing of a folder, on a task of its own: a print reads only what the
# document holds, and an operation that starts a read gets its answer back as
# another operation.

"""
    DOCUMENT_READ_WAIT

How long, in seconds, [`start_document_read!`](@ref) waits for a read before it
lets the document show what it holds meanwhile: a read that ends inside the wait
is in the first frame, such as the listing of a small folder.
"""
const DOCUMENT_READ_WAIT = 0.05

"""
    start_document_read!(editor, read, apply; wait = DOCUMENT_READ_WAIT) -> Task or nothing

Run `read()` on a task of its own, off the loop, and apply its answer to the
document: `apply(answer)` is the operation that writes the answer, and the editor
evaluates it. The answer is the value of `read`, or the exception that it threw,
so `apply` also writes a failure, such as a folder that a person may not read.

The call waits for the read at most `wait` seconds. A read that ends inside the
wait is applied at once, in the evaluation that started it, and the answer is
`nothing`. A longer read posts its operation to the editor when it ends
([`post_operation!`](@ref)), so the next frame applies it, and the answer is the
task of the read; the document shows what it holds meanwhile, such as a reading
marker. A read whose editor ended applies nothing. An editor that is not an
`Editor`, such as the stand-in of a test, runs the read at once on the calling
task. It runs in the evaluation of an operation, such as an acquire, and never in
a print.
"""
function start_document_read!(editor, read, apply; wait::Real = DOCUMENT_READ_WAIT)
    if !(editor isa Editor)
        evaluate_operation(editor, apply(_run_document_read(read)))
        return nothing
    end
    task = Threads.@spawn _run_document_read(read)
    if timedwait(() -> istaskdone(task), wait; pollint = 0.001) === :ok
        evaluate_operation(editor, apply(fetch(task)))
        return nothing
    end
    errormonitor(@async _post_document_read!(editor, apply, fetch(task)))
    task
end

# The answer of `read`: its value, or the exception that it threw. An exception
# that means stop goes on.
function _run_document_read(read)
    try
        read()
    catch exception
        is_fault_exception(exception) || rethrow()
        exception
    end
end

# Post the operation of an answer that came after the wait; an editor whose loop
# ended takes no post.
function _post_document_read!(editor, apply, answer)
    try
        post_operation!(editor, apply(answer))
    catch exception
        exception isa InvalidStateException || rethrow()
    end
    nothing
end
