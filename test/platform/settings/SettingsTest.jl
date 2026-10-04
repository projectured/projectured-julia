# The settings of an editor: a group that `@settings` declares, the `Settings` of
# one editor, and `ApplySettingOperation`, which checks a value, writes it and
# applies the group to the editor and to its backend.

import ProjecturedKernelExample: HeadlessBackend
import ProjecturedKernel.EditorModule: Editor, run_frame!
import ProjecturedKernel.DeviceModule: Device

@settings struct SettingsTestProbeSettings
    "Flag: a switch of the probe."
    flag::Bool = false
    "Count: a whole number of the probe."
    count::Int = 2 in 1:4
    "Delay: a number of seconds of the probe."
    delay::Float64 = 0.5 in 0.0:0.5:3.0
    "Mode: a choice of the probe."
    mode::Symbol = :fast in (:fast, :slow)
    "Name: a text of the probe."
    name::String = ""
end

@settings struct SettingsTestOtherSettings
    "Level: the one setting of the other probe."
    level::Int = 1
end

SettingsModule.get_setting_environment_names(::Type{SettingsTestProbeSettings}) =
    (flag = "SETTINGS_TEST_FLAG", count = "SETTINGS_TEST_COUNT", mode = "SETTINGS_TEST_MODE")

# A target that records each apply, as a backend or an editor does.
struct SettingsTestTarget
    applied::Vector{Any}
end
SettingsTestTarget() = SettingsTestTarget(Any[])
function SettingsModule.apply_settings!(target::SettingsTestTarget,
                                        group::SettingsTestProbeSettings)
    push!(target.applied, (group.flag, group.count))
    nothing
end

# The target holds a count of 4, which a read copies into the group.
SettingsModule.read_settings!(group::SettingsTestProbeSettings, ::SettingsTestTarget) =
    (group.count = 4; nothing)

# An editor as the evaluation sees one: a backend, and nothing else.
struct SettingsTestEditor
    backend::SettingsTestTarget
end

function test_settings()
@testset "the settings of an editor" begin

@testset "@settings declares a group and its descriptions" begin
    group = SettingsTestProbeSettings()
    @test group isa SettingsGroup
    @test (group.flag, group.count, group.delay, group.mode, group.name) ==
          (false, 2, 0.5, :fast, "")
    @test SettingsTestProbeSettings(count = 3).count == 3
    @test get_settings_group_type(group) === SettingsTestProbeSettings
    @test get_settings_name(SettingsTestProbeSettings) == "settings_test_probe"
    descriptions = get_setting_descriptions(SettingsTestProbeSettings)
    @test [d.name for d in descriptions] == [:flag, :count, :delay, :mode, :name]
    count = find_setting_description(SettingsTestProbeSettings, :count)
    @test (count.label, count.text, count.type, count.default, count.values) ==
          ("Count", "A whole number of the probe.", Int, 2, 1:4)
    @test find_setting_description(SettingsTestProbeSettings, :missing) === nothing
end

@testset "a declaration that breaks a rule is an error that names it" begin
    @test_throws "Label: text" @macroexpand @settings struct BadDocstringSettings
        "no label here"
        flag::Bool = false
    end
    @test_throws "needs a docstring" @macroexpand @settings struct NoDocstringSettings
        flag::Bool = false
    end
    @test_throws "the type of `size`" @macroexpand @settings struct BadTypeSettings
        "Size: a size."
        size::Int32 = 1
    end
    @test_throws "ends with `Settings`" @macroexpand @settings struct BadName
        "Flag: a flag."
        flag::Bool = false
    end
end

@testset "a value converts to its type and stays inside its values" begin
    describe(name) = find_setting_description(SettingsTestProbeSettings, name)
    @test convert_setting_value(describe(:flag), true) === true
    @test convert_setting_value(describe(:flag), 1) === nothing
    @test convert_setting_value(describe(:count), 3) === 3
    @test convert_setting_value(describe(:count), "4") === 4
    @test convert_setting_value(describe(:count), 3.0) === 3
    @test convert_setting_value(describe(:count), 5) === nothing
    @test convert_setting_value(describe(:count), true) === nothing
    @test convert_setting_value(describe(:count), "four") === nothing
    @test convert_setting_value(describe(:delay), 1) === 1.0
    @test convert_setting_value(describe(:delay), "2.5") === 2.5
    @test convert_setting_value(describe(:delay), 3.5) === nothing
    @test convert_setting_value(describe(:delay), NaN) === nothing
    @test convert_setting_value(describe(:mode), "slow") === :slow
    @test convert_setting_value(describe(:mode), :medium) === nothing
    @test convert_setting_value(describe(:name), :text) == "text"
