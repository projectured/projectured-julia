# Fragment of `AssistantModule` — a picture in the draft: the "Picture" button,
# and a part with no text that becomes a picture when the person sends it.

"""
    AddDraftPictureOperation(assistant)

The "Picture" button of the composer: a picture of the part that the person
selected as a whole, with Alt+click, or else of the window, goes into the draft
of `assistant` as a part before the text that the person types
(`write_part_picture`, `write_window_picture`). With no window, or no backend
that writes an image, it does nothing.
"""
struct AddDraftPictureOperation <: Operation
    assistant::Assistant
end

# It names the assistant that it acts on, so no projection reroots it.
OperationModule.is_self_contained_operation(::AddDraftPictureOperation) = true

function evaluate_operation(editor, op::AddDraftPictureOperation)
    editor isa Editor || return nothing
    filename = _make_picture_filename()
    _write_selection_picture(editor, filename) === nothing && return nothing
    evaluate_operation(editor, InsertDraftDocumentOperation(op.assistant.draft, ImageFile(filename)))
end

# A picture of the part that the person selected as a whole, or else of the window
# that shows the selection.
function _write_selection_picture(editor, filename::AbstractString)
    selection = get_selection(editor.document)
    picture = is_whole_selection(editor.document, selection) ?
              write_part_picture(editor, selection, filename) : nothing
    picture === nothing ? write_window_picture(editor, selection, filename) : picture
end

"""
    register_picture_tools!(set) -> set

Add the tool `take_picture` to `set`: a picture of what the editor shows, as a
PNG file in the folder of pictures, which the tool answers as an `LlmImage`. Its
`part` is `"window"`, the window, or `"selection"`, the part that the person
selected as a whole with Alt+click, or the window when the person selected no
whole part. The MCP server gives the picture to an agent as an image.
"""
function register_picture_tools!(set)
    register_tool!(set, Tool(
        "take_picture";
        description =
            "Take a picture of what the editor shows: the window, or the part that the person " *
            "selected. Use it to see what has no text, such as a plot, a layout or a widget.",
        parameters = [(name = "part", type = "string", required = false,
                       description = "\"window\" (the default), or \"selection\": the part that the " *
                                     "person selected with Alt+click, or the window when there is none")],
        handler = (editor, args) -> _take_picture(editor, get(args, "part", "window"))))
    set
end

function _take_picture(editor, part)
    editor isa Editor || return "This editor shows no window."
    part in ("window", "selection") || return "The part is \"window\" or \"selection\", not $(repr(part))."
    filename = _make_picture_filename()
    picture = part == "selection" ? _write_selection_picture(editor, filename) :
              write_window_picture(editor, get_selection(editor.document), filename)
    picture === nothing && return "The editor can take no picture: it shows no window, or no backend writes an image."
    LlmImage("image/png", read(picture.filename))
end

# A part of the draft that has no text, such as a plot that the person pasted,
# becomes a picture of it, which the backend writes as a tab draws the part
# (`NaturalToGraphics`); a model and an agent see the picture. A part that the
# backend can not write stays as it is.
function _make_part_pictures!(draft::ConversationDraft)
    for part in collect(draft.parts)
        content = part.content
        (content isa ImageDocument || has_text_form(content)) && continue
        filename = _make_picture_filename()
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

# A new name for the file of a picture, in the folder of pictures of the user:
# `$XDG_CACHE_HOME/projectured/pictures`, by default `~/.cache/projectured/pictures`.
function _make_picture_filename()
    cache = get(ENV, "XDG_CACHE_HOME", "")
    isempty(cache) && (cache = joinpath(homedir(), ".cache"))
    directory = mkpath(joinpath(cache, "projectured", "pictures"))
    stem = "picture-" * Libc.strftime("%Y%m%d-%H%M%S", time())
    filename = joinpath(directory, stem * ".png")
    count = 1
    while isfile(filename)
        count += 1
        filename = joinpath(directory, stem * "-$(count).png")
    end
    filename
end
