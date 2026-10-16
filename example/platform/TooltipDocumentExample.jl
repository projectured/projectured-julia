# The content of a tooltip window that shows one layer, the tooltip of one part.
make_tooltip_content_document_example() =
    TooltipContent(; layers = Tuple{String,Document}[("Save", PrimitiveString("Saves the file."))], shown = 1)

# The state of a tooltip window around a string, with no tooltip open.
make_tooltip_window_state_document_example() = TooltipWindowState(; content = PrimitiveString("content"))
