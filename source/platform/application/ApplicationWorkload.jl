# Fragment of `ApplicationModule` — the workload of the application window: a list
# of clicks, keys and typed texts that the loop of the window reads as it reads the
# hand of a person, and a model that answers an assistant turn of the list. A
# package runs it in its `@compile_workload`, so that its package image holds the
# code that these steps run.

"""
    DrawnText(text; pick = :first)

A target of a workload step: a place where the window draws `text`. A `String`
matches a whole drawn text, and a `Regex` matches a part of one. When several
places draw it, `pick` chooses one: `:first` in the order of the drawing,
`:leftmost` or `:topmost`. The newest window is searched first, so a popup
comes before the window below it.
"""
struct DrawnText
    text::Union{String,Regex}
    pick::Symbol
end

function DrawnText(text::Union{AbstractString,Regex}; pick::Symbol = :first)
    pick in (:first, :leftmost, :topmost) ||
        throw(ArgumentError("The pick of a drawn text is :first, :leftmost or :topmost, not $(repr(pick))."))
    DrawnText(text isa Regex ? text : String(text), pick)
end

"""
    DrawnPart(predicate)

A target of a workload step: the drawing of the first part of a document for
which `predicate` answers `true`, such as a tool of the toolbar or the draft of
the assistant. `predicate` gets the input of each view of the window. A click
presses the middle of the drawing.
"""
struct DrawnPart
    predicate::Function
end

"""
    WorkloadStep

A step of [`run_application_workload`](@ref): a click, a key, a typed text, or a
wait for a target.
"""
abstract type WorkloadStep end

"""
    WorkloadClick(target; button = :left)

The pointer moves to `target`, a [`DrawnText`](@ref) or a [`DrawnPart`](@ref), and
`button` goes down and up there.
"""
struct WorkloadClick <: WorkloadStep
    target::Union{DrawnText,DrawnPart}
    button::Symbol
end

WorkloadClick(target::Union{DrawnText,DrawnPart}; button::Symbol = :left) =
    WorkloadClick(target, button)

"""
    WorkloadKey(key; ctrl = false, shift = false, alt = false)

The key `key` goes down and up with the modifiers. Return and Tab also type their
character, as a keyboard does.
"""
struct WorkloadKey <: WorkloadStep
    key::Symbol
    modifiers::ModifierKeys
end

WorkloadKey(key::Symbol; ctrl::Bool = false, shift::Bool = false, alt::Bool = false) =
    WorkloadKey(key, ModifierKeys(; ctrl, shift, alt))

"""
    WorkloadTyping(text)

Each character of `text` is typed: its key goes down, the character arrives, and
its key goes up.
"""
struct WorkloadTyping <: WorkloadStep
    text::String
end

"""
    WorkloadWait(target)

Wait until the window draws `target`, a [`DrawnText`](@ref) or a
[`DrawnPart`](@ref).
"""
struct WorkloadWait <: WorkloadStep
    target::Union{DrawnText,DrawnPart}
end

"""
    make_workload_llm(code; answer = "The code ran.") -> Llm

A model for the assistant turn of a workload. A workload gives it to a window as
the model of its assistant, such as the keyword `llm` of
[`run_application_workload`](@ref). Each turn of the model has the two rounds of
a turn with a tool call: the first thinks, says a line, and asks the tool
`execute_julia_code` to run `code`; the second says `answer`. So the window shows
each kind of part that a turn shows, and a workload waits for `answer` to know
that the turn ended.

Only a compile workload makes one. No path that a person starts makes one, and
the assistant does not fall back to it.
"""
make_workload_llm(code::AbstractString; answer::AbstractString = "The code ran.") =
    _WorkloadLlm(String(code), String(answer), 0)

# The model of `make_workload_llm`. `round` counts the rounds that it streamed, so
# that an odd round asks for the tool and an even round answers.
mutable struct _WorkloadLlm <: Llm
    code::String
    answer::String
    round::Int
end

