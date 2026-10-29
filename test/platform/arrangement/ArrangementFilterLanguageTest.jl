# The language of a filter: the text of the field under the header of a column,
# read for values of a known type and of any type, and the condition of the
# operator `:matches`, which holds such a text.

using ProjecturedPlatform.ArrangementModule: parse_filter_text, parse_name_pattern, make_value_list_text,
                                             is_value_listed

# A run whose delay can be unknown.
@document struct _FilterLanguageRun
    status::Any
    delay::Any
end

function test_arrangement_filter_language()
@testset "the language of a filter" begin
    # The values of `values` that the text of a filter keeps.
    kept(text, values, type = eltype(values)) = (condition = parse_filter_text(text, type);
                                                [value for value in values if condition(value)])
    numbers = collect(1:20)
    words = ["item 1", "Item 2", "item 12", "other", "a, b"]

    @testset "the forms of the language" begin
        @test parse_filter_text("", Int) === nothing
        @test parse_filter_text("   ", Int) === nothing
        @test kept("> 17", numbers) == [18, 19, 20]
        @test kept(">= 19", numbers) == [19, 20]
        @test kept("< 3", numbers) == [1, 2]
        @test kept("<= 2", numbers) == [1, 2]
        @test kept("5..7", numbers) == [5, 6, 7]
        @test kept("= 4, 9", numbers) == [4, 9]
        @test kept("!= 1", numbers[1:3]) == [2, 3]
        # A text with no operator: the printed value contains it, in any case.
        @test kept("1", numbers[1:12]) == [1, 10, 11, 12]
        @test kept("ITEM", words) == ["item 1", "Item 2", "item 12"]
        @test kept("/^item [0-9]\$/", words) == ["item 1"]
        @test kept("= item 1, other", words) == ["item 1", "other"]
        @test kept("= \"a, b\"", words) == ["a, b"]
        @test kept("= true", [true, false, true]) == [true, true]
    end

    @testset "missing passes only missing" begin
        values = Union{Int,Missing}[1, missing, 3]
        @test isequal(kept("missing", values), [missing])
        @test kept("!missing", values) == [1, 3]
        @test kept("> 0", values) == [1, 3]
        @test kept("!= 1", values) == [3]
    end

    @testset "a text that does not parse gives its reason" begin
        @test parse_filter_text("> abc", Int) isa String
        @test parse_filter_text("> 3", String) isa String
        @test parse_filter_text("1..x", Int) isa String
        @test parse_filter_text("/[/", String) isa String
        @test parse_filter_text("=", String) isa String
        @test parse_filter_text("= maybe", Bool) isa String
    end

    @testset "values of any type: a comparison holds only for a number" begin
        values = Any[3, "abc", :failed, 12.5, true, nothing, missing]
        @test kept("> 2", values, Any) == [3, 12.5]
        @test kept("2..4", values, Any) == [3]
        @test kept("= failed, abc", values, Any) == ["abc", :failed]
        @test kept("= 3", values, Any) == [3]
        @test kept("AB", values, Any) == ["abc"]
        @test parse_filter_text("> abc") isa String
    end

    @testset "a list of values and the pattern of names" begin
        @test make_value_list_text(["done", "failed", "a, b"], [false, true, true]) == "= failed, \"a, b\""
        @test make_value_list_text(["done", "failed"], [true, true]) == ""
        @test make_value_list_text(["done", "failed"], [false, false]) === nothing
        @test !is_value_listed("= failed, error", "done")
        @test is_value_listed("= failed, error", "error")
        @test is_value_listed("> 3", "done")
        keep = parse_name_pattern("DELAY")
        @test keep("queue_delay") && !keep("status")
        @test parse_name_pattern("/^q/")("queue") && parse_name_pattern("")("any")
        @test parse_name_pattern("/[/") isa String
    end

    @testset "a condition of the operator :matches" begin
        rows = [_FilterLanguageRun(:failed, 0.4), _FilterLanguageRun(:done, 0.1), _FilterLanguageRun(:error, nothing)]
        status = extend_reference(EmptyReference(), FieldReferenceStep("status"))
        delay = extend_reference(EmptyReference(), FieldReferenceStep("delay"))
        shown(conditions...) = compute_filter_rows(ArrangementFilter(Any[conditions...]), rows)
        @test shown(ArrangementCondition(status, :matches, "= failed, error")) == [1, 3]
        @test shown(ArrangementCondition(delay, :matches, "> 0.2")) == [1]
        # A key that finds no value is `missing` to the text.
        @test shown(ArrangementCondition(delay, :matches, "missing")) == [3]
        # An empty text and a text that does not parse keep every item.
        @test shown(ArrangementCondition(status, :matches, "")) == [1, 2, 3]
        @test shown(ArrangementCondition(delay, :matches, "> x")) == [1, 2, 3]
        @test shown(ArrangementCondition(nothing, :matches, "")) == [1, 2, 3]
        @test is_condition_holding(ArrangementCondition(status, :matches, "!= done"), rows[1])
        @test describe_arrangement_part(ArrangementCondition(status, :matches, "= failed, error")) ==
              "status: = failed, error"
        # A `String` value in a filter pair is the filter text.
        entry = make_arrangement_entry(EmptyReference(); filter = ["status" => "= failed"])
        condition = only(only(entry.projections).conditions)
        @test condition.operator === :matches && condition.value == "= failed"
        @test_throws ArgumentError make_arrangement_entry(EmptyReference(); filter = ["status" => 3])
    end
end
end
