# The type `View` and the families below it: a view of one content, a widget, a
# layout, a graphics document and a pane are views, and a content is none.

function test_view_families()
@testset "View families" begin

@test supertype(View) === Document
@test supertype(ContentView) === View
@test supertype(WidgetDocument) === View
@test supertype(LayoutDocument) === View
@test supertype(GraphicsDocument) === View
@test supertype(PaneDocument) === View

block = TextBlock(TextLine(TextString("alpha")))
label = WidgetLabel("alpha")
@test TextView(block) isa View
@test label isa View
@test VerticalLayout([label]) isa View
@test !(block isa View)
@test !(PrimitiveString("alpha") isa View)

end
end
