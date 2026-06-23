using Projectured.DocumentModule: Document, @document
using Projectured.ReferenceModule: Reference

# A small settings object whose scalar Cell fields ObjectToWidget reflects into
# an editable widget form: the String becomes an editable text field, each Bool
# a checkbox. Typing edits the (single) text field; clicking a checkbox toggles
# it.
@document struct SearchSettings <: Document
    query::String
    case_insensitive::Bool
    whole_word::Bool
    selection::Reference
end

function make_object_to_widget_document_example()
    SearchSettings("dolor", false, true, nothing)
end
