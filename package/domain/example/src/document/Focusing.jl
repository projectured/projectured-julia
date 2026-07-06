function make_focusing_document_example()
    JsonArray(
        JsonString("alpha"),
        JsonNumber(42),
        JsonArray(JsonBool(true), JsonNull(), JsonNumber(7)),
        JsonString("omega"),
    )
end
