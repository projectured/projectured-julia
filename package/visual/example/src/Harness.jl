# ═══════════════════════════════════════════════════════════════════════════
# visual-example/src/Harness.jl
#
# The visual half of the example harness: rendering an example's projected
# output as text on stdout (`print_example` — `print_object` is the visual
# ObjectToSyntax pretty-printer) and as a vector PDF (`write_example_pdf` —
# `write_pdf` is the visual dependency-free Pdf backend; SDL is only reached
# through the `make_backend` seam for its font metrics). The name-lookup
# variants live in the `ProjecturedExample` umbrella.
# ═══════════════════════════════════════════════════════════════════════════

function print_example(example::Example)
    iomap = print_document(example.projection, example.document)
    output = iomap.output
    println(print_object(output isa Cell ? output[] : output; open_delimiter="{", close_delimiter="}"))
end

# Render an example to a vector PDF. Reuses the example's own (SDL-measured)
# projection for layout parity with the on-screen / `write_image` view; unlike
# `write_image`, `write_pdf` does not initialize SDL itself, so we bring it up
# here for the projection's `truetype_measure_text`.
function write_example_pdf(example::Example, filename;
                           width=nothing, height=nothing,
                           max_width=1800, max_height=1200, kwargs...)
    initialize_backend!(make_backend(:sdl))
    write_pdf(example.document, example.projection, filename;
              width=width, height=height,
              max_width=max_width, max_height=max_height,
              measure=truetype_measure_text, kwargs...)
end
