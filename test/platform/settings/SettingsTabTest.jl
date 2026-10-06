# The settings tab: the `Settings` of an editor drawn by `SettingsToWidget`. A test
# presses where a control is drawn: it reads clicks along the row of a label
# until one answers the edit of its setting, and then gives that click to the
# editor. The settings wrapper of the same editor applies each change.

import ProjecturedKernelExample: HeadlessBackend, rendered_output, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display
import ProjecturedPlatform.ScreenModule: show_document!

_stab_natural(; extra = Pair{Type,Any}[]) =
    NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0), extra)

# An editor whose content is `content`, a tab that shows `settings`, with the
# settings wrapper over the same `settings`, after its first frame.
function _stab_editor(content, settings; extra = Pair{Type,Any}[], focus_cycling = false,
                      display = Display())
    backend = HeadlessBackend()
    editor = build_editor(content, _stab_natural(; extra); backend,
                          devices = Device[Keyboard(), Mouse(), display],
                          window = false, tabs = false, appearance = false, settings,
                          focus_cycling)
    run_frame!(editor)
    (editor, backend)
end

# Each text of a canvas, at its place, also inside the viewport of a pane.
function _stab_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        element = element isa Cell ? element[] : element
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _stab_drawn(element, x, y, found)
        elseif element isa GraphicsViewport
            _stab_drawn(element.content, x + Int(element.x) + round(Int, element.transform.e),
                        y + Int(element.y) + round(Int, element.transform.f), found)
        end
    end
    found
end

_stab_texts(backend) = _stab_drawn(last(rendered_output(backend)))

# The names of the settings that `operation` changes, inside a compound or a
# wrapping operation too.
_stab_names(operation::ApplySettingOperation) =
    Symbol[Symbol(get_reference_head(strip_reference_types(operation.operation.reference)).name)]
_stab_names(operation::CompoundOperation) = reduce(vcat, map(_stab_names, operation.operations);
                                                   init = Symbol[])
_stab_names(operation::WrappingOperation) = _stab_names(get_wrapped_operation(operation))
_stab_names(_) = Symbol[]

_stab_click(x, y) = MouseClick(:left, x, y, 1, ModifierKeys(); time = 0.0)

# The click on the row of `label`, right of the label, whose answer changes the
# setting `name`; `nothing` when no point of the row does.
function _stab_find_click(editor, backend, label, name)
    (_, lx, ly) = only(text for text in _stab_texts(backend) if text[1] == label)
    for x in lx:2:(lx + 800)
        answer = read_intent(editor.projection, nothing, Intent(_stab_click(x, ly + 6)),
                             editor.iomap)
        operation = answer isa Intent ? answer.operation : answer
        name in _stab_names(operation) && return _stab_click(x, ly + 6)
    end
    nothing
end

# The click on the row of `label`, right of the label, whose answer `is_wanted`
# takes; `nothing` when no point of the row answers so.
function _stab_find_click_answer(editor, backend, label, is_wanted)
    (_, lx, ly) = only(text for text in _stab_texts(backend) if text[1] == label)
    for x in lx:2:(lx + 800)
        answer = read_intent(editor.projection, nothing, Intent(_stab_click(x, ly + 6)),
                             editor.iomap)
        is_wanted(answer isa Intent ? answer.operation : answer) && return _stab_click(x, ly + 6)
    end
    nothing
end

_stab_has_selection(operation::ReplaceSelectionOperation) = true
_stab_has_selection(operation::CompoundOperation) = any(_stab_has_selection, operation.operations)
_stab_has_selection(operation::WrappingOperation) = _stab_has_selection(get_wrapped_operation(operation))
_stab_has_selection(_) = false

_stab_type(character::Char) = KeyPress(character, string(character), ModifierKeys(); time = 0.0)

# The click on the text `text` drawn in the row of `label`.
function _stab_click_in_row(backend, label, text)
    (_, _, ly) = only(drawn for drawn in _stab_texts(backend) if drawn[1] == label)
    (_, x, y) = only(drawn for drawn in _stab_texts(backend)
                     if drawn[1] == text && abs(drawn[3] - ly) <= 8)
    _stab_click(x + 2, y + 6)
end

_stab_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

function test_settings_tab()
@testset "the settings tab" begin

@testset "a card for each group, a row for each setting" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    texts = Set(first(text) for text in _stab_texts(backend))
    @test "Fault" in texts && "Pointer" in texts && "History" in texts && "Render" in texts
    @test "Log faults" in texts && "Double click time" in texts && "Undo steps" in texts
    @test "Reset all" in texts && "Reset" in texts
end

