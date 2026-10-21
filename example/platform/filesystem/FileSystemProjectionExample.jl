function make_filesystem_projection_example(; measure=FontFileMeasure())
    ChainingProjection(
        RecursiveProjection(FileSystemToSyntax()),
        RecursiveProjection(SyntaxToText(
            expanded_marker  = TextString("▾", StyleFont("DejaVu Sans Mono", 20), color_default),
            collapsed_marker = TextString("▸", StyleFont("DejaVu Sans Mono", 20), color_default),
            marker_eligible  = is_filesystem_marker_eligible)),
        TextToGraphics(measure=measure),
    )
end

# Widget presentation: `FileSystem → WidgetTree → Graphics`. The file-system tree
# projects to a single native `WidgetTree` whose nodes each carry a dedicated icon
# glyph + the item's basename; the tree (selection band, chevrons, icons, labels)
# is then rendered to graphics by `WidgetToGraphics`. Clicking / arrowing a row
# maps the selection back through the tree to the file-system node. The example
# shows the tree alone, with no pane tree to open a file in, so Return and a double
# click on a file open nothing.
function make_filesystem_widget_projection_example(; measure=FontFileMeasure())
    font = StyleFont("Ubuntu Mono", 20)
    ChainingProjection(
        RecursiveProjection(FileSystemToWidget(; open_file = nothing)),
        RecursiveProjection(WidgetToGraphics(font; measure=measure)),
    )
end