function stream_turn(model::_WorkloadLlm, ::LlmRequest; on_event::Function)
    model.round += 1
    events = if isodd(model.round)
        tool_id = string("workload_", model.round)
        call = LlmToolUse(tool_id, "execute_julia_code", Dict{String,Any}("code" => model.code))
        LlmEvent[LlmThinkingStart(), LlmThinkingDelta("The code gives the answer."),
                 LlmThinkingSignature("workload"), LlmThinkingStop(),
                 LlmTextStart(), LlmTextDelta("I run the code."), LlmTextStop(),
                 LlmToolUseStart(tool_id, "execute_julia_code"), LlmToolUseStop(call),
                 LlmTurnEnd(:tool_use)]
    else
        LlmEvent[LlmTextStart(), LlmTextDelta(model.answer), LlmTextStop(), LlmTurnEnd(:end_turn)]
    end
    foreach(on_event, events)
    nothing
end

# How long the window stays quiet before a workload gives the next step, in
# seconds. A gesture that takes several events, such as a click, ends in this time.
const _QUIET_WINDOW_SECONDS = 0.25

"""
    run_application_workload(files; steps, llm = nothing, timeout = 300,
                             backend = WorkloadBackend(; events = Event[])) -> Nothing

Run the application window as `run_application` runs it, on `backend`, in a
temporary folder that holds `files`, and give it the [`WorkloadStep`](@ref)s of
`steps` one after the other. `files` is a list of `name => text` pairs, which
the Files pane lists. `llm` is the model of the assistant; with `nothing`, a
turn of the assistant fails, as it does when no model is named. The backend
takes the inputs of the steps by [`send_workload_inputs!`](@ref), and a backend
of another package that has a method of it runs the same steps.

Before each step, the window becomes quiet: no frame applies an input, and no
input or timer waits. A step with a target waits until the window draws the target, for
at most `timeout` seconds. After the last step, the loop stops, and the folder
is removed.

It throws an error that names each step whose target the window did not draw,
the step before which the loop ended, and each fault that a barrier of the
editor caught. A package calls it in its
`@compile_workload`, so that its package image holds the code of the steps.
"""
function run_application_workload(files::AbstractVector{<:Pair}; steps::AbstractVector{<:WorkloadStep},
                                  llm = nothing, timeout::Real = 300,
                                  backend::Backend = WorkloadBackend(; events = Event[]))
    directory = mktempdir()
    try
        for (name, text) in files
            write(joinpath(directory, name), text)
        end
        # No file and no variable of the environment starts a server, a process
        # or a connection to a model.
        settings = make_application_settings(nothing; assistant = :none, mcp = false)
        # The loop writes a line for each operation that it applies; the task of
        # the loop keeps the logger of the scope that starts it.
        logger = Base.CoreLogging.ConsoleLogger(stderr, Base.CoreLogging.Warn)
        editor = Base.CoreLogging.with_logger(logger) do
            run_editor!(; wait = false) do
                _make_application_editor(String[], settings; backend, root = directory,
                                         width = 1280, height = 800, appearance = Appearance(),
                                         llm)
            end
        end
        loop = editor.loop_task
        problems = String[]
        try
            for step in steps
                !editor.has_loop_ended && _run_workload_step!(editor, step, time() + timeout) &&
                    continue
                if editor.has_loop_ended
                    push!(problems, "The loop of the window ended before " * repr(step) * ".")
                    break
                end
                push!(problems, "The window did not draw the target of " * repr(step) * ".")
            end
            _wait_for_quiet_window(editor, time() + timeout)
        finally
            _stop_workload_editor!(editor, loop)
        end
        _throw_workload_problems(problems, get_fault_records(editor.faults))
    finally
        rm(directory; recursive = true, force = true)
    end
    nothing
end

# Give `step` to the window when the window is quiet and draws the target of the
# step. A call on the editor finds the target, and the inputs go to the backend
# from this task after the call, as a device gives them: the editor runs a call in
# a code unit, and a backend that holds its frames meanwhile drops the pointer
# input that starts during the hold. Answers whether it gave the step before
# `deadline` and the end of the loop.
function _run_workload_step!(editor, step::WorkloadStep, deadline::Float64)
    while !editor.has_loop_ended
        _wait_for_quiet_window(editor, deadline)
        editor.has_loop_ended && break
        inputs = _call_on_loop(() -> _find_workload_inputs(editor, step), editor, deadline)
        if inputs isa Vector{WindowInput}
            _wait_for_held_frames_end(editor, deadline)
            send_workload_inputs!(editor.backend, inputs)
            return true
        end
        time() >= deadline && break
        sleep(0.05)
    end
    false
end

