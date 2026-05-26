# Plan: `write_image` — Save a Projected Document to an Image File

Analogous to `print_object` (which chains `ObjectToSyntax → SyntaxToText → TextToString`
internally), but for graphics: the caller provides their own projection and
`write_image` drives `projection_print`, renders the resulting `GraphicsCanvas`
offscreen with SDL2, and saves it to disk.

---

## Design overview

| Component | Location | Role |
|---|---|---|
| `write_image(document, projection, filename; ...)` | `Sdl.jl` | Primary function: runs the pipeline, renders, saves |
| `write_image(canvas, filename; ...)` | `Sdl.jl` | Low-level overload: render a canvas you already have |
| `GraphicsCanvasToImageFile` | `Sdl.jl` | Printer-only projection; same effect via pipeline composition |
| Example | `example/src/` | `graphics_image_example` — calls `write_image` with a JSON projection |
| Test | `test/src/projection/GraphicsToFileTest.jl` | Verifies file is created and non-empty |

All SDL2-specific code lives in `SdlBackendModule` (`Sdl.jl`) because the
implementation must call the private `_render_canvas!` helper and construct a
`SdlWindowHandle` with a software renderer.

---

## Step 1: Add imports to `SdlBackendModule`

**File:** `program/src/backend/Sdl.jl`

Add to the existing import block:

```julia
import ..ImageModule: ImageFile
import ..ProjectionApiModule: projection_print, Projection
import ..IoMapModule: SimpleIoMap
```

(`projection_print` is already used indirectly; make it explicit so the
`write_image` overload and `GraphicsCanvasToImageFile` compile without
ambiguity.)

---

## Step 2: Add `write_image(canvas, filename; ...)`

**File:** `program/src/backend/Sdl.jl` — after the existing `sdl_render_canvas`
stub.

```julia
"""
    write_image(canvas::GraphicsCanvas, filename::AbstractString;
                width::Integer = 800, height::Integer = 600,
                background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff)) -> ImageFile

Low-level overload. Render `canvas` to an offscreen SDL2 software renderer and
save the result to `filename` (BMP format). Returns an `ImageFile` document.
No window is required; SDL2 + SDL_ttf are initialized lazily.

Supported extensions: `.bmp` (case-insensitive).

Most callers should use `write_image(document, projection, filename)` instead.
"""
function write_image(canvas::GraphicsCanvas, filename::AbstractString;
                     width::Integer = 800,
                     height::Integer = 600,
                     background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff))
    SDL_Init(SDL_INIT_VIDEO)
    TTF_Init()

    surface = SDL_CreateRGBSurface(UInt32(0), Int32(width), Int32(height), Int32(32),
                                   UInt32(0x00FF0000), UInt32(0x0000FF00),
                                   UInt32(0x000000FF), UInt32(0xFF000000))
    @assert surface != C_NULL "SDL surface creation failed: $(unsafe_string(SDL_GetError()))"

    renderer = SDL_CreateSoftwareRenderer(surface)
    @assert renderer != C_NULL "SDL software renderer creation failed: $(unsafe_string(SDL_GetError()))"

    h = SdlWindowHandle(C_NULL, renderer, Dict{Tuple{String,Int}, Ptr{TTF_Font}}())
    r, g, b, a = background
    SDL_SetRenderDrawColor(renderer, r, g, b, a)
    SDL_RenderClear(renderer)

    _render_canvas!(h, canvas, 0, 0, Int(width), Int(height))

    ext = lowercase(splitext(filename)[2])
    if ext == ".bmp"
        rw = SDL_RWFromFile(filename, "wb")
        @assert rw != C_NULL "Failed to open output file: $filename"
        SDL_SaveBMP_RW(surface, rw, Int32(1))   # freedst=1 — SDL closes the RW handle
    else
        SDL_DestroyRenderer(renderer)
        SDL_FreeSurface(surface)
        error("write_image: unsupported format \"$ext\" (only .bmp is supported)")
    end

    for (_, font) in h.font_cache
        TTF_CloseFont(font)
    end
    SDL_DestroyRenderer(renderer)
    SDL_FreeSurface(surface)

    ImageFile(filename)
end
```

