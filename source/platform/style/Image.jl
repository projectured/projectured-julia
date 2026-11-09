# Fragment of `StyleModule`.
#
# The image document domain. Provides the picture of a file, a memory-backed image
# document and the file document of a picture file. The first two share the
# abstract `ImageDocument` base.
# ── Abstract base ──────────────────────────────────────────────────────────

"""
    ImageDocument

Abstract base type for all image documents.
"""
abstract type ImageDocument <: Document end

# ── ImageInsertion ───────────────────────────────────────────────────────

@document struct ImageInsertion <: ImageDocument
    value::Any = nothing
end

# ── ImageMemory ────────────────────────────────────────────────────────────

"""
    ImageMemory(raw)

A memory-backed image document.  `raw` is a `Cell` holding the image data
directly (e.g. a decoded pixel buffer).
"""
@document struct ImageMemory <: ImageDocument
    raw::Any
end

# ── Image ──────────────────────────────────────────────────────────────────

"""
    Image(filename)

The picture that a file holds, not read yet. `filename` is the path. Making an
`Image` reads nothing and runs no work: its pixels are a background cell, which a
task fills after the frame in which a paint asked for them (`make_background_cell`).
The work decodes the file with `decode_image` and answers the pixels, or the
exception of a file that does not exist or does not decode, as a value.

A print reads plain cells and never the pixels: `natural_size`, the
`(width, height)` of the picture, and `failure`, the exception of the read. Both are
`nothing` until the first answer. A label and a text span put the pixel cell
itself into their `GraphicsImage`, so only the paint of a backend reads it.

The size comes from two reads. `head_size` is a background cell whose work reads the
size from the head of the file with no decode (`read_image_size`), and
[`get_image_natural_size`](@ref) is the call of a print for the size: it asks for the
head while the decode of this read has not answered. `decoded_count` is the
`read_count` whose decode answered, and −1 until the first decode answers. For one
read the decode wins over the head, because the paint draws the pixels of the decode.

`read_count` counts the changes of the file. One more gives the pixel cell and the
head cell a new input: each answers its last answer until the new one comes, and the
next print asks for the head again. `natural_size` and `failure` change only when the
answer differs from what they hold. All fields but `filename` are view state: a save
writes the path only, and undo records none of their changes.

Each `Image` has a `BackgroundSource` of its own for its pixels, so the pictures that
one frame paints decode in parallel. The head cells of all pictures share one source,
so the sizes that one frame asks for are read on one task.

# Example

    picture_1 = Image("media/throughput.png")
    wait_for_cell!(getfield(picture_1, :pixels); editor = nothing)   # (pixels, width, height)
    picture_1.natural_size                                           # (width, height)
"""
@document struct Image <: ImageDocument
    filename::String
    read_count::Int
    pixels::Any
    head_size::Any
    decoded_count::Int
    natural_size::Any
    failure::Any
    source::Any
end

get_view_state_fields(::Type{<:Image}) =
    (:read_count, :pixels, :head_size, :decoded_count, :natural_size, :failure, :source)

Image(filename::AbstractString) = _make_image(filename, _make_image_source())

# The work that reads the sizes of the pictures of one frame from the heads of their
# files off the loop: the size of each path, `nothing` for a file whose head says none,
# or the exception of a file that can not be opened, so one bad file fails no other.
# It holds its work and its description; the demands are in each editor.
const _IMAGE_SIZE_SOURCE =
    BackgroundSource(inputs -> Any[_read_image_head_answer(path) for (path, _) in inputs];
                     description = "the sizes of pictures")

function _read_image_head_answer(path::AbstractString)
    try
        read_image_size(path)
    catch exception
        exception
    end
end

# The picture of `filename` whose pixels `source` reads and whose size `size_source`
# reads. `Image` passes a source of its own for the pixels and the shared source of the
# sizes; a test passes sources whose work it can count.
function _make_image(filename::AbstractString, source::BackgroundSource,
                     size_source::BackgroundSource = _IMAGE_SIZE_SOURCE)
    path = Cell(String(filename))
    read_count = Cell(0)
    holder = Ref{Any}(nothing)
    pixels = make_background_cell(source, () -> (path[], read_count[]);
                                  apply = (inputs, answer) -> ApplyImageAnswerOperation(holder[], last(inputs), answer, true))
    head_size = make_background_cell(size_source, () -> (path[], read_count[]);
                                     apply = (inputs, answer) -> ApplyImageAnswerOperation(holder[], last(inputs), answer, false))
    image = Image(path, read_count, pixels, head_size, Cell(-1), Cell(nothing), Cell(nothing), Cell(source))
    holder[] = image
    image
end

"""
    get_image_natural_size(image::Image)

The `(width, height)` that a print gives `image`, or `nothing` until a size is known.
It asks for the head of the file while the decode of this read has not answered, so a
task reads the size after the frame and the next frame has it; a picture whose decode
answered asks for no head. Outside an editor it asks for nothing.

# Example

    picture_1 = Image("media/throughput.png")
    wait_for_cell!(getfield(picture_1, :head_size); editor = nothing)
    get_image_natural_size(picture_1)    # (width, height)
"""
function get_image_natural_size(image::Image)
    image.decoded_count == image.read_count || getfield(image, :head_size)[]
    image.natural_size
