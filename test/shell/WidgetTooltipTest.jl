# What a document says about itself in one glance.
#
# A widget stores its answer in a field that whoever placed it set; every other
# document computes one. The two kinds are tested together, because the point of
# the generic is that a caller asks one question and does not care which kind it
# is asking.

function test_widget_tooltip()
@testset "a document says what it is" begin

@testset "a widget answers the field it was given" begin
    @test compute_tooltip(WidgetButton("Run"; size = Point2D(80, 24))) === nothing
    # A string is wrapped, because a one-line tooltip is what a caller writes.
    answer = compute_tooltip(WidgetButton("Run";
                                          size = Point2D(80, 24), tooltip = "Run the selected configurations"))
    @test answer isa PrimitiveString
    @test answer.value == "Run the selected configurations"
    # A document passes through as it is.
    given = WidgetLabel("a tip")
    @test compute_tooltip(WidgetLabel("x"; tooltip = given)) === given
end

@testset "every widget type carries the field" begin
    # The sweep is the claim, so the test is the sweep: a type that was missed
    # answers a MethodError rather than nothing.
    @test compute_tooltip(WidgetTable(Any["a"], Any[Any["1"]])) === nothing
    @test compute_tooltip(WidgetSwitch()) === nothing
    @test compute_tooltip(WidgetSplitPane(:horizontal, Any[])) === nothing
    @test compute_tooltip(WidgetTree(Any[])) === nothing
    @test compute_tooltip(WidgetMenuItem("Copy")) === nothing
end

@testset "a document with nothing to say says nothing" begin
    @test compute_tooltip(PrimitiveString("plain")) === nothing
    @test compute_context_menu(PrimitiveString("plain")) === nothing
end

end # @testset
end # function