end

@testset "a Settings holds one group of each type, and two are independent" begin
    settings = Settings()
    group = get_settings_group!(settings, SettingsTestProbeSettings)
    @test get_settings_group!(settings, SettingsTestProbeSettings) === group
    other = make_settings(SettingsTestProbeSettings(count = 4))
    @test get_settings_group!(other, SettingsTestProbeSettings).count == 4
    # The other loaded group types get their defaults.
    @test SettingsTestOtherSettings in compute_loaded_settings_types()
    @test haskey(other.groups, SettingsTestOtherSettings)
    @test group.count == 2
    replaced = set_settings_group!(settings, SettingsTestProbeSettings(flag = true))
    @test get_settings_group!(settings, SettingsTestProbeSettings) === replaced
    get_settings_group!(settings, SettingsTestOtherSettings)
    names = [get_settings_name(get_settings_group_type(group))
             for group in get_settings_groups(settings)]
    @test names == ["settings_test_other", "settings_test_probe"]
    @test is_settings_group(settings, replaced)
    @test !is_settings_group(settings, group)
    @test !is_settings_group(other, replaced)
end

@testset "ApplySettingOperation writes the value and then applies the group" begin
    group = SettingsTestProbeSettings()
    target = SettingsTestTarget()
    editor = SettingsTestEditor(target)
    evaluate_operation(editor, ApplySettingOperation(group, :count, 3))
    @test group.count == 3
    @test target.applied == [(false, 3)]
    evaluate_operation(editor, ApplySettingOperation(group, :flag, true))
    @test group.flag
    @test target.applied[end] == (true, 3)
    # A value from a text converts.
    evaluate_operation(editor, ApplySettingOperation(group, :count, "4"))
    @test group.count === 4
    @test describe_operation(ApplySettingOperation(group, :flag, false)) ==
          "set flag to off"
end

@testset "a value that does not fit changes nothing and applies nothing" begin
    group = SettingsTestProbeSettings()
    target = SettingsTestTarget()
    @test_logs (:warn, r"can not take 9") evaluate_operation(
        SettingsTestEditor(target), ApplySettingOperation(group, :count, 9))
    @test group.count == 2
    @test isempty(target.applied)
end

@testset "the inverse writes the old value and then applies it" begin
    group = SettingsTestProbeSettings()
    target = SettingsTestTarget()
    editor = SettingsTestEditor(target)
    operation = ApplySettingOperation(group, :count, 4)
    inverse = make_inverse_operation(nothing, operation)
    @test inverse isa ApplySettingOperation
    evaluate_operation(editor, operation)
    evaluate_operation(editor, inverse)
    @test group.count == 2
    @test target.applied == [(false, 4), (false, 2)]
end

@testset "a write of no single setting of a group is no ApplySettingOperation" begin
    @test_throws ArgumentError ApplySettingOperation(
        ReplaceReferencedValueOperation(WidgetLabel("x"), "content", "y"))
    @test_throws ArgumentError ApplySettingOperation(
        ReplaceReferencedValueOperation(SettingsTestProbeSettings(), EmptyReference(), 1))
end

@testset "an environment variable sets a setting for one run" begin
    settings = make_settings(SettingsTestProbeSettings(count = 3))
    environment = Dict("SETTINGS_TEST_FLAG" => "on", "SETTINGS_TEST_COUNT" => " ",
                       "SETTINGS_TEST_MODE" => "slow")
    read_settings_environment!(settings, environment)
    group = get_settings_group!(settings, SettingsTestProbeSettings)
    # An empty variable leaves the value as it is.
    @test (group.flag, group.count, group.mode) == (true, 3, :slow)
    @test_logs (:warn, r"SETTINGS_TEST_COUNT can not set \"Count\" to \"9\"") (
        read_settings_environment!(settings, Dict("SETTINGS_TEST_COUNT" => "9")))
    @test group.count == 3
    read_settings_environment!(settings, Dict("SETTINGS_TEST_FLAG" => "0"))
    @test !group.flag
    # A group with no variables reads none.
    @test get_setting_environment_names(SettingsTestOtherSettings) == (;)
