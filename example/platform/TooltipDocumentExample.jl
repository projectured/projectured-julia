# The content of a tooltip window that shows one layer, the tooltip of one part.
make_tooltip_content_document_example() =
    TooltipContent(; layers = Tuple{String,Document}[("Save", PrimitiveString("Saves the file."))], shown = 1)

# What a part says about itself, piece by piece: its name, its key, what it does,
# a fact and a hint.
make_tooltip_note_document_example() =
    TooltipNote(; title = "Refresh", keys = Any[KeyDownPattern(:f5; modifiers = Symbol[])],
                text = "Read the frame again.", facts = ["Rows" => "12480"],
                hint = "The filter and the sort stay.")

# The state of a tooltip window around a string, with no tooltip open.
make_tooltip_window_state_document_example() = TooltipWindowState(; content = PrimitiveString("content"))
