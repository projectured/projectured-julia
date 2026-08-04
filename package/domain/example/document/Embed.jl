# A marker standing in for a document that lives in another file. The stub
# carries the marker source and, once `resolve!` has run, the document it
# evaluated to; unresolved is the honest state for an atom, because resolving
# would need a `LoaderContext` pointing at a real directory and the thing under
# test is the stub's own rendering, not the loader's.
#
# Every source domain has a printer for it (`ReferenceStubToJsonSyntaxLeaf`,
# `…ToJuliaSyntaxLeaf`, `…ToMarkdownSyntaxLeaf`, `…ToXmlSyntaxLeaf`) so that an
# embed reads as a leaf of whatever document it is spliced into.
make_reference_stub_document_example() = ReferenceStub("file(\"example.json\")")