# A call answers before the frames that the editor held while it ran end, and
# the editor clears its code unit when they end.
function _wait_for_held_frames_end(editor, deadline::Float64)
    while (@atomic editor.code_unit) !== nothing && time() < deadline && !editor.has_loop_ended
        sleep(0.001)
    end
end

# Wait until the window stays quiet for `_QUIET_WINDOW_SECONDS`, or until
# `deadline` or the end of the loop. Each look is a call on the editor, between
# two frames.
function _wait_for_quiet_window(editor, deadline::Float64)
    quiet_since = time()
    while time() < deadline && !editor.has_loop_ended
        _call_on_loop(() -> _is_window_busy(editor), editor, deadline) === false ||
            (quiet_since = time())
        time() - quiet_since >= _QUIET_WINDOW_SECONDS && return true
        sleep(0.005)
    end
    false
end

# Whether the last frame applied an input, a wake waits, a timer waits, or the
# backend holds an input that it did not give. A timer is a gesture that is not
# read yet: a click waits for a second click, and a rest of the pointer for a
# tooltip.
_is_window_busy(editor) =
    editor.operation !== nothing || editor.wake_pending[] || !isempty(editor.timers) ||
    has_workload_inputs(editor.backend)

# The answer of `function_` as a call on the editor, or `nothing` when the editor
# was too busy to start the call before `deadline`: a frame that compiles a first
# gesture can take seconds.
function _call_on_loop(function_, editor, deadline::Float64)
    try
        run_on_editor_task!(function_, editor; description = "a step of a workload",
                            timeout = max(1.0, deadline - time()))
    catch exception
        exception isa EditorCallTimeoutException || rethrow()
        nothing
    end
end

# The quit goes through the inbox, as a close of the display does. A loop that
# ended with an exception gives the exception here.
function _stop_workload_editor!(editor, loop::Task)
    if !istaskdone(loop)
        try
            post_operation!(editor, QuitEditorOperation())
        catch exception
            exception isa InvalidStateException || rethrow()
        end
    end
    wait(loop)
    nothing
end

function _throw_workload_problems(problems::Vector{String}, faults)
    isempty(problems) && isempty(faults) && return nothing
    lines = copy(problems)
    for record in faults
        push!(lines, string("A fault at the site ", record.site, " of ", record.origin, ": ",
                            record.exception_type, ": ", record.message))
    end
    error("The application workload failed.\n" * join(lines, "\n"))
end

# In a call on the editor: the inputs of `step`, with its target found in what the
# window drew, or `nothing` when the window does not draw the target.
function _find_workload_inputs(editor, step::WorkloadClick)
    place = _find_target_place(editor, step.target)
    place === nothing && return nothing
    (window, x, y) = place
    WindowInput[WindowInput(window, MouseMove(x, y; time = 0.0)),
                WindowInput(window, MouseDown(step.button, x, y; time = 0.0)),
                WindowInput(window, MouseUp(step.button, x, y; time = 0.0))]
end

_find_workload_inputs(editor, step::WorkloadKey) =
    _make_key_inputs(_get_main_window_id(editor), step.key, step.modifiers, nothing)

function _find_workload_inputs(editor, step::WorkloadTyping)
    window = _get_main_window_id(editor)
    inputs = WindowInput[]
    for char in step.text
        key = 'a' <= lowercase(char) <= 'z' ? Symbol(lowercase(char)) : char == ' ' ? :space : :char
        append!(inputs, _make_key_inputs(window, key, ModifierKeys(; shift = isuppercase(char)), char))
    end
    inputs
end

_find_workload_inputs(editor, step::WorkloadWait) =
    _find_target_place(editor, step.target) === nothing ? nothing : WindowInput[]

# The down, the character and the up of a key, as a keyboard gives them: the key
# of each modifier goes down before the key and up after it, and Return and Tab
# type their character with no character given.
function _make_key_inputs(window::Symbol, key::Symbol, modifiers::ModifierKeys,
                          char::Union{Char,Nothing})
    typed = char === nothing ? find_typed_character(key) : char
    held = [name for (name, is_held) in ((:lctrl, modifiers.ctrl), (:lshift, modifiers.shift),
                                         (:lalt, modifiers.alt)) if is_held]
    inputs = WindowInput[WindowInput(window, KeyDown(name, modifiers; time = 0.0)) for name in held]
    push!(inputs, WindowInput(window, KeyDown(key, modifiers; time = 0.0)))
    typed === nothing ||
        push!(inputs, WindowInput(window, KeyPress(typed, string(typed), modifiers; time = 0.0)))
    push!(inputs, WindowInput(window, KeyUp(key, modifiers; time = 0.0)))
    for name in reverse(held)
        push!(inputs, WindowInput(window, KeyUp(name, ModifierKeys(); time = 0.0)))
    end
    inputs
