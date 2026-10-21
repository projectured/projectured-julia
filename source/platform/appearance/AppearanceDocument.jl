# Fragment of `AppearanceModule` — the document that holds the appearance of an
# editor around the document that the editor shows, and its keys.

"""
    AppearanceDocument(appearance, content)

The root document of an editor with the `appearance` wrapper: the `Appearance`
of the editor, and `content`, the document that the editor shows. The
appearance is a part of the document, so a view can show it and a reference can
name it.
"""
@document struct AppearanceDocument <: Document
    appearance::Appearance
    content::Document
end

get_wrapped_document(document::AppearanceDocument) = get_wrapped_document(document.content)

"""
    make_appearance_document(document, appearance) -> AppearanceDocument

`document` inside an `AppearanceDocument` with `appearance`. The selection of
`document` moves to the new root, under `content`.
"""
function make_appearance_document(document, appearance::Appearance)
    wrapped = AppearanceDocument(appearance, document)
    inner = get_selection(document)
    inner === nothing ||
        replace_selection!(wrapped,
            concat_references(ConcreteReference(FieldReferenceStep("content"), EmptyReference()),
                              strip_reference_types(inner)))
    wrapped
end

# The keys of the zoom and of the scales. The content reads each key first, so a
# view that binds one of them, such as the zoom of a `WidgetTransformPane`, keeps
# it. The control, radius and line scales have no key.
@gestures AppearanceDocument begin
    KeyDown(:equals; ctrl) => "Zoom in" => AdjustZoomOperation(doc.appearance, 1)
    KeyDown(:minus; ctrl) => "Zoom out" => AdjustZoomOperation(doc.appearance, -1)
    KeyDown(:zero; ctrl) => "Reset the zoom" => AdjustZoomOperation(doc.appearance, 0)
    KeyDown(:equals; ctrl, alt) => "Make the text larger" =>
        AdjustScaleOperation(doc.appearance, :font_scale, 1)
    KeyDown(:minus; ctrl, alt) => "Make the text smaller" =>
        AdjustScaleOperation(doc.appearance, :font_scale, -1)
    KeyDown(:zero; ctrl, alt) => "Reset the size of the text" =>
        AdjustScaleOperation(doc.appearance, :font_scale, 0)
    KeyDown(:period; ctrl, alt) => "Make the icons larger" =>
        AdjustScaleOperation(doc.appearance, :icon_scale, 1)
    KeyDown(:comma; ctrl, alt) => "Make the icons smaller" =>
        AdjustScaleOperation(doc.appearance, :icon_scale, -1)
    KeyDown(:right_bracket; ctrl, alt) => "Make the spacing larger" =>
        AdjustScaleOperation(doc.appearance, :spacing_scale, 1)
    KeyDown(:left_bracket; ctrl, alt) => "Make the spacing smaller" =>
        AdjustScaleOperation(doc.appearance, :spacing_scale, -1)
    KeyDown(:comma; ctrl) => "Show the appearance" =>
        InvokeActionOperation(Action("Show the appearance";
            callback = editor -> show_document!(doc.appearance; title = "Appearance", editor)))
end

"""
    find_editor_appearance(; editor = get_evaluation_editor()) -> Appearance or nothing

The `Appearance` of `editor`: the one that its `appearance` wrapper holds, or
`nothing` for an editor with no such wrapper.
"""
find_editor_appearance(; editor = get_evaluation_editor()) =
    run_on_editor_task!(() -> editor.document isa AppearanceDocument ? editor.document.appearance : nothing, editor; description = "find_editor_appearance")

# A file keeps that it shows the appearance of the editor, whose values the
# appearance file holds. A load gives the appearance of its editor, and a load with
# no editor, or in an editor with no appearance, the default appearance.
pred_arguments(::Appearance) = (), Pair{Symbol,Any}[]

function make_pred_document(::Type{<:Appearance}, positional, keywords)
    editor = find_evaluation_editor()
    found = editor isa Editor ? find_editor_appearance(; editor) : nothing
    found === nothing ? Appearance() : found
end

get_document_decoration(::Union{AppearanceDocument, Appearance}) =
    DocumentDecoration(; icon = :palette, tooltip = () -> TooltipNote(; title = "Appearance",
                                                                       text = "The zoom and the scales of this window."))
