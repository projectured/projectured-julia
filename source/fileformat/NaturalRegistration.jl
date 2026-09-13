# An embed draws as what it embeds, and the two rows that say so are this
# package's rather than the renderer's: a stub and a file document are its
# documents. Registered on load, from here, because Julia calls `__init__` on a
# package's top-level module only.
#
# The bare rows go to the to-syntax table, which the fabric consumes. The card
# rows go to the to-graphics table, because a card is a widget and belongs in a
# to-graphics row — and only there: the save path goes through the bare ones and
# stays by-marker.
function __init__()
    NaturalModule.register_natural_syntax!(
        SerializationModule.ReferenceStub => FileFormatModule.ReferenceStubToSyntax(),
        SerializationModule.FileDocument  => FileFormatModule.FileDocumentToSyntax())
    NaturalModule.register_natural_graphics!(:fileformat, (; measure) -> Pair{Type,Any}[
        SerializationModule.ReferenceStub =>
            FileFormatModule.ReferenceStubToSyntax(unforced = :prose, wrap = :card),
        SerializationModule.FileDocument =>
            FileFormatModule.FileDocumentToSyntax(unforced = :prose, wrap = :card)])
    nothing
end
