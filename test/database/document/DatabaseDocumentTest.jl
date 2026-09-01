# The database domain: its documents and its adapter seam.
#
# Nothing here touches a database. The point of the seam is that the documents,
# the query spec and the operations exist without a driver — the live ODBC
# adapter is an opt-in package that registers a method on `make_database_adapter`
# when it loads. So this suite asserts the shape of the seam and what happens
# when nobody has filled it in.

using Test

# A concrete adapter that implements none of the seam. Declared at file scope
# because a `struct` cannot be declared inside a `@testset` body.
struct UnimplementedAdapter <: DatabaseAdapter end

"""
    test_database_documents()

The credentials/instance documents, the query spec, and the `make_database_adapter`
seam's behaviour with and without a registered adapter.
"""
function test_database_documents()
@testset "database documents and the adapter seam" begin

    @testset "credentials own their keyword constructor" begin
        # No field declares a default, so the macro generates no keyword form
        # and the hand-written one coerces both arguments to String.
        c = DatabaseCredentials(user = "someone", password = "secret")
        @test c.user == "someone"
        @test c.password == "secret"
        @test DatabaseCredentials("a", "b").user == "a"
    end

    @testset "an instance defaults its host and port" begin
        c = DatabaseCredentials(user = "u", password = "p")
        d = DatabaseInstance(database = "shop", credentials = c)
        @test d.database == "shop"
        @test d.host == "localhost"
        @test d.port == 5432
        @test d.credentials.user == "u"

        # `database` and `credentials` are the two fields without a default, so
        # they are the two required keywords.
        @test_throws Exception DatabaseInstance(database = "shop")
    end

    @testset "an instance overrides what it names" begin
        c = DatabaseCredentials(user = "u", password = "p")
        d = DatabaseInstance(database = "shop", host = "db.internal",
                             port = 5433, credentials = c)
        @test d.host == "db.internal"
        @test d.port == 5433
    end

    @testset "a table is a query spec, not a result" begin
        # No adapter, no connection: the spec is a document like any other, and
        # holds no rows.
        t = DatabaseTable(nothing, "orders")
        @test t.table == "orders"
        @test t.columns === nothing
        @test t.where_clause === nothing
        @test t.limit === nothing

        limited = DatabaseTable(nothing, "orders", ["id", "total"], "total > 10", 25)
        @test limited.columns == ["id", "total"]
        @test limited.where_clause == "total > 10"
        @test limited.limit == 25
    end

    @testset "the adapter seam refuses helpfully when nothing filled it in" begin
        # A kind no package registers. The error names the kind and says what to
        # do, rather than being a bare MethodError — the point of the seam is
        # that a caller need not name the concrete adapter type.
        err = try
            make_database_adapter(:no_such_driver)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("no_such_driver", err.msg)
        @test occursin("loaded", err.msg)
    end

    @testset "the abstract adapter implements nothing" begin
        # Every operation is a seam method that a concrete adapter must fill in.
        # A subtype that implements none must fail on use, not silently no-op.
        a = UnimplementedAdapter()
        @test_throws ErrorException db_connect!(a)
        @test_throws ErrorException db_close!(a)
        @test_throws ErrorException db_alive(a)
        @test_throws ErrorException db_rowid_column(a)
    end

end # @testset
end # test_database_documents
