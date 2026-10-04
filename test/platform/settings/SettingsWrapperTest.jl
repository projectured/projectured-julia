# The `settings` wrapper of `build_editor`. Its document holds the `Settings` of
# the editor around the content. A normal edit of a setting becomes an
# `ApplySettingOperation`, so the value reaches the place where it acts; every
# other edit passes as it is.

import ProjecturedKernelExample: HeadlessBackend, push_event!
import ProjecturedKernel.EditorModule: build_editor, run_frame!, EditorParts
import ProjecturedKernel.DeviceModule: Device, Keyboard, Mouse, Display
import ProjecturedPlatform.PaneModule: get_pane_groups, get_pane_tab_title_string

# A projection that answers Ctrl+`key` with `write`, as a view of a settings
# group does, and passes every other input to `inner`.
struct SettingsWrapperKeyProjection <: Projection
    inner::Projection
    key::Symbol
    write::Any
end
ProjecturedKernel.ProjectionModule.print_document(p::SettingsWrapperKeyProjection,
                                                  recursion, input, ctx) =
    print_document(p.inner, recursion, input, ctx)
function ProjecturedKernel.ProjectionModule.read_intent(p::SettingsWrapperKeyProjection,
                                                         recursion, change::Intent, iomap)
    event = change.gesture
    event isa KeyDown && event.key === p.key && event.modifiers.ctrl &&
        return Intent(event, p.write)
    read_intent(p.inner, recursion, change, iomap)
end

_sw_natural() = NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0))
_sw_key(key) = KeyDown(key, ModifierKeys(ctrl = true); time = 0.0)
_sw_field(name) = ConcreteReference(FieldReferenceStep(String(name)), EmptyReference())

# An editor on `document` with the settings wrapper and no window, no tabs and no
# appearance, after its first frame.
function _sw_editor(document; projection = _sw_natural(), settings = true, undo = false)
    backend = HeadlessBackend()
    editor = build_editor(document, projection; backend,
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false, settings, undo,
                          focus_cycling = false)
    run_frame!(editor)
    (editor, backend)
end

_sw_press!(editor, backend, events...) =
    (foreach(event -> push_event!(backend, event), events); run_frame!(editor))

function test_settings_wrapper()
@testset "the settings wrapper" begin

@testset "the root holds the settings around the content" begin
    settings = make_settings()
    label = WidgetLabel("Name")
    editor, _ = _sw_editor(label; settings)
    @test editor.document isa SettingsDocument
    @test editor.document.settings === settings
    @test editor.document.content === label
    @test get_wrapped_document(editor.document) === label
    # `true` makes a Settings with a group of each loaded type.
    other, _ = _sw_editor(WidgetLabel("Other"))
    @test other.document.settings !== settings
    @test haskey(other.document.settings.groups, RenderSettings)
end

@testset "a write into a group becomes an applied setting" begin
    settings = make_settings()
    fault = get_settings_group!(settings, FaultSettings)
    write = ReplaceReferencedValueOperation(fault, _sw_field(:is_sound_enabled), false)
    projection = SettingsWrapperKeyProjection(_sw_natural(), :s, write)
    editor, backend = _sw_editor(WidgetLabel("Name"); projection, settings)
    @test editor.fault_policy.is_sound_enabled
    _sw_press!(editor, backend, _sw_key(:s))
    @test !fault.is_sound_enabled
    @test !editor.fault_policy.is_sound_enabled       # the apply reached the editor
end

@testset "the wrap reaches into compound and wrapping operations, and nothing else" begin
    settings = make_settings()
    render = get_settings_group!(settings, RenderSettings)
    write = ReplaceReferencedValueOperation(render, _sw_field(:partial_render), true)
    other = ReplaceReferencedValueOperation(WidgetLabel("x"), _sw_field(:content), "y")
    @test wrap_setting_writes(settings, write) isa ApplySettingOperation
    @test wrap_setting_writes(settings, other) === other
    @test wrap_setting_writes(settings, DoNothingOperation()) isa DoNothingOperation
    compound = wrap_setting_writes(settings, CompoundOperation(Any[other, write]))
    @test compound.operations[1] === other
    @test compound.operations[2] isa ApplySettingOperation
    wrapped = wrap_setting_writes(settings, ReplaceViewStateOperation(write))
    @test wrapped isa ReplaceViewStateOperation &&
          get_wrapped_operation(wrapped) isa ApplySettingOperation
    applied = ApplySettingOperation(write)
    @test wrap_setting_writes(settings, applied) === applied
    # A group of another editor is not one of these settings.
    foreign = ReplaceReferencedValueOperation(RenderSettings(), _sw_field(:partial_render), true)
    @test wrap_setting_writes(settings, foreign) === foreign
end

@testset "an edit of the content applies nothing" begin
    settings = make_settings()
    label = WidgetLabel("Name")
    write = ReplaceReferencedValueOperation(label, _sw_field(:content), "Other")
    projection = SettingsWrapperKeyProjection(_sw_natural(), :e, write)
    editor, backend = _sw_editor(label; projection, settings)
    policy = editor.fault_policy
    _sw_press!(editor, backend, _sw_key(:e))
    @test label.content == "Other"
    @test editor.fault_policy === policy
