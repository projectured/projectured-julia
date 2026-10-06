# Fragment of `DisplayModule` — a value shown in an editor window beside the
# REPL.
#
# The loop of the editor keeps the world of its start: a function that the REPL
# defines later is too new for it. So every call that this file posts to the
# editor goes through `_call_latest`, a closure of this package that calls its
# function in the newest world.

"""
    EditorDisplay()

A display that shows a value in an editor window. This slice pushes no
display, so a value at the prompt prints as text, and only an explicit call
opens the editor: `display(EditorDisplay(), value)`, or
[`display_in_editor`](@ref).
"""
struct EditorDisplay <: AbstractDisplay end

Base.display(::EditorDisplay, value) = (display_in_editor(value); nothing)

"""
    display_in_editor(value; title = summary(value), backend = nothing,
                      tabs = true, refresh_every = nothing) -> document

Show `value` in the editor of this process, and answer its document: the
document that `make_value_document` makes for it, in the tab or the window that
shows it already, else in a new one. A value of a type that no loaded package
gives a document is an error.

The first call starts the editor, and so does a call after its window was
closed. With no `backend`, the one loaded backend that draws windows runs it.
Each value is a tab of one window, because the pane slice of
`ProjecturedPlatform` is always loaded with this one. The window has the
features of a window of the platform around its tabs: the chrome with the menu
bar, the toolbar and the status bar, the undo, the clipboard and the walk, F1
help, the command palette, and the gesture log, the message log, the statistics
and the fault log, which fill the tools of the toolbar. While the window is
open, the message log also collects what the REPL logs, which the REPL still
prints. `tabs = false` gives each value a window of its own instead, with none
of these features, because they act on the tabs. `backend` and `tabs` apply when the
call starts the editor. `title` names a new tab or window; a title that the
editor has already gets a number.

A value that a program changes in place, such as a data frame that gets a row,
shows the change after [`refresh_display_editor!`](@ref). With `refresh_every`,
a number of seconds, the editor that the call starts also reads every shown
value again at that interval; it is off by default, because a program that
writes a value while the editor reads it races the editor.

The editor logs only warnings and errors, so an operation in its window writes
no line to the REPL.
"""
function display_in_editor(value; title::AbstractString = summary(value), backend = nothing,
                           tabs::Bool = true, refresh_every::Union{Nothing,Real} = nothing)
    hasmethod(make_value_document, Tuple{typeof(value)}) ||
        error("No loaded package shows a value of type ", typeof(value), " in an editor: ",
              "none adds a method of make_value_document for it.")
    lock(_SESSION_LOCK) do
        session = _SESSION[]
        if session !== nothing && !_is_session_alive(session)
            _close_session!(session)
            session = nothing
        end
        if session === nothing
            document = make_value_document(value)
            session = _start_session(document, String(title); backend, tabs, refresh_every)
            _SESSION[] = session
            _remember!(session, value, String(title), document)
            return document
        end
        _show_in_session!(session, value, String(title))
    end
end

"""
    close_display_editor!() -> Nothing

Stop the editor that [`display_in_editor`](@ref) started, and wait for its loop
to end. Nothing happens when no editor runs.
"""
function close_display_editor!()
    lock(_SESSION_LOCK) do
        session = _SESSION[]
        session === nothing || _close_session!(session)
        _SESSION[] = nothing
    end
    nothing
end

"""
    refresh_display_editor!() -> Nothing

Read again every value that the editor of [`display_in_editor`](@ref) shows,
after a program changed it in place: each shown document with a method of
`refresh_document!` reads its value again, and the call waits until the editor
did it. Nothing happens when no editor runs.
"""
function refresh_display_editor!()
    session = lock(() -> _SESSION[], _SESSION_LOCK)
    session === nothing || _refresh_session(session; wait = true)
    nothing
end

# ── The session ──────────────────────────────────────────────────────────────

# The editor of this process, the task of its loop, the title and the document
# of each value that it showed, and every title that it gave. A value is the
# same value by identity: two equal values are two documents, and a lookup
# hashes no content.
struct _EditorSession
    editor::Editor
    loop::Task
    shown::IdDict{Any,Pair{String,Any}}
    titles::Set{String}
    refresh_timer::Base.RefValue{Union{Nothing,Timer}}   # the timer of `refresh_every`, or nothing
end

const _SESSION = Ref{Union{_EditorSession,Nothing}}(nothing)
const _SESSION_LOCK = ReentrantLock()

# A closure of this package, which is older than the loop, that calls `f` in the
# newest world.
_call_latest(f) = () -> Base.invokelatest(f)

_run_in_editor(f, session::_EditorSession) =
    run_on_editor_task!(_call_latest(f), session.editor)

function _remember!(session::_EditorSession, value, title::String, document)
    session.shown[value] = title => document
    push!(session.titles, title)
    nothing
