# Fragment of `CellModule` — the check of the writer of a cell. While an editor runs
# its loop, only the task that owns its cells writes a cell that a computation
# reads: the task of the loop, or the task of a code unit while it runs. A write
# from another task races the owner, and the check records it.

"""
    ForeignCellWriteException(task, cell_type)

A task that does not own the cells wrote a cell of type `cell_type` that a
computation reads, while an editor ran its loop. The write races the owner of the
cells. An editor records it as a fault, whose message names the task.

The fix is in the task that wrote: it posts its write to the editor with
`run_on_editor_task!`, or it calls a verb that does.
"""
struct ForeignCellWriteException <: Exception
    task::Task
    cell_type::Type
end

Base.showerror(io::IO, exception::ForeignCellWriteException) =
    print(io, "ForeignCellWriteException: the task ", exception.task, " wrote a ",
          exception.cell_type, " that a computation reads, and that task does not own ",
          "the cells. Post the write with `run_on_editor_task!`.")

# The owner tasks of the running editors. The check reads the list with one atomic
# load; an add or a remove makes a new list under the lock, which happens only at
# the start and the end of a loop or of a code unit.
mutable struct _CellWriters
    @atomic tasks::Vector{Task}
end

const _CELL_WRITERS = _CellWriters(Task[])
const _CELL_WRITERS_LOCK = ReentrantLock()

# The foreign writes that the check found and no editor took yet: at most one for
# each task, and at most `_FOREIGN_WRITE_LIMIT` in all.
const _FOREIGN_WRITES = ForeignCellWriteException[]
const _FOREIGN_WRITES_LOCK = ReentrantLock()
const _FOREIGN_WRITE_LIMIT = 64

"""
    add_cell_writer!(task) -> Nothing

Let `task` write the cells that computations read: the task of the loop of an
editor from the start of the loop, and the task of a code unit while it runs.
While at least one task may write, a write from any other task to such a cell is
recorded as a [`ForeignCellWriteException`](@ref). With no task, nothing is
checked.
"""
function add_cell_writer!(task::Task)
    lock(_CELL_WRITERS_LOCK) do
        tasks = @atomic _CELL_WRITERS.tasks
        task in tasks || (@atomic _CELL_WRITERS.tasks = Task[tasks; task])
    end
    nothing
end

"""
    remove_cell_writer!(task) -> Nothing

End what [`add_cell_writer!`](@ref) allowed `task`.
"""
function remove_cell_writer!(task::Task)
    lock(_CELL_WRITERS_LOCK) do
        tasks = @atomic _CELL_WRITERS.tasks
        @atomic _CELL_WRITERS.tasks = Task[other for other in tasks if other !== task]
    end
    nothing
end

"""
    take_foreign_cell_writes!() -> Vector{ForeignCellWriteException}

The foreign writes that the check found since the last call, oldest first, and
empty the list. An editor takes them once in each frame and records each one as a
fault. The list is one for the process, because a cell does not know its editor.
"""
function take_foreign_cell_writes!()
    lock(_FOREIGN_WRITES_LOCK) do
        writes = copy(_FOREIGN_WRITES)
        empty!(_FOREIGN_WRITES)
        writes
    end
end

# The check at each write of a reactive cell, and at each store of a computed
# value. With no owner, it is one atomic load. An owner passes at one comparison
# for each running editor. Another task that writes a cell with a reader is
# recorded.
@inline function _check_cell_writer(c::ReactiveCell)
    tasks = @atomic _CELL_WRITERS.tasks
    isempty(tasks) && return nothing
    task = current_task()
    for allowed in tasks
        allowed === task && return nothing
    end
    _record_foreign_write!(c, task)
end

# A cell that no computation reads is not checked, such as a cell of a document
# that a task builds before it posts it. Each task is recorded once.
@noinline function _record_foreign_write!(c::ReactiveCell, task::Task)
    dependents = c.dependents
    (dependents === nothing || isempty(dependents)) && return nothing
    lock(_FOREIGN_WRITES_LOCK) do
        length(_FOREIGN_WRITES) < _FOREIGN_WRITE_LIMIT &&
            !any(write -> write.task === task, _FOREIGN_WRITES) &&
            push!(_FOREIGN_WRITES, ForeignCellWriteException(task, typeof(c)))
    end
    nothing
end
