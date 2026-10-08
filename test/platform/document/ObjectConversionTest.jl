# A plain value copied into a document of a schema and back, field by field: a
# flat value, a nested value, a vector of values and a vector of structs, a schema
# that shows a part of a value, a schema field that the value does not have, and
# a copy that shares no object with the value.

struct ConvWindow
    title::String
    width::Int
end

struct ConvHost
    address::String
end

struct ConvServer
    name::String
    capacity::Int
    window::ConvWindow
    tags::Vector{String}
    hosts::Vector{ConvHost}
end

@document struct ConvWindowForm
    title::String
    width::Int
end

@document struct ConvHostForm
    address::String
end

@document struct ConvServerForm
    name::String
    capacity::Int
    window::ConvWindowForm
    tags::Vector
    hosts::Vector{ConvHostForm}
end

# A schema that shows a part of the value.
@document struct ConvNameForm
    name::String
end

# A schema with a field that the value does not have.
@document struct ConvWrongForm
    name::String
    missing_field::Int
end

_conv_server() = ConvServer("gateway", 4, ConvWindow("Main", 800), ["alpha", "beta"],
                            [ConvHost("10.0.0.1"), ConvHost("10.0.0.2")])

_conv_equal(a::ConvServer, b::ConvServer) =
    a.name == b.name && a.capacity == b.capacity && a.window == b.window &&
    a.tags == b.tags && a.hosts == b.hosts

function test_object_conversion()
@testset "ObjectConversion" begin

    @testset "a flat field takes the value of the field of the same name" begin
        form = convert_object_to_document(ConvServerForm, _conv_server())
        @test form isa ConvServerForm
        @test form.name == "gateway"
        @test form.capacity == 4
        @test getfield(form, :name) isa AbstractCell
    end

    @testset "a nested value converts to the schema that the field declares" begin
        form = convert_object_to_document(ConvServerForm, _conv_server())
        @test form.window isa ConvWindowForm
        @test form.window.title == "Main"
        @test form.window.width == 800
    end

    @testset "a vector copies its values and converts its structs" begin
        form = convert_object_to_document(ConvServerForm, _conv_server())
        @test collect(form.tags) == ["alpha", "beta"]
        hosts = collect(form.hosts)
        @test length(hosts) == 2
        @test all(host -> host isa ConvHostForm, hosts)
        @test hosts[2].address == "10.0.0.2"
    end

    @testset "the way back makes the plain value again, with the edits" begin
        server = _conv_server()
        form = convert_object_to_document(ConvServerForm, server)
        @test _conv_equal(convert_document_to_object(ConvServer, form), server)
        form.name = "gw2"
        form.window.width = 1024
        back = convert_document_to_object(ConvServer, form)
        @test back isa ConvServer
        @test back.name == "gw2"
        @test back.window == ConvWindow("Main", 1024)
        @test back.tags isa Vector{String}
        @test back.hosts == server.hosts
        @test server.name == "gateway"
    end

    @testset "a schema shows a part of a value, and the way back takes the rest from a base" begin
        server = _conv_server()
        form = convert_object_to_document(ConvNameForm, server)
        form.name = "gw2"
        back = convert_document_to_object(ConvServer, form; base = server)
        @test back.name == "gw2"
        @test back.capacity == 4
        @test back.window == server.window
        @test_throws ArgumentError convert_document_to_object(ConvServer, form)
    end

    @testset "a field of the schema that the value does not have is an error" begin
        @test_throws ArgumentError convert_object_to_document(ConvWrongForm, _conv_server())
    end

    @testset "the copy shares no object with the value" begin
        server = _conv_server()
        form = convert_object_to_document(ConvNameForm, server)
        back = convert_document_to_object(ConvServer, form; base = server)
        push!(back.tags, "gamma")
        @test server.tags == ["alpha", "beta"]
    end

end
end # test_object_conversion