end

@testset "the commands of the settings are listed and toggle their setting" begin
    settings = make_settings()
    editor, _ = _sw_editor(WidgetLabel("Name"); settings)
    answer = read_intent(editor.projection, nothing, Intent(CollectIntents()), editor.iomap)
    collected = answer isa Intent ? answer.operation : answer
    labels = Set(intent.description for intent in collected.intents)
    @test "Toggle partial render" in labels && "Toggle repaint outline" in labels
    toggle = make_toggle_setting_operation(settings, RenderSettings, :partial_render)
    @test toggle isa ApplySettingOperation
    evaluate_operation(editor, toggle)
    @test !get_settings_group!(settings, RenderSettings).partial_render
    @test make_toggle_setting_operation(Settings(), RenderSettings, :partial_render) isa
          DoNothingOperation
end

@testset "Show the settings opens one tab that shows the settings" begin
    settings = make_settings()
    editor = build_editor(WidgetLabel("Name"), _sw_natural(); backend = HeadlessBackend(),
                          devices = Device[Keyboard(), Mouse(), Display()],
                          appearance = false, settings, focus_cycling = false)
    run_frame!(editor)
    answer = read_intent(editor.projection, nothing, Intent(CollectIntents()), editor.iomap)
    collected = answer isa Intent ? answer.operation : answer
    shows = [intent for intent in collected.intents if intent.description == "Show the settings"]
    @test length(shows) == 1
    for _ in 1:2
        evaluate_operation(editor, shows[1].operation)
        run_frame!(editor)
    end
    tree = get_wrapped_document(editor.document).windows[1].content
    tabs = [tab for group in get_pane_groups(tree) for tab in group.tabs]
    @test count(tab -> tab.content === settings, tabs) == 1
    @test get_pane_tab_title_string(only(filter(tab -> tab.content === settings, tabs))) ==
          "Settings"
end

@testset "two editors keep two settings" begin
    one, two = make_settings(), make_settings()
    first_editor, _ = _sw_editor(WidgetLabel("One"); settings = one)
    second_editor, _ = _sw_editor(WidgetLabel("Two"); settings = two)
    evaluate_operation(first_editor, ApplySettingOperation(
        get_settings_group!(one, FaultSettings), :is_console_enabled, false))
    @test !first_editor.fault_policy.is_console_enabled
    @test second_editor.fault_policy.is_console_enabled
end

@testset "with no Settings from the caller, the values of the targets stay" begin
    backend = HeadlessBackend()
    editor = build_editor(WidgetLabel("Name"), _sw_natural(); backend,
                          devices = Device[Keyboard(), Mouse(), Display()],
                          window = false, tabs = false, appearance = false,
                          fault_policy = make_strict_fault_policy())
    run_frame!(editor)
    settings = editor.document.settings
    @test settings.is_read_from_targets
    @test !editor.fault_policy.is_barrier_enabled
    @test !get_settings_group!(settings, FaultSettings).is_barrier_enabled
    # An environment variable wins for one run.
    environment_editor = withenv("PROJECTURED_PARTIAL_RENDER" => "0") do
        build_editor(WidgetLabel("Name"), _sw_natural(); backend = HeadlessBackend(),
                     devices = Device[], window = false, tabs = false, appearance = false)
    end
    render = get_settings_group!(environment_editor.document.settings, RenderSettings)
    @test !render.partial_render
end

@testset "a Settings from the caller wins over the targets" begin
    settings = make_settings(FaultSettings(is_sound_enabled = false))
    @test !settings.is_read_from_targets
    editor, _ = _sw_editor(WidgetLabel("Name"); settings)
    @test !editor.fault_policy.is_sound_enabled
    # The environment is the main builder's to read.
    other = withenv("PROJECTURED_PARTIAL_RENDER" => "0") do
        first(_sw_editor(WidgetLabel("Name"); settings = make_settings()))
    end
    @test get_settings_group!(other.document.settings, RenderSettings).partial_render
end

@testset "the undo of a window keeps the steps of the history settings" begin
    settings = make_settings()
    history = get_settings_group!(settings, HistorySettings)
    editor, _ = _sw_editor(WidgetLabel("Name"); settings, undo = true)
    buffer = only(search_documents(editor.document, node -> node isa UndoBuffer))
    @test buffer.capacity == 100
    history.undo_capacity = 30
    @test buffer.capacity == 30
end

@testset "the window takes the pointer settings of the settings wrapper" begin
    settings = make_settings()
    pointer = get_settings_group!(settings, PointerSettings)
    parts = EditorParts(WidgetLabel("Name"), _sw_natural(), HeadlessBackend(), Feed[], Any[],
                        Any[], Pair{Type,Any}[], Any[], Dict{Symbol,Any}(:settings => settings))
    recognitions = ScreenModule._make_window_recognitions(parts)
    click = only(r for r in recognitions if r isa ClickRecognition)
    @test click.multi_click_max_interval === get_setting_cell(pointer, :multi_click_max_interval)
    parts.arguments = Dict{Symbol,Any}()
    plain = ScreenModule._make_window_recognitions(parts)
    @test only(r for r in plain if r isa ClickRecognition).multi_click_max_interval == 0.3
end

end
end
