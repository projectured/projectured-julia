struct Address
    street::String
    city::String
    zip::String
end

struct Person
    name::String
    age::Int
    active::Bool
    score::Float64
    address::Address
    tag::Symbol
end

function make_object_document_example()
    Person(
        "Alice",
        30,
        true,
        98.6,
        Address("123 Main St", "Wonderland", "12345"),
        :admin,
    )
end
