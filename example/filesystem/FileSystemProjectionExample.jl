function make_filesystem_projection_example(; measure=measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(FileSystemToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", font_dejavu_monospace_regular_20, color_default),
            collapsed_marker = TextString("▸", font_dejavu_monospace_regular_20, color_default),
            marker_eligible  = filesystem_marker_eligible)),
        TextToGraphics(measure=measure),
    )
end

# Widget presentation: `FileSystem → WidgetTree → Graphics`. The file-system tree
# projects to a single native `WidgetTree` whose nodes each carry a dedicated icon
# glyph + the item's basename; the tree (selection band, chevrons, icons, labels)
# is then rendered to graphics by `WidgetToGraphics`. Clicking / arrowing a row
# maps the selection back through the tree to the file-system node.
function make_filesystem_widget_projection_example(; measure=measure_truetype_text)
    font = font_ubuntu_monospace_regular_20
    ChainingProjection(
        RecursiveProjection(FileSystemToWidget()),
        WidgetToGraphics(font; measure=measure),
    )
end
