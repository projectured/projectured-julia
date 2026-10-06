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
"""
function find_editor_settings(; editor = get_evaluation_editor())
    document = editor.document
    for _ in 1:8
        document isa SettingsDocument && return document.settings
        hasproperty(document, :content) || return nothing
        document = document.content
    end
    nothing
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
