
function make_widget_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(WidgetToGraphics(StyleFont("/usr/share/fonts/truetype/tuffy/tuffy_regular.ttf", 24);
                                             measure=measure,
                                             default_fg=(0xee, 0xee, 0xee, 0xff))),
    )
end