end

# The keyboard stays with the main window, as a window manager leaves it when a
# popup opens.
_get_main_window_id(editor) = first(collect(get_iomap_output(editor.iomap).windows)).id

# The window and the point of `target`, or `nothing` when no window draws it. The
# newest window comes first.
function _find_target_place(editor, target::DrawnText)
    for window in Iterators.reverse(collect(get_iomap_output(editor.iomap).windows))
        places = _collect_drawn_text_places!(Tuple{Int,Int}[], window.content, target.text, 0, 0)
        isempty(places) && continue
        # A place is `(x, y)`, so the topmost place is the least of the reversed ones.
        (x, y) = target.pick === :leftmost ? minimum(places) :
                 target.pick === :topmost ? reverse(minimum(reverse, places)) : first(places)
        return (window.id, x + 3, y + 3)
    end
    nothing
end

function _find_target_place(editor, target::DrawnPart)
    outputs = _collect_part_outputs(editor.iomap, target.predicate)
    isempty(outputs) && return nothing
    for window in Iterators.reverse(collect(get_iomap_output(editor.iomap).windows))
        for output in outputs
            point = _find_node_middle(window.content, output, 0, 0)
            point === nothing || return (window.id, point...)
        end
    end
    nothing
end

# A node of the drawing, with the cell and the link of a lazy list around it taken
# away.
function _get_drawn_node(node)
    node isa AbstractCell && (node = node[])
    node isa ListNode ? _get_drawn_node(node.value) : node
end

# The place of `node` in the frame of its window, from the place `(x0, y0)` of its
# container.
_get_drawn_place(node, x0::Int, y0::Int) =
    (hasproperty(node, :x) ? x0 + round(Int, something(node.x, 0)) : x0,
     hasproperty(node, :y) ? y0 + round(Int, something(node.y, 0)) : y0)

# Push to `places` the place of each drawn text below `node` that `text` matches.
function _collect_drawn_text_places!(places::Vector{Tuple{Int,Int}}, node, text, x0::Int, y0::Int)
    node = _get_drawn_node(node)
    node === nothing && return places
    (x, y) = _get_drawn_place(node, x0, y0)
    if node isa GraphicsText
        drawn = node.text
        (text isa Regex ? occursin(text, drawn) : drawn == text) && push!(places, (x, y))
    elseif hasproperty(node, :elements)
        for element in node.elements
            _collect_drawn_text_places!(places, element, text, x, y)
        end
    elseif node isa GraphicsViewport
        transform = node.transform
        _collect_drawn_text_places!(places, node.content, text,
                                    x + round(Int, transform.e), y + round(Int, transform.f))
    elseif hasproperty(node, :content)
        _collect_drawn_text_places!(places, node.content, text, x, y)
    end
    places
end

# The middle of `target`, a node of the drawing below `node`, in the frame of its
# window, or `nothing` when `node` does not hold it.
function _find_node_middle(node, target, x0::Int, y0::Int)
    node = _get_drawn_node(node)
    node === nothing && return nothing
    (x, y) = _get_drawn_place(node, x0, y0)
    if node === target
        w = hasproperty(node, :w) ? round(Int, something(node.w, 4)) : 4
        h = hasproperty(node, :h) ? round(Int, something(node.h, 4)) : 4
        return (x + w ÷ 2, y + h ÷ 2)
    elseif hasproperty(node, :elements)
        for element in node.elements
            point = _find_node_middle(element, target, x, y)
            point === nothing || return point
        end
    elseif node isa GraphicsViewport
        transform = node.transform
        return _find_node_middle(node.content, target,
                                x + round(Int, transform.e), y + round(Int, transform.f))
    elseif hasproperty(node, :content)
        return _find_node_middle(node.content, target, x, y)
    end
    nothing
end

