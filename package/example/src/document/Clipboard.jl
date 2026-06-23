# A ClipboardSlice wrapping a small JSON array. The slice starts empty, so the
# round trip is: select a sub-document, Ctrl+C (or Ctrl+X to cut) to store it in
# the slice, Ctrl+/ to flip the view to the stored slice, and Ctrl+V to paste it
# over the current selection. See make_clipboard_projection_example for the keys.
function make_clipboard_document_example()
    content = JsonArray(
        JsonString("alpha"),
        JsonNumber(42),
        JsonArray(JsonBool(true), JsonNull(), JsonNumber(7)),
        JsonString("omega"),
    )
    ClipboardSlice(content)
end