end

@testset "the render settings of the screen" begin
    @test get_settings_name(RenderSettings) == "render"
    @test [d.name for d in get_setting_descriptions(RenderSettings)] ==
          [:partial_render, :debug_dirty, :debug_dirty_hold, :supersample]
    render = RenderSettings()
    @test (render.partial_render, render.debug_dirty, render.debug_dirty_hold,
           render.supersample) == (true, false, 0.0, 2)
    settings = make_settings()
    read_settings_environment!(settings, Dict("PROJECTURED_PARTIAL_RENDER" => "0",
                                              "PROJECTURED_DEBUG_DIRTY" => "yes",
                                              "PROJECTURED_SUPERSAMPLE" => "1"))
    render = get_settings_group!(settings, RenderSettings)
    @test (render.partial_render, render.debug_dirty, render.supersample) == (false, true, 1)
end

@testset "the fault settings become the fault policy of the editor" begin
    editor = Editor(WidgetLabel("fault"),
                    NaturalToGraphics(; measure = FixedMeasure(8, 12, 4, 0));
                    backend = HeadlessBackend(), devices = Device[])
    run_frame!(editor)
    @test editor.iomap !== nothing
    group = FaultSettings(is_barrier_enabled = false)
    @test is_settings_target(editor, group)
    @test !is_settings_target(editor.backend, group)
    evaluate_operation(editor, ApplySettingOperation(group, :is_console_enabled, false))
    @test editor.fault_policy ==
          FaultPolicy(is_barrier_enabled = false, is_console_enabled = false)
    # A report reads the log flag from the editor, so the view does not print again.
    @test editor.iomap !== nothing
    # A barrier decides while it prints whether it catches, so the view prints again.
    evaluate_operation(editor, ApplySettingOperation(group, :is_barrier_enabled, true))
    @test editor.fault_policy.is_barrier_enabled
    @test editor.iomap === nothing
    run_frame!(editor)
    # The same policy again prints nothing again.
    apply_settings!(editor, group)
    @test editor.iomap !== nothing
end

@testset "the pointer settings are the limits of the recognitions" begin
    group = PointerSettings()
    @test (group.multi_click_max_interval, group.click_max_displacement,
           group.dwell_delay) == (0.3, 5, 0.5)
    recognitions = make_standard_recognitions(group)
    click = only(r for r in recognitions if r isa ClickRecognition)
    dwell = only(r for r in recognitions if r isa DwellRecognition)
    @test any(r -> r isa ChordRecognition, recognitions)
    limit(value) = value isa Real ? value : value[]
    @test limit(click.multi_click_max_interval) == 0.3
    evaluate_operation(nothing, ApplySettingOperation(group, :multi_click_max_interval, 0.6))
    evaluate_operation(nothing, ApplySettingOperation(group, :click_max_displacement, 8))
    evaluate_operation(nothing, ApplySettingOperation(group, :dwell_delay, 1.0))
    @test limit(click.multi_click_max_interval) == 0.6
    @test limit(click.click_max_displacement) == 8
    @test limit(click.multi_click_max_displacement) == 8
    @test limit(dwell.delay) == 1.0
    # The time of a press stays the default of a desktop.
    @test limit(click.click_max_duration) == 0.3
end

