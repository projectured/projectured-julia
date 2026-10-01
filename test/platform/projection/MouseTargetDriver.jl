# A test driver that moves the pointer over a document, as the window of an
# editor does: it reads a move or a leave, and writes the answer at the root,
# where the part under the pointer is written by the chain of the mouse target.
# A content that draws and has no windows is the view of the window itself, so
# the driver does what the window does. A content that is a screen reads the
# input of its window itself.

struct MttDriver
    projection::Projection
    document::Any
    iomap::Any
end

# A driver over `document` drawn through `projection`: how a test of a widget
# moves the pointer.
MttDriver(projection::Projection, document) =
    MttDriver(projection, document, print_document(projection, document))

_mtt_apply!(driver, operation::CompoundOperation) =
    foreach(o -> _mtt_apply!(driver, o), operation.operations)
_mtt_apply!(driver, ::Nothing) = nothing
# A move names the part under the pointer, which the editor writes at its root.
_mtt_apply!(driver, operation::ReplaceMouseTargetOperation) =
    (replace_mouse_target!(driver.document, operation.path); nothing)
_mtt_apply!(driver, operation) = (evaluate_operation(nothing, operation); nothing)

# Read one input, and write its answer.
function _mtt_play!(driver::MttDriver, input)
    answer = read_intent(driver.projection, nothing, Intent(input), driver.iomap)
    _mtt_apply!(driver, answer isa Intent ? answer.operation : answer)
end

# A move and a leave of the window. On the view, the content reads the move and
# names the part under the pointer. Off it, the content reads the leave, and it
# holds no part under the pointer.
function _mtt_move!(driver, x, y, t)
    move = MouseMove(x, y; time = t)
    _mtt_is_window_view(driver) || return _mtt_play!(driver, WindowInput(:win, move))
    _mtt_is_on_view(driver.iomap, x, y) || return _mtt_leave_view!(driver, move)
    _mtt_apply!(driver, read_child_move(driver.iomap, move))
end

function _mtt_leave!(driver, t)
    _mtt_is_window_view(driver) ||
        return _mtt_play!(driver, WindowInput(:win, WindowLeave(; time = t)))
    _mtt_leave_view!(driver, MouseMove(-1, -1; time = t))
end

function _mtt_leave_view!(driver, move)
    _mtt_apply!(driver, read_child_leave(driver.iomap, move, 0, 0))
    replace_mouse_target!(driver.document, nothing)
    nothing
end

_mtt_is_window_view(driver) = !hasproperty(driver.document, :windows) &&
    unwrap_cell(get_iomap_output(driver.iomap)) isa GraphicsDocument

# Whether `(x, y)` is on the canvas that `iomap` draws; a canvas with no size
# leaves it to the content.
function _mtt_is_on_view(iomap, x, y)
    canvas = unwrap_cell(get_iomap_output(iomap))
    canvas isa GraphicsCanvas || return true
    (Int(canvas.w) <= 0 || Int(canvas.h) <= 0) && return true
    0 <= x < Int(canvas.w) && 0 <= y < Int(canvas.h)
end
