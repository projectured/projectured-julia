# Fragment of `DataFramesModule`.
#
# A data frame shown in an editor window beside the REPL. The editor runs on a
# task of its own, which `run_editor!(...; wait = false)` pins to a thread that
# is not the thread of the REPL. So the REPL keeps its speed, and the window
# stays live while an input runs.
#
# The loop of the editor keeps the world of its start: a function that the REPL
# defines later is too new for it. So every call that this file posts to the
# editor goes through `_call_latest`, a closure of this package that calls its
# function in the newest world.

"""
    ProjecturedDisplay()

A display that shows a data frame in an editor window, one tab for each frame.
The package pushes no display, so a value at the prompt prints as text, and only
an explicit call opens the editor: `display(ProjecturedDisplay(), df)`, or
[`display_in_editor`](@ref).
"""
struct ProjecturedDisplay <: AbstractDisplay end

Base.display(::ProjecturedDisplay, frame::AbstractDataFrame) =
    (display_in_editor(frame); nothing)

"""
    display_in_editor(frame; title = summary(frame), backend = nothing) -> DataFrameView

Show `frame` in the editor of this process: in the tab that shows it already,
else in a new tab. The first call starts the editor, and so does a call after
the window was closed. `title` names a new tab; a title that another tab has
gets a number. `backend` is for a test that runs without a window; `nothing` is
SDL.
"""
function display_in_editor(frame::AbstractDataFrame; title::AbstractString = summary(frame),
                           backend = nothing)
    lock(_SESSION_LOCK) do
        session = _SESSION[]
        if session !== nothing && !_is_session_alive(session)
            _close_session!(session)
            session = nothing
        end
        if session === nothing
            view = DataFrameView(frame)
            session = _start_session(view, String(title), backend)
            _SESSION[] = session
            session.tabs[frame] = String(title) => view
            return view
        end
        _show_in_session!(session, frame, String(title))
    end
end

"""
    close_data_frame_editor!() -> Nothing

Stop the editor that [`display_in_editor`](@ref) started, and wait for its loop
to end. Nothing happens when no editor runs.
"""
function close_data_frame_editor!()
    lock(_SESSION_LOCK) do
        session = _SESSION[]
        session === nothing || _close_session!(session)
        _SESSION[] = nothing
    end
    nothing
end

# ── The session ──────────────────────────────────────────────────────────────

# The editor of this process, the task of its loop, and the title of the tab and
# the view of each frame that it showed. A frame is the same frame by identity:
# two frames with equal rows are two tabs, and a lookup hashes no rows.
struct _EditorSession
    editor::Any
    loop::Task
    tabs::IdDict{AbstractDataFrame,Pair{String,DataFrameView}}
end

const _SESSION = Ref{Union{_EditorSession,Nothing}}(nothing)
const _SESSION_LOCK = ReentrantLock()

# A closure of this package, which is older than the loop, that calls `f` in the
# newest world.
_call_latest(f) = () -> Base.invokelatest(f)

_run_in_editor(f, session::_EditorSession) =
    run_on_editor_task!(_call_latest(f), session.editor)

# The loop runs, and the window is open. A closed window ends no loop, so a loop
# with no window is a session that a new display replaces.
_is_session_alive(session::_EditorSession) =
    !istaskdone(session.loop) &&
    _run_in_editor(() -> !isempty(session.editor.document.windows), session)

function _close_session!(session::_EditorSession)
    istaskdone(session.loop) && return nothing
    post_operation!(session.editor, QuitEditorOperation())
    wait(session.loop)
    nothing
end

# The editor with one window of tabs, the first of which shows `view`, built and
# run on a task of its own.
function _start_session(view::DataFrameView, title::String, backend)
    tree = PaneTree(PaneGroup([PaneTab(title, view)]))
    projection = ChainingProjection(RecursiveProjection(PaneToWidget()),
                                    NaturalToGraphics(; measure = FontFileMeasure()))
    editor = run_editor!(tree, projection; wait = false,
                         backend = something(backend, SdlBackend()),
                         window = (; title = "Data frames", width = 1000, height = 600))
    _EditorSession(editor, editor.loop_task, IdDict{AbstractDataFrame,Pair{String,DataFrameView}}())
end

function _show_in_session!(session::_EditorSession, frame::AbstractDataFrame, title::String)
    editor = session.editor
    shown = get(session.tabs, frame, nothing)
    if shown !== nothing
        tab = _run_in_editor(() -> find_pane(editor, first(shown)), session)
        if tab !== nothing
            _run_in_editor(() -> focus_pane!(editor, tab), session)
            return last(shown)
        end
    end
    unique = _make_unique_title(session, title)
    view = DataFrameView(frame)
    _run_in_editor(() -> open_pane!(editor, view; title = unique), session)
    session.tabs[frame] = unique => view
    view
end

# `title`, or `title` with the first number that no open tab has.
function _make_unique_title(session::_EditorSession, title::String)
    taken(name) = _run_in_editor(() -> find_pane(session.editor, name) !== nothing, session)
    taken(title) || return title
    number = 2
    while taken(string(title, " (", number, ")"))
        number += 1
    end
    string(title, " (", number, ")")
end