@testset "each history of an editor keeps the steps of the setting" begin
    history = HistorySettings()
    @test history.undo_capacity == 100
    buffer = UndoBuffer(WidgetLabel("history");
                        capacity = get_setting_cell(history, :undo_capacity))
    @test buffer.capacity == 100
    for index in 1:12
        push_undo_entry!(buffer, UndoEntry("step", DoNothingOperation(), nothing))
    end
    @test length(buffer.undo_entries) == 12
    evaluate_operation(nothing, ApplySettingOperation(history, :undo_capacity, 10))
    @test buffer.capacity == 10
    # The buffer drops the oldest steps at its next step.
    push_undo_entry!(buffer, UndoEntry("step", DoNothingOperation(), nothing))
    @test length(buffer.undo_entries) == 10
    # A number stays a number.
    @test UndoBuffer(WidgetLabel("plain"); capacity = 5).capacity == 5
end

@testset "a read copies the values of the targets into a group" begin
    group = SettingsTestProbeSettings()
    read_settings_from_editor!(SettingsTestEditor(SettingsTestTarget()), group)
    @test group.count == 4
    # A group that no target reads stays as it is.
    other = SettingsTestOtherSettings()
    read_settings_from_editor!(SettingsTestEditor(SettingsTestTarget()), other)
    @test other.level == 1
    @test read_settings!(other, nothing) === nothing
end

@testset "a settings file keeps the values, and a load tolerates what it does not know" begin
    folder = mktempdir()
    path = joinpath(folder, "nested", "settings.toml")
    settings = make_settings(SettingsTestProbeSettings(flag = true, count = 3, mode = :slow,
                                                       name = "probe"))
    write_settings_file!(settings, path)
    text = read(path, String)
    @test occursin("[settings_test_probe]", text) && occursin("mode = \"slow\"", text)
    loaded = make_settings()
    read_settings_file!(loaded, path)
    probe = get_settings_group!(loaded, SettingsTestProbeSettings)
    @test (probe.flag, probe.count, probe.mode, probe.name) == (true, 3, :slow, "probe")
    # A key that is missing keeps its value; what is not known, or does not fit,
    # is a warning, and the rest loads.
    write(path, "[settings_test_probe]\ncount = 9\ndelay = 1.5\nunknown = 1\n\n[nowhere]\nx = 1\n")
    partial = make_settings()
    @test_logs (:warn, r"count") (:warn, r"unknown") (:warn, r"\[nowhere\]") match_mode = :any (
        read_settings_file!(partial, path))
    group = get_settings_group!(partial, SettingsTestProbeSettings)
    @test (group.count, group.delay, group.flag) == (2, 1.5, false)
    # A file that does not exist changes nothing.
    @test read_settings_file!(make_settings(), joinpath(folder, "none.toml")) isa Settings
    rm(folder; recursive = true)
end

@testset "save and load are operations, and a load can be taken back" begin
    folder = mktempdir()
    path = joinpath(folder, "settings.toml")
    settings = make_settings(SettingsTestProbeSettings(count = 4))
    save = SaveSettingsOperation(settings, path)
    @test make_inverse_operation(nothing, save) isa DoNothingOperation
    evaluate_operation(nothing, save)
    @test isfile(path)
    group = get_settings_group!(settings, SettingsTestProbeSettings)
    group.count = 1
    target = SettingsTestTarget()
    editor = SettingsTestEditor(target)
    load = LoadSettingsOperation(settings, path)
    back = make_inverse_operation(nothing, load)
    evaluate_operation(editor, load)
    @test group.count == 4
    @test target.applied == [(false, 4)]            # one change, one apply
    evaluate_operation(editor, back)
    @test group.count == 1
    rm(folder; recursive = true)
end

@testset "the configuration folder follows XDG_CONFIG_HOME" begin
    withenv("XDG_CONFIG_HOME" => "/some/where") do
        @test get_configuration_folder() == "/some/where/projectured"
        @test get_settings_file() == "/some/where/projectured/settings.toml"
    end
    withenv("XDG_CONFIG_HOME" => nothing) do
        @test get_configuration_folder() == joinpath(homedir(), ".config", "projectured")
    end
end

@testset "a target is a target of a group when a method applies it" begin
    @test is_settings_target(SettingsTestTarget(), SettingsTestProbeSettings())
    @test !is_settings_target(SettingsTestTarget(), SettingsTestOtherSettings())
    @test !is_settings_target(nothing, SettingsTestProbeSettings())
    # The default does nothing.
    @test apply_settings!(nothing, SettingsTestProbeSettings()) === nothing
end

end
end