---

## Step 3: Add `write_image(document, projection, filename; ...)`

**File:** `program/src/backend/Sdl.jl` — immediately after Step 2.

This is the primary function. The projection is provided by the caller — it
must produce a `GraphicsCanvas` as its output.

```julia
"""
    write_image(document, projection, filename::AbstractString;
                width::Integer = 800, height::Integer = 600,
                background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff)) -> ImageFile

Run `projection_print(projection, document)` to obtain a `GraphicsCanvas`,
then render it offscreen and save to `filename` (BMP). The projection is
provided by the caller, typically the same pipeline used to open a live editor
window. Returns an `ImageFile` pointing at the saved file.

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
)
write_image(doc, proj, "snapshot.bmp"; width=1200, height=800)
```

Throws if the projection output is not a `GraphicsCanvas`.
"""
function write_image(document, projection, filename::AbstractString;
                     width::Integer = 800,
                     height::Integer = 600,
                     background::NTuple{4,UInt8} = (0x00, 0x00, 0x00, 0xff))
    iomap = projection_print(projection, document)
    canvas = iomap.output
    canvas isa GraphicsCanvas ||
        error("write_image: projection output is $(typeof(canvas)), expected GraphicsCanvas")
    write_image(canvas, filename; width=width, height=height, background=background)
end
```

---

## Step 4: Add `GraphicsCanvasToImageFile` projection

**File:** `program/src/backend/Sdl.jl` — after Step 3.

An alternative interface: compose the save step directly into a
`SequentialProjection` pipeline rather than calling `write_image` after the
fact. The output document is an `ImageFile`. Has no reader.

```julia
"""
    GraphicsCanvasToImageFile(filename; width=800, height=600,
                               background=(0x00,0x00,0x00,0xff))

Printer-only projection. On `projection_print` it renders the input
`GraphicsCanvas` offscreen and saves to `filename` (BMP). The `output` field
of the returned `SimpleIoMap` is an `ImageFile` document. Has no reader.

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
    GraphicsCanvasToImageFile("output.bmp"; width=1200, height=800),
)
iomap = projection_print(proj, doc)   # writes output.bmp
# iomap.output isa ImageFile
```
"""
struct GraphicsCanvasToImageFile <: Projection
    filename::String
    width::Int
    height::Int
    background::NTuple{4, UInt8}
end

function GraphicsCanvasToImageFile(filename::AbstractString;
                                    width::Integer = 800,
                                    height::Integer = 600,
                                    background = (0x00, 0x00, 0x00, 0xff))
    GraphicsCanvasToImageFile(String(filename), Int(width), Int(height),
                               NTuple{4,UInt8}(background))
end

function projection_print(p::GraphicsCanvasToImageFile,
                           canvas::GraphicsCanvas, recursion, reference)
    output = write_image(canvas, p.filename;
                         width=p.width, height=p.height, background=p.background)
    SimpleIoMap(p, canvas, output)
end

function map_reference_forward(::GraphicsCanvasToImageFile, iomap, reference)
    nothing
end

function map_reference_backward(::GraphicsCanvasToImageFile, iomap, reference)
    nothing
end
```

---

## Step 5: Update exports in `Sdl.jl`

```julia
# before
export SdlBackend, sdl_measure_text, sdl_render_canvas

# after
export SdlBackend, sdl_measure_text, sdl_render_canvas, write_image, GraphicsCanvasToImageFile
```

---

## Step 6: Update `Projectured.jl`

```julia
# using line — before
using .SdlBackendModule: SdlBackend, sdl_measure_text, sdl_render_canvas

# using line — after
using .SdlBackendModule: SdlBackend, sdl_measure_text, sdl_render_canvas,
                          write_image, GraphicsCanvasToImageFile

# export line — before
export SdlBackend, sdl_measure_text, sdl_render_canvas

# export line — after
export SdlBackend, sdl_measure_text, sdl_render_canvas, write_image, GraphicsCanvasToImageFile
```

---

## Step 7: Add example

### 7a. New file `example/src/projection/Graphics.jl`

```julia
function make_graphics_image_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure=measure),
    )
end
```

