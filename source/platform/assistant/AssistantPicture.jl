# Fragment of `AssistantModule` — a picture in the draft: the "Picture" button,
# a part with no text that becomes a picture when the person sends it, and the
# picture that a model sees for the file of a picture.

"""
    AddDraftPictureOperation(assistant)

The "Picture" button of the composer: a picture of the part that the person
selected as a whole, with Alt+double click, or else of the window, goes into the draft
of `assistant` as a part before the text that the person types
(`write_selection_picture`, `write_window_picture`). With no window, or no backend
that writes an image, it does nothing.
"""
struct AddDraftPictureOperation <: Operation
    assistant::Assistant
end

# It names the assistant that it acts on, so no projection reroots it.
OperationModule.is_self_contained_operation(::AddDraftPictureOperation) = true

function evaluate_operation(editor, op::AddDraftPictureOperation)
    editor isa Editor || return nothing
    filename = make_picture_filename()
    picture = write_selection_picture(; editor, filename)
    picture === nothing && (picture = write_window_picture(; editor, filename))
    picture === nothing && return nothing
    evaluate_operation(editor, InsertDraftDocumentOperation(op.assistant.draft, ImageFile(filename)))
end

# The code of a model that answers the file of a picture, such as a verb that writes
# a picture of the window, answers the picture, which the model sees.
get_model_image(image::ImageFile) = _read_picture(image)

# A part of the draft that has no text, such as a plot that the person pasted,
# becomes a picture of it, which the backend writes as a tab draws the part
# (`NaturalToGraphics`); a model and an agent see the picture. A part that the
# backend can not write stays as it is.
function _make_part_pictures!(draft::ConversationDraft)
    for part in collect(draft.parts)
        content = part.content
        (content isa Union{ImageDocument, ImageFile} || has_text_form(content)) && continue
        filename = make_picture_filename()
        _write_document_picture(content, filename) === nothing && continue
        part.content = ImageFile(filename)
    end
    nothing
end

function _write_document_picture(document, filename::AbstractString)
    projection = NaturalToGraphics(; measure = FontFileMeasure())
    applicable(write_image, document, projection, filename) || return nothing
    try
        write_image(document, projection, filename)
    catch exception
        is_fault_exception(exception) || rethrow()
        @warn "The picture of a part could not be written." exception
        nothing
    end
end
