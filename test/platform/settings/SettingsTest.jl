# The settings of an editor: a group that `@settings` declares, the `Settings` of
# one editor, and `ApplySettingOperation`, which checks a value, writes it and
# applies the group to the editor and to its backend.

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

@testset "a target is a target of a group when a method applies it" begin
    @test is_settings_target(SettingsTestTarget(), SettingsTestProbeSettings())
    @test !is_settings_target(SettingsTestTarget(), SettingsTestOtherSettings())
    @test !is_settings_target(nothing, SettingsTestProbeSettings())
    # The default does nothing.
    @test apply_settings!(nothing, SettingsTestProbeSettings()) === nothing
end

end
end