end

# The loop runs, and a window is open. A closed window ends no loop, so a loop
# with no window is a session that a new display replaces.
_is_session_alive(session::_EditorSession) =
    !istaskdone(session.loop) &&
    _run_in_editor(() -> begin
        root = get_wrapped_document(session.editor.document)
        !(root isa ScreenDocument) || length(root.windows) > 0
    end, session)

# Post the refresh of every shown document to the editor of `session`, and wait
# for it when `wait`. The documents are read under the lock of the session,
# because the timer of `refresh_every` runs on a task of its own.
function _refresh_session(session::_EditorSession; wait::Bool)
    istaskdone(session.loop) && return nothing
    documents = lock(() -> Any[last(entry) for entry in values(session.shown)], _SESSION_LOCK)
    run_on_editor_task!(_call_latest(() -> foreach(_refresh_shown_document, documents)), session.editor;
                        wait)
    nothing
end

_refresh_shown_document(document) =
    hasmethod(refresh_document!, Tuple{typeof(document)}) && refresh_document!(document)

# A timer that refreshes the documents of `session` every `seconds`.
_start_refresh_timer(session::_EditorSession, seconds::Real) =
    Timer(_ -> _refresh_session(session; wait = false), seconds; interval = seconds)

function _close_session!(session::_EditorSession)
    timer = session.refresh_timer[]
    timer === nothing || close(timer)
    istaskdone(session.loop) && return nothing
    post_operation!(session.editor, QuitEditorOperation())
    wait(session.loop)
    nothing
end

# The features of a window of the display, as keywords of `build_editor`: the
# chrome, the undo, the clipboard and the walk, F1 help, the command palette, and
# the four that fill the tools of the toolbar. The slices of `ProjecturedPlatform`
# that declare them are always loaded with this one, and the display names them
# by keyword only.
const _DISPLAY_FEATURES = (:shell, :undo, :clipboard, :gesture_help, :command_palette,
                           :gesture_log, :message_log, :frame_statistics, :fault_log)

# The editor with one window, which shows `document`, built and run on a task
# of its own.
function _start_session(document, title::String; backend, tabs::Bool, refresh_every)
    appearance = load_appearance!(Appearance())
    projection = NaturalToGraphics(; measure = FontFileMeasure(), appearance = appearance)
    # The tabs wrapper is on by default, and the features of the window act on the
    # tabs, so a window of one value has none. The argument of the tabs names the
    # first tab.
    has_tabs = hasmethod(get_wrapper_layers, Tuple{Val{:tabs}}) && tabs
    features = has_tabs ?
        (; (keyword => true for keyword in _DISPLAY_FEATURES
            if hasmethod(get_wrapper_layers, Tuple{Val{keyword}}))...) : (;)
    # A value of its own window draws with a renderer of its own, because a
    # renderer keeps state for the documents it draws. The windows that the
    # features open draw with the rows that their wrappers give.
    opened = has_tabs ? Pair{Type,Any}[] :
        Pair{Type,Any}[Document => NaturalToGraphics(; measure = FontFileMeasure(), appearance)]
    window = (; title = "Values", width = 1000, height = 600, opened_window_projections = opened)
    # The loop logs each operation that it applies as an info line, and a hover
    # is an operation. The task of the loop keeps the logger of the scope that
    # starts it, so the loop writes only warnings and errors to the REPL.
    logger = Base.CoreLogging.ConsoleLogger(stderr, Base.CoreLogging.Warn)
    editor = Base.CoreLogging.with_logger(logger) do
        run_editor!(document, projection; wait = false, backend = backend,
                    fault_policy = FaultPolicy(),
                    window = window, appearance = appearance,
                    tabs = has_tabs ? (; title, appearance) : false, features...)
    end
    session = _EditorSession(editor, editor.loop_task, IdDict{Any,Pair{String,Any}}(), Set{String}(),
                             Ref{Union{Nothing,Timer}}(nothing))
    refresh_every === nothing || (session.refresh_timer[] = _start_refresh_timer(session, refresh_every))
    session
end

function _show_in_session!(session::_EditorSession, value, title::String)
    editor = session.editor
    shown = get(session.shown, value, nothing)
    if shown !== nothing
        _run_in_editor(() -> show_document!(last(shown); title = first(shown), editor), session)
        return last(shown)
    end
    unique = _make_unique_title(session, title)
    document = make_value_document(value)
    _run_in_editor(() -> show_document!(document; title = unique, editor), session)
    _remember!(session, value, unique, document)
    document
end

# `title`, or `title` with the first number that the session has not given.
function _make_unique_title(session::_EditorSession, title::String)
    title in session.titles || return title
    number = 2
    while string(title, " (", number, ")") in session.titles
        number += 1
    end
    string(title, " (", number, ")")
end
