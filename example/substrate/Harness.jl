# ═══════════════════════════════════════════════════════════════════════════
# visual-example/Harness.jl
#
# The visual half of the example harness: rendering an example's projected
# output as text on stdout (`print_example` — `print_object` is the visual
# ObjectToSyntax pretty-printer) and as a vector PDF (`write_example_pdf` —
# `write_pdf` is the visual dependency-free Pdf backend). Text measurement is
# SDL-free throughout (`measure_truetype_text` reads the font's own TrueType
# metrics), so this half needs no backend at all. The name-lookup variants live
# in the `ProjecturedExample` umbrella.
# ═══════════════════════════════════════════════════════════════════════════

function print_example(example::Example)
    iomap = print_document(example.projection, example.document)
    output = iomap.output
    println(print_object(output isa Cell ? output[] : output; open_delimiter="{", close_delimiter="}"))
end

# Render an example to a vector PDF. Reuses the example's own projection for
# layout parity with the on-screen / `write_image` view. `write_pdf` needs no
# live backend: it measures text via `measure_truetype_text`, which reads the
# font's own TrueType `hmtx` metrics directly (no SDL, no display server).
function write_example_pdf(example::Example, filename;
                           width=nothing, height=nothing,
                           max_width=1800, max_height=1200, kwargs...)
    write_pdf(example.document, example.projection, filename;
              width=width, height=height,
              max_width=max_width, max_height=max_height,
              measure=measure_truetype_text, kwargs...)
end