# The outputs of the views below `iomap` whose input passes `predicate`. A view
# gives its children as a reader reaches them (`get_child_iomaps`), which computes
# a list of children that no print needed. A field of a view that holds a view
# is read only when its cell holds a value, so the walk computes no other cell.
function _collect_part_outputs(iomap, predicate)
    found = Any[]
    seen = IdDict{Any,Nothing}()
    stack = Any[iomap]
    while !isempty(stack)
        value = _get_held_value(pop!(stack))
        (value isa IoMap || value isa AbstractVector || value isa Tuple) || continue
        haskey(seen, value) && continue
        seen[value] = nothing
        if value isa IoMap
            input = _get_held_value(get_iomap_input(value))
            input !== nothing && predicate(input) &&
                push!(found, _get_held_value(get_iomap_output(value)))
            children = get_child_iomaps(value)
            children === nothing || append!(stack, children)
            for name in fieldnames(typeof(value))
                isdefined(value, name) && push!(stack, getfield(value, name))
            end
        else
            append!(stack, value)
        end
    end
    found
end

# The value of a cell that holds one, `nothing` for a cell that holds none, and any
# other value as it is.
_get_held_value(value) = value isa AbstractCell ? (is_cell_valid(value) ? value[] : nothing) : value

"""
    run_window_workload(; backend = WorkloadBackend(; events = Event[])) -> Nothing

Run the gestures of the application window with [`run_application_workload`](@ref)
on `backend`: a menu and an item of each menu, each tool of the toolbar, the
open of a text file and of a `.pred` file from the Files pane, a click, a key, a
save and an undo in each, a tab, a split, the Explorer and its context menu, a
new tab named in the name buffer, F1, the command palette, and an assistant
turn with a tool call. One gesture of each kind runs the code of every gesture
of that kind, and each tool opens a view of its own.

The package of the platform calls it in its `@compile_workload`, and the package
of a backend calls it with its own backend.
"""
function run_window_workload(; backend::Backend = WorkloadBackend(; events = Event[]))
    files = ["a.txt" => "one two three\nfour\n",
             "b.pred" => print_pred_text(CellVector(Any[PrimitiveString("first"),
                                                         PrimitiveString("second")]))]
    tool(label) = DrawnPart(input -> input isa WidgetToolbarItem &&
                                     string(input.action.label) == label)
    menu(title, item) = WorkloadStep[WorkloadClick(DrawnText(title; pick = :topmost)),
                                     WorkloadClick(DrawnText(item))]
    open_file(name, shown) = WorkloadStep[WorkloadClick(tool("Files")),
                                          WorkloadClick(DrawnText(name; pick = :leftmost)),
                                          WorkloadKey(:return), WorkloadWait(DrawnText(shown))]
    edit(shown) = WorkloadStep[WorkloadClick(DrawnText(shown)), WorkloadTyping("x"),
                               WorkloadKey(:s; ctrl = true), WorkloadKey(:z; ctrl = true)]
    steps = WorkloadStep[
        menu("Help", "About")...,
        menu("View", "Split vertically")...,
        menu("Help", "Documents")...,
        open_file("a.txt", r"four")..., edit(r"four")...,
        open_file("b.pred", "second")..., edit("second")...,
        WorkloadClick(DrawnText("a.txt"; pick = :topmost)),
        WorkloadClick(tool("Explorer")),
        WorkloadClick(DrawnText("Files"; pick = :leftmost); button = :right),
        WorkloadClick(DrawnText("Open in a new tab")),
        # Ctrl+T opens a tab on an empty placeholder, Insert turns it into the
        # name buffer, and the first key lists every type that it can make.
        WorkloadKey(:t; ctrl = true), WorkloadKey(:insert), WorkloadTyping("evaluator"),
        WorkloadKey(:return),
        WorkloadKey(:f1), WorkloadKey(:f1),
        WorkloadKey(:p; ctrl = true, shift = true), WorkloadTyping("ab"), WorkloadKey(:escape),
        (WorkloadClick(tool(label)) for label in ("Evaluator", "Selection", "Appearance", "Settings",
                                                  "Assistants", "Message log", "Gesture log",
                                                  "Fault log", "Frame statistics", "Frame times"))...,
        WorkloadClick(tool("Assistant")),
        WorkloadClick(DrawnPart(input -> input isa ConversationDraft)),
        WorkloadTyping("hi"), WorkloadKey(:return),
        WorkloadWait(DrawnText("The sum is two.")),
        WorkloadKey(:w; ctrl = true)]
    run_application_workload(files; steps, backend,
                             llm = make_workload_llm("1 + 1"; answer = "The sum is two."))
end
