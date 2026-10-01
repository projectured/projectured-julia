# The settings tab: the `Settings` of an editor drawn by `SettingsToWidget`. A test
# presses where a control is drawn: it reads clicks along the row of a label
# until one answers the edit of its setting, and then gives that click to the
# editor. The settings wrapper of the same editor applies each change.

import ProjecturedKernelExample: HeadlessBackend, rendered_output, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display

_stab_natural(; extra = Pair{Type,Any}[]) =
    NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0), extra)

# An editor whose content is `content`, a tab that shows `settings`, with the
# settings wrapper over the same `settings`, after its first frame.
function _stab_editor(content, settings; extra = Pair{Type,Any}[])
    backend = HeadlessBackend()
    editor = build_editor(content, _stab_natural(; extra); backend,
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings)
    run_frame!(editor)
    (editor, backend)
end

# Each text of a canvas, at its place.
function _stab_drawn(canvas, ox = 0, oy = 0, found = Tuple{String,Int,Int}[])
    x = ox + Int(canvas.x)
    y = oy + Int(canvas.y)
    for element in canvas.elements
        if element isa GraphicsText
            push!(found, (String(element.text), x + Int(element.x), y + Int(element.y)))
        elseif element isa GraphicsCanvas
            _stab_drawn(element, x, y, found)
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
    # The card can wrap the note, so a piece of it is enough.
    @test any(text -> occursin("does not use", text[1]), _stab_texts(backend))
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

@testset "the settings of an editor are found under its root" begin
    settings = make_settings()
    editor, _ = _stab_editor(WidgetLabel("Name"), settings)
    @test find_editor_settings(editor) === settings
end

end
end
