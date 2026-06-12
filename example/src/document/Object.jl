using Projectured.DocumentModule: Document
using Projectured.ReferenceModule: Reference

@document struct Address <: Document
    street::String
    city::String
    zip::String
    selection::Reference
end

@document struct Person <: Document
    name::String
    age::Int
    active::Bool
    score::Float64
    address::Address
    tag::Symbol
    selection::Reference
end

function make_object_document_example()
    Person(
        "Alice",
        30,
        true,
        98.6,
        Address("123 Main St", "Wonderland", "12345", nothing),
        :admin,
        nothing,
    )
end