end

# The work that decodes the pictures of one source off the loop: the pixels of
# each path, or the exception of a file that fails, so one bad file fails no other.
_make_image_source() =
    BackgroundSource(inputs -> Any[_read_image_answer(path) for (path, _) in inputs];
                     description = "the pixels of a picture")

function _read_image_answer(path::AbstractString)
    try
        decode_image(path)
    catch exception
        exception
    end
end

# The size of the pixels that an answer holds.
_get_image_answer_size(answer) = (Int(answer[2]), Int(answer[3]))

"""
    ApplyImageAnswerOperation(image, read_count, answer, is_pixel_answer)

Write what a read of `image` found: the size into `natural_size`, or the exception of
the read into `failure`. A cell whose value stays the same is not written. The answer
of a read that a newer read follows is dropped: `read_count` names the read.

`is_pixel_answer` is `true` for the answer of the pixel cell, which writes
`decoded_count` and wins over the head for its read, and `false` for the answer of the
head cell. A size answer for a read whose decode answered is dropped; a size answer of
`nothing` writes nothing; a size clears `failure`. It is a write of view state, so undo
records none.
"""
struct ApplyImageAnswerOperation <: Operation
    image::Image
    read_count::Int
    answer::Any
    is_pixel_answer::Bool
end

function evaluate_operation(editor, operation::ApplyImageAnswerOperation)
    image = operation.image
    operation.read_count == image.read_count || return nothing
    answer = operation.answer
    if operation.is_pixel_answer
        image.decoded_count == operation.read_count || (image.decoded_count = operation.read_count)
    else
        image.decoded_count == operation.read_count && return nothing
        answer === nothing && return nothing
    end
    if answer isa Exception
        isequal(image.failure, answer) || (image.failure = answer)
    else
        size = operation.is_pixel_answer ? _get_image_answer_size(answer) : answer
        image.failure === nothing || (image.failure = nothing)
        isequal(image.natural_size, size) || (image.natural_size = size)
    end
    nothing
end

# A copy of a picture, such as a copy gesture stores, is a new picture of the same path
# that reads nothing, as a load makes. A field-by-field copy would share the source of
# the picture and keep a pixel cell that nothing feeds.
copy_document(policy::CopyPolicy, image::Image) =
    is_descendable_for_copy(policy, image) ? Image(image.filename) : make_copy_placeholder(policy, image)

# A save writes the path of a picture, and a load makes a picture that reads nothing.
pred_arguments(image::Image) = (image.filename,), Pair{Symbol,Any}[]
make_pred_document(::Type{<:Image}, positional, keywords) = Image(only(positional))

# ── set_cell_computation! delegation ───────────────────────────────────────────────────

set_cell_computation!(img::ImageMemory, f::Function) = (set_cell_computation!(getfield(img, :raw), f); img)

# ── ImageFile ──────────────────────────────────────────────────────────────

"""
    ImageFile(filename)

The file document of a picture file: `content` is the [`Image`](@ref) that the file
holds, and `disk` is its state against the disk, as for every file type. A person
does not edit it, so a save writes nothing of it, and a change of the file adds one
to the `read_count` of the picture that the file keeps. Making an `ImageFile` reads
nothing: not a byte of the file, and not its time or its size.

The extensions `.png`, `.jpg`, `.jpeg`, `.bmp` and `.gif` are this type, so
`make_file_tab` and the open of a file make one. `ImageFile(filename)` makes a new
document that no other place shares. A holder that must follow the file asks the
editor for its one file document of the path with `open_file_document!`.

Use it to show a picture file in a card of a dashboard or in a zoom tab. The card
and the tab show the new picture after a program writes the file again.

# Example

    picture_1 = open_file_document!("media/throughput.png")
    card_1 = DashboardCard("Throughput", picture_1)
    dashboard_1 = Dashboard("Charts", Any[card_1])

See also `open_file_document!` and `DashboardCard`.

For the assistant.
"""
@document struct ImageFile <: FileDocument
    filename::String
    content::Any
    disk::FileDiskState = FileDiskState()
end

ImageFile(filename::AbstractString) = ImageFile(String(filename), Image(filename))

get_file_domain(::Type{<:ImageFile}) = Document
is_editable_file_type(::Type{<:ImageFile}) = false
read_file_content(::Type{<:ImageFile}, path::AbstractString) = Image(path)

# A load of the file gives the history a new picture of the same path. The file keeps
# the picture that holds the pixels, which asks for the new ones, and the new picture
# is dropped: nothing read its pixel cell.
function replace_wrapped_document!(image::Image, document)
    (document isa Image && document.filename == image.filename) || return document
    image.read_count += 1
    image
end

"""
    get_shown_picture(content)

What a label or a text span draws for `content`: the picture that a picture file
holds, through its history, and `content` itself for anything else. A holder that
shows a picture file thus draws its picture.

# Example

    picture_1 = get_shown_picture(ImageFile("media/throughput.png"))   # an Image
"""
get_shown_picture(content) = content isa ImageFile ? get_edited_document(content) : content