@testset "a setting shows its description under its label, and a card the summary of its group" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    texts = _stab_texts(backend)
    label = only(t for t in texts if t[1] == "Log faults")
    # The description, the text of the docstring after the label, starts on a line
    # under the label, at the start of the row.
    description = only(t for t in texts if t[1] == "Write each new fault to the log.")
    @test description[3] > label[3]
    @test description[2] == label[2]
    # It belongs to its setting: it is closer to its label than to the next one.
    next = only(t for t in texts if t[1] == "Fault sound")
    @test description[3] - label[3] < next[3] - description[3]
    # The card of the group starts with the summary of its type.
    summary = compute_docstring_summary(FaultSettings)
    @test !isempty(summary)
    @test any(t -> length(t[1]) > 10 && startswith(summary, t[1]), texts)
    @test !any(t -> occursin('`', t[1]), texts)
end

@testset "a press on a switch changes its setting, and the editor applies it" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    click = _stab_find_click(editor, backend, "Log faults", :is_console_enabled)
    @test click !== nothing
    @test editor.fault_policy.is_console_enabled
    _stab_press!(editor, backend, click)
    @test !get_settings_group!(settings, FaultSettings).is_console_enabled
    @test !editor.fault_policy.is_console_enabled
end

@testset "a press on a stepper steps a number in its values" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    click = _stab_find_click(editor, backend, "Undo steps", :undo_capacity)
    @test click !== nothing
    _stab_press!(editor, backend, click)
    # The values of the setting are `10:10000`, so a step is 1.
    @test get_settings_group!(settings, HistorySettings).undo_capacity in (99, 101)
end

@testset "a reset gives a setting its default, and Reset all gives every one" begin
    settings = make_settings()
    fault = get_settings_group!(settings, FaultSettings)
    pointer = get_settings_group!(settings, PointerSettings)
    editor, backend = _stab_editor(settings, settings)
    evaluate_operation(editor, ApplySettingOperation(fault, :is_sound_enabled, false))
    evaluate_operation(editor, ApplySettingOperation(pointer, :dwell_delay, 2.0))
    run_frame!(editor)
    _stab_press!(editor, backend, _stab_click_in_row(backend, "Fault sound", "Reset"))
    @test fault.is_sound_enabled && editor.fault_policy.is_sound_enabled
    @test pointer.dwell_delay == 2.0
    (_, x, y) = only(text for text in _stab_texts(backend) if text[1] == "Reset all")
    _stab_press!(editor, backend, _stab_click(x + 2, y + 6))
    @test pointer.dwell_delay == 0.5
end

@testset "a control follows a change from another path" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    history = get_settings_group!(settings, HistorySettings)
    evaluate_operation(editor, ApplySettingOperation(history, :undo_capacity, 250))
    run_frame!(editor)
    @test any(text -> text[1] == "250", _stab_texts(backend))
end

@testset "a group that the editor does not use says so, and its controls are off" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    # The headless backend draws no windows, so nothing applies the render group.
    @test RenderSettings in settings.unused_types
    @test !(FaultSettings in settings.unused_types)
    @test !(PointerSettings in settings.unused_types)
    @test is_settings_group_applied(RenderSettings) && is_settings_group_applied(FaultSettings)
    @test !is_settings_group_applied(PointerSettings)
    # The card can wrap the note, so a piece of it is enough. The note is its text,
    # not the text of a widget.
    @test any(text -> occursin("does not use", text[1]), _stab_texts(backend))
    @test !any(text -> occursin("WidgetLabel", text[1]), _stab_texts(backend))
    @test _stab_find_click(editor, backend, "Partial render", :partial_render) === nothing
end

@testset "Ctrl+Z in a history around the tab takes back a change, and applies it" begin
    settings = make_settings()
    buffer = UndoBuffer(settings)
    editor, backend = _stab_editor(buffer, settings;
                                   extra = Pair{Type,Any}[UndoBuffer => UndoBufferToAnyProjection()])
    click = _stab_find_click(editor, backend, "Log faults", :is_console_enabled)
    _stab_press!(editor, backend, click)
    @test !editor.fault_policy.is_console_enabled
    @test length(buffer.undo_entries) == 1
    _stab_press!(editor, backend, KeyDown(:z, ModifierKeys(ctrl = true); time = 0.0))
    @test get_settings_group!(settings, FaultSettings).is_console_enabled
    @test editor.fault_policy.is_console_enabled
    _stab_press!(editor, backend, KeyDown(:y, ModifierKeys(ctrl = true); time = 0.0))
    @test !editor.fault_policy.is_console_enabled
end

@testset "Save and Load are off with no file, and write and read the file" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    (_, x, y) = only(text for text in _stab_texts(backend) if text[1] == "Save")
    answer = read_intent(editor.projection, nothing, Intent(_stab_click(x + 2, y + 6)),
                         editor.iomap)
    @test (answer isa Intent ? answer.operation : answer) === nothing
    folder = mktempdir()
    settings.file = joinpath(folder, "settings.toml")
    run_frame!(editor)
    _stab_press!(editor, backend, _stab_click(x + 2, y + 6))
    @test isfile(settings.file)
    fault = get_settings_group!(settings, FaultSettings)
    evaluate_operation(editor, ApplySettingOperation(fault, :is_sound_enabled, false))
    run_frame!(editor)
    (_, lx, ly) = only(text for text in _stab_texts(backend) if text[1] == "Load")
    _stab_press!(editor, backend, _stab_click(lx + 2, ly + 6))
    @test fault.is_sound_enabled && editor.fault_policy.is_sound_enabled
    rm(folder; recursive = true)
