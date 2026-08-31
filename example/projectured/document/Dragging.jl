# Dragging example document: a flat JSON array wrapped in a DraggingState so its
# elements can be reordered by drag-and-drop. The wrapper is transparent — the
# array renders exactly as the plain `json` example would; DraggingProjection
# only adds the press → drag → drop gesture handling on top.
function make_dragging_document_example()
    DraggingState(
        JsonArray(
            JsonString("apple"),
            JsonString("banana"),
            JsonString("cherry"),
            JsonString("date"),
            JsonString("elderberry"),
        ),
    )
end
