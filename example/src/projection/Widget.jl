
function make_widget_projection_example(; measure=sdl_measure_text)
    SequentialProjection(
        RecursiveProjection(WidgetToGraphics(font_ubuntu_regular_24;
                                             measure=measure,
                                             default_fg=(0xee, 0xee, 0xee, 0xff))),
    )
end