end

@testset "Tab reaches a control of the tab, and Space changes its setting" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings; focus_cycling = true)
    fault = get_settings_group!(settings, FaultSettings)
    @test fault.is_barrier_enabled
    _stab_press!(editor, backend, KeyDown(:tab, ModifierKeys(); time = 0.0))
    # The selection of the settings is a path that the tab introduces.
    @test get_selection(settings) isa ConcreteReference
    _stab_press!(editor, backend, KeyDown(:space, ModifierKeys(); time = 0.0))
    @test !fault.is_barrier_enabled && !editor.fault_policy.is_barrier_enabled
end

@testset "a click puts the caret in a text of a setting, and a key types into it" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    start = get_settings_group!(settings, StartSettings)
    click = _stab_find_click_answer(editor, backend, "Model", _stab_has_selection)
    @test click !== nothing
    _stab_press!(editor, backend, click)
    for character in "big"
        _stab_press!(editor, backend, _stab_type(character))
    end
    @test start.model == "big"
    @test any(text -> text[1] == "big", _stab_texts(backend))
end

@testset "a choice writes its value, and the start group says when it acts" begin
    settings = make_settings()
    editor, backend = _stab_editor(settings, settings)
    start = get_settings_group!(settings, StartSettings)
    @test start.assistant === :ollama
    (_, _, ly) = only(text for text in _stab_texts(backend) if text[1] == "Assistant")
    (_, x, y) = only(text for text in _stab_texts(backend)
                     if text[1] == "anthropic" && abs(text[3] - ly) <= 40)
    _stab_press!(editor, backend, _stab_click(x + 2, y + 6))
    @test start.assistant === :anthropic
    @test any(text -> occursin("next start", text[1]), _stab_texts(backend))
end

@testset "the tab scrolls in a window, and a change of a setting keeps its place" begin
    settings = make_settings()
    backend = HeadlessBackend()
    editor = build_editor(WidgetLabel("Name"); backend,
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = (; title = "T", width = 900, height = 300),
                          tabs = (; title = "Doc"), settings)
    run_frame!(editor)
    function send!(events...)
        foreach(event -> push_event!(backend, WindowInput(:T, event)), events)
        run_frame!(editor)
        run_frame!(editor)
    end
    show_document!(settings; title = "Settings", editor)
    send!()
    drawn() = _stab_drawn(only(last(rendered_output(backend)).windows).content)
    place(label) = only(text for text in drawn() if text[1] == label)[3]
    bottom = place("Reset all")
    @test bottom > 300
    # The row of the undo steps starts below the window, which is 300 high.
    @test place("Undo steps") > 300
    (_, x, y) = only(text for text in drawn() if text[1] == "Catch faults")
    # The wheel scrolls the tab until the row of the undo steps is in the window.
    for i in 1:20
        place("Undo steps") <= 250 && break
        send!(MouseScroll(0, -1, x, y, ModifierKeys(); time = 0.1 * i))
    end
    @test 0 < place("Undo steps") <= 250
    scrolled = place("Reset all")
    @test scrolled < bottom
    # The step up of the undo steps is the upper arrow in the row of its label.
    row = place("Undo steps")
    (_, ux, uy) = only(text for text in drawn() if text[1] == "\ue13d" && abs(text[3] - row) <= 12)
    send!(MouseDown(:left, ux + 4, uy + 4, ModifierKeys(); time = 5.0),
          MouseUp(:left, ux + 4, uy + 4, ModifierKeys(); time = 5.05))
    @test get_settings_group!(settings, HistorySettings).undo_capacity == 101
    @test place("Reset all") == scrolled
    # A press on the switch of "Log faults", found along its row, changes the log
    # flag, which a report reads from the editor: the view does not print again.
    fault = get_settings_group!(settings, FaultSettings)
    row = place("Log faults")
    @test 0 < row < 300
    for (i, px) in enumerate(100:4:400)
        fault.is_console_enabled || break
        send!(MouseDown(:left, px, row + 6, ModifierKeys(); time = 10.0 + i),
              MouseUp(:left, px, row + 6, ModifierKeys(); time = 10.05 + i))
    end
    @test !fault.is_console_enabled
    @test !editor.fault_policy.is_console_enabled
    @test place("Reset all") == scrolled
end

@testset "the settings of an editor are found under its root" begin
    settings = make_settings()
    editor, _ = _stab_editor(WidgetLabel("Name"), settings)
    @test find_editor_settings(; editor) === settings
end

end
end
