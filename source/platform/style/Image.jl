# Fragment of `StyleModule`.
#
# The image document domain. Provides file-backed and memory-backed image
# documents. Both subtypes share the abstract `ImageDocument` base.
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

# ── ImageFile ──────────────────────────────────────────────────────────────

"""
    ImageFile(filename)

A file-backed image document.  `filename` is a `Cell` holding a `String` path
and `raw` is a `Cell` holding the decoded image data (or `nothing` until loaded).
"""
@document struct ImageFile <: ImageDocument
    filename::String
    raw::Any
end

# Only `raw` needs filling; the trailing `selection` is filled by the macro.
ImageFile(filename::AbstractString) = ImageFile(Cell(filename), Cell(nothing))

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

A print reads two plain cells and never the pixels: `natural_size`, the
`(width, height)` of the pixels, and `failure`, the exception of the read. Both are
`nothing` until the first answer. A label and a text span put the pixel cell
itself into their `GraphicsImage`, so only the paint of a backend reads it.

`read_count` counts the changes of the file. One more gives the pixel cell a new
input: it answers its last pixels until the new ones come, and the next paint
asks again. `natural_size` and `failure` change only when the answer differs
from what they hold. All of them are view state: a save writes the path only, and
undo records none of their changes.

Each `Image` has a `BackgroundSource` of its own, so the pictures that one frame
paints decode in parallel.

# Example

    picture_1 = Image("media/throughput.png")
    wait_for_cell!(getfield(picture_1, :pixels); editor = nothing)   # (pixels, width, height)
    picture_1.natural_size                                           # (width, height)
"""
@document struct Image <: ImageDocument
    filename::String
    read_count::Int
    pixels::Any
    natural_size::Any
    failure::Any
    source::Any
end

get_view_state_fields(::Type{<:Image}) = (:read_count, :pixels, :natural_size, :failure, :source)

Image(filename::AbstractString) = _make_image(filename, _make_image_source())

# The picture of `filename` whose pixels `source` reads. `Image` passes a source of
# its own; a test passes one whose work it can count.
function _make_image(filename::AbstractString, source::BackgroundSource)
    path = Cell(String(filename))
    read_count = Cell(0)
    holder = Ref{Any}(nothing)
    pixels = make_background_cell(source, () -> (path[], read_count[]);
                                  apply = (inputs, answer) -> ApplyImageAnswerOperation(holder[], last(inputs), answer))
    image = Image(path, read_count, pixels, Cell(nothing), Cell(nothing), Cell(source))
    holder[] = image
    image
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
    ApplyImageAnswerOperation(image, read_count, answer)

Write what a read of `image` found: the size of its pixels into `natural_size`, or
the exception of the read into `failure`. A cell whose value stays the same is not
written. The answer of a read that a newer read follows is dropped: `read_count`
names the read. It is a write of view state, so undo records none.
"""
struct ApplyImageAnswerOperation <: Operation
    image::Image
    read_count::Int
    answer::Any
end

function evaluate_operation(editor, operation::ApplyImageAnswerOperation)
    image = operation.image
    operation.read_count == image.read_count || return nothing
    answer = operation.answer
    if answer isa Exception
        isequal(image.failure, answer) || (image.failure = answer)
    else
        size = _get_image_answer_size(answer)
        image.failure === nothing || (image.failure = nothing)
        isequal(image.natural_size, size) || (image.natural_size = size)
    end
    nothing
end

# A save writes the path of a picture, and a load makes a picture that reads nothing.
pred_arguments(image::Image) = (image.filename,), Pair{Symbol,Any}[]
make_pred_document(::Type{<:Image}, positional, keywords) = Image(only(positional))

# ── set_cell_computation! delegation ───────────────────────────────────────────────────

set_cell_computation!(img::ImageFile,   f::Function) = (set_cell_computation!(getfield(img, :raw), f); img)
set_cell_computation!(img::ImageMemory, f::Function) = (set_cell_computation!(getfield(img, :raw), f); img)