(The same pipeline used in `run_example` — no `GraphicsCanvasToImageFile` needed
here since the example calls `write_image(doc, proj, filename)` directly.)

### 7b. New entry in `example/src/Examples.jl`

```julia
const graphics_image_example = Example(
    "graphics_image",
    make_json_document_example,
    make_graphics_image_projection_example,
)
```

Add `graphics_image_example` to the `examples` vector.

Add a convenience wrapper next to `run_example` / `print_example`:

```julia
function write_image_example(example::Example, filename;
                              width=1200, height=800, kwargs...)
    write_image(example.document, example.projection, filename;
                width=width, height=height, kwargs...)
end

function write_image_example(name="json", filename=tempname()*".bmp"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    write_image_example(examples[idx], filename; kwargs...)
end
```

### 7c. Include and export in `example/src/ProjecturedExample.jl`

```julia
include(joinpath(_EXAMPLE_DIR, "projection", "Graphics.jl"))
export make_graphics_image_projection_example
```

---

## Step 8: Add test

**New file:** `test/src/projection/GraphicsToFileTest.jl`

```julia
using Test, Projectured, ProjecturedExample

@testset "write_image" begin

    @testset "write_image(document, projection, filename)" begin
        doc  = make_json_document_example()
        proj = make_graphics_image_projection_example()
        filename = tempname() * ".bmp"
        img = write_image(doc, proj, filename; width=400, height=300)
        @test img isa ImageFile
        @test isfile(filename)
        @test filesize(filename) > 0
        rm(filename)
    end

    @testset "write_image(canvas, filename)" begin
        canvas = GraphicsCanvas()
        filename = tempname() * ".bmp"
        img = write_image(canvas, filename; width=100, height=80)
        @test img isa ImageFile
        @test isfile(filename)
        @test filesize(filename) > 0
        rm(filename)
    end

    @testset "GraphicsCanvasToImageFile projection" begin
        doc  = make_json_document_example()
        filename = tempname() * ".bmp"
        proj = SequentialProjection(
            make_graphics_image_projection_example(),
            GraphicsCanvasToImageFile(filename; width=400, height=300),
        )
        iomap = projection_print(proj, doc)
        @test iomap.output isa ImageFile
        @test isfile(filename)
        @test filesize(filename) > 0
        rm(filename)
    end

    @testset "unsupported format raises error" begin
        canvas = GraphicsCanvas()
        @test_throws ErrorException write_image(canvas, tempname() * ".png")
    end

end
```

Register in `test/src/ProjecturedTest.jl`:

```julia
include(joinpath(_TEST_DIR, "projection", "GraphicsToFileTest.jl"))
```

---

## Step 9: Update `guide/document/graphics.md`

```markdown
## Saving to a file

`write_image` renders a projected document to a BMP file without opening a
window. Provide the same projection you would use for `run_example`:

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
)
write_image(doc, proj, "snapshot.bmp"; width=1200, height=800)
```

If you already have a `GraphicsCanvas` in hand, pass it directly:

```julia
write_image(canvas, "snapshot.bmp"; width=800, height=600)
```

To compose the save step into a pipeline, use `GraphicsCanvasToImageFile` as
the final projection — its output is an `ImageFile` document:

```julia
proj = SequentialProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText()),
    TextToGraphics(measure=sdl_measure_text),
    GraphicsCanvasToImageFile("snapshot.bmp"; width=1200, height=800),
)
iomap = projection_print(proj, doc)
# iomap.output isa ImageFile
```

`GraphicsCanvasToImageFile` has no reader — it is a write-only, side-effecting
projection.

File format roadmap: BMP is built into SDL2 and needs no extra dependencies.
PNG output is a future extension (requires SDL_image).
```

---

## Validation

```
grep -n "write_image\|GraphicsCanvasToImageFile" program/src/backend/Sdl.jl
grep -n "write_image\|GraphicsCanvasToImageFile" program/src/Projectured.jl
julia --project=program -e 'using Projectured; @assert isdefined(Projectured, :write_image)'
julia --project=test -e 'using ProjecturedTest; test_all()'
```
