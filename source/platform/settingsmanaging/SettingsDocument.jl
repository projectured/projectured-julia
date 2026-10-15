# Fragment of `SettingsManagingModule` — the document that holds the settings of
# an editor around the document that the editor shows, and its commands.

"""
    SettingsDocument(settings, content)

The root document of an editor with the `settings` wrapper: the `Settings` of the
editor, and `content`, the document that the editor shows. The settings are a
part of the document, so a view can show them and a reference can name them.
"""
@document struct SettingsDocument <: Document
    settings::Settings
    content::Document
end

get_wrapped_document(document::SettingsDocument) = get_wrapped_document(document.content)

"""
    make_settings_document(document, settings) -> SettingsDocument

`document` inside a `SettingsDocument` with `settings`. The selection of
`document` moves to the new root, under `content`.
"""
function make_settings_document(document, settings::Settings)
    wrapped = SettingsDocument(settings, document)
    inner = get_selection(document)
    inner === nothing ||
        replace_selection!(wrapped,
            concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                              strip_reference_types(inner)))
    wrapped
end

"""
    find_editor_settings(; editor = get_evaluation_editor()) -> Settings or nothing

The `Settings` of `editor`: those of the `SettingsDocument` at its root, or
under the `content` of the documents around it, such as the `AppearanceDocument`. `nothing` for an editor with no
`settings` wrapper.

Use [`describe_settings`](@ref) to read the settings of the window as text.
"""
function find_editor_settings(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "find_editor_settings") do
        document = editor.document
        for _ in 1:8
            document isa SettingsDocument && return document.settings
            hasproperty(document, :content) || return nothing
            document = document.content
        end
        nothing
    end
end

"""
    describe_settings(; editor = get_evaluation_editor()) -> Text

The settings of the window, one line each: the group, the name, the value now,
and the sentence that says what the setting does, with the values it can take
when they are few. A window with no settings says so.

Use it to find the name of a setting before you change it with
[`change_setting!`](@ref), or to answer how the window is set up.

# Example

    println(describe_settings())

See also `change_setting!`.
"""
function describe_settings end

function describe_settings(; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "describe_settings") do
        settings = find_editor_settings(; editor)
        settings === nothing && return Text("This window has no settings.")
        lines = String[]
        for group in get_settings_groups(settings)
            T = get_settings_group_type(group)
            for description in get_setting_descriptions(T)
                values = description.values isa Tuple ?
                         " (" * join(repr.(description.values), ", ") * ")" : ""
                push!(lines, get_settings_name(T) * "." * String(description.name) * " = " *
                             repr(getproperty(group, description.name)) * ": " *
                             description.text * values)
            end
        end
        Text(join(lines, "\n"))
    end
end

"""
    change_setting!(name, value; editor = get_evaluation_editor()) -> value

Change the setting `name` of the window to `value`, as a person does in the tab of
the settings: the window checks the value against the description of the
setting, writes it, and applies it at once. `name` is the name of a setting, as
[`describe_settings`](@ref) writes it after the group; a name that no group has,
or that two groups have, is refused, and so is a value that does not fit the
setting.

Use it to change how the window looks or works when the person asks for it.

# Example

    println(describe_settings())
    change_setting!(:partial_render, false)

See also `describe_settings`.
"""
function change_setting! end

function change_setting!(name::Symbol, value; editor = get_evaluation_editor())
    run_on_editor_task!(editor; description = "change_setting!") do
        settings = find_editor_settings(; editor)
        settings === nothing && throw(ArgumentError("This window has no settings."))
        groups = [group for group in get_settings_groups(settings)
                  if find_setting_description(get_settings_group_type(group), name) !== nothing]
        isempty(groups) && throw(ArgumentError("No group of the settings has the setting " * repr(name) * "."))
        length(groups) == 1 ||
            throw(ArgumentError(string(length(groups), " groups of the settings have the setting ",
                                       repr(name), ".")))
        group = only(groups)
        description = find_setting_description(get_settings_group_type(group), name)
        convert_setting_value(description, value) === nothing &&
            throw(ArgumentError(repr(value) * " does not fit the setting " * repr(name) * ", a " *
                                string(description.type) *
                                (description.values === nothing ? "" : " in " * repr(description.values)) * "."))
        evaluate_operation(editor, ApplySettingOperation(group, name, value))
        getproperty(group, name)
    end
end

"""
    make_toggle_setting_operation(settings, T, name) -> Operation

The `ApplySettingOperation` that turns the `Bool` setting `name` of the group of
type `T` in `settings` on when it is off, and off when it is on. A `Settings`
with no group of `T` gives `DoNothingOperation`.
"""
function make_toggle_setting_operation(settings::Settings, T::Type{<:SettingsGroup},
                                       name::Symbol)
    group = get(settings.groups, T, nothing)
    group === nothing && return DoNothingOperation()
    ApplySettingOperation(group, name, !getproperty(group, name))
end

# The commands of the settings, with no key: a person runs them from the palette.
# "Show the settings" focuses the tab that shows the settings, or opens one.
@gestures SettingsDocument begin
    nothing => "Show the settings" =>
        InvokeActionOperation(Action("Show the settings";
            callback = editor -> show_document!(doc.settings; title = "Settings", editor)))
    nothing => "Toggle partial render" =>
        make_toggle_setting_operation(doc.settings, RenderSettings, :partial_render)
    nothing => "Toggle repaint outline" =>
        make_toggle_setting_operation(doc.settings, RenderSettings, :debug_dirty)
end
