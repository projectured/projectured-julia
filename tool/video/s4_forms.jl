# The forms of screenplay S4, which `record_widget_tool.jl` types, in the groups
# that the take shows at work one after the other.

# The tool: a button that counts its presses, in a column.
const TOOL_FORMS = [
    "presses = Cell(0)",
    "button = WidgetButton(\"Press me\"; action = () -> presses[] += 1)",
    "tool = VerticalLayout([button]; gap = 12)",
]

# After the tool has a pane of its own: the helper, and the label that counts.
const COUNTER_FORMS = [
    "add!(widgets...) = foreach(widget -> push!(tool.children, widget), widgets)",
    "add!(WidgetLabel(() -> \"Pressed \$(presses[]) times\"))",
]

# The slider, and the label that reads it.
const SLIDER_FORMS = [
    "slider = WidgetSlider(0.3)",
    "add!(slider, WidgetLabel(() -> \"Slider at \$(round(slider.value; digits = 2))\"))",
]

# The name, the table that follows all three, and a write of the name.
const TABLE_FORMS = [
    "name = WidgetText(\"Ada\")",
    "add!(name, WidgetTable([\"what\", \"value\"], [[\"presses\", () -> presses[]], [\"slider\", () -> round(slider.value; digits = 2)], [\"name\", () -> name.content]]))",
    "name.content = \"Ada Lovelace\"",
]

const S4_FORMS = vcat(TOOL_FORMS, COUNTER_FORMS, SLIDER_FORMS, TABLE_FORMS)
