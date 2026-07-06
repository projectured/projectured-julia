using Projectured.DocumentModule: Document
using Projectured.DocumentModule: @document
using Projectured.ReferenceModule: Reference

# A small settings object whose scalar Cell fields ObjectToWidget reflects into
# an editable widget form: the String becomes an editable text field, each Bool
# a checkbox. Typing edits the (single) text field; clicking a checkbox toggles
# it.
@document struct SearchSettings
    query::String
    case_insensitive::Bool
    whole_word::Bool
    selection::Reference
end

function make_object_to_widget_document_example()
    SearchSettings("dolor", false, true, nothing)
end

# A *nested* settings object exercising the recursive form: a sub-struct
# (`window`) renders as a collapsible card holding its own label|control grid, and
# a vector (`tags`) renders as a collapsible card holding a vertical list. Scalar
# fields at every level whose backing is a `Cell` stay editable.
@document struct WindowSettings
    title::String
    width::Int
    height::Int
    visible::Bool
    selection::Reference
end

@document struct AppSettings
    name::String
    dark_mode::Bool
    window::WindowSettings
    tags::Vector
    selection::Reference
end

function make_nested_object_to_widget_document_example()
    AppSettings("MyApp", true,
                WindowSettings("Main", 800, 600, true, nothing),
                Any["alpha", "beta"], nothing)
end
