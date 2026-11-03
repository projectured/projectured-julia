"""
The interface vocabulary a window declares to a model: the names marked
`For the assistant.` are declared without refusal beside the pane names, every
interface name carries the docstring a search reads, and a search finds the widget
a sentence means.
"""

using Test
using ProjecturedKernel.ToolModule
using ProjecturedKernel.ToolModule: _binding_doc
using ProjecturedKernel.ToolModule: collect_marked_api, get_api_entry_names
import ProjecturedPlatform.WidgetModule
import ProjecturedPlatform.LayoutModule
import ProjecturedPlatform.StyleModule

# The widgets a person asks for by name, the policies a layout sizes a child with,
# and the two geometry values a widget takes: each is marked in its docstring.
const INTERFACE_NAMES = (
    WidgetModule => (
        :WidgetCard, :WidgetTitlePane, :WidgetTabbedPane, :WidgetSplitPane,
        :WidgetScrollPane, :WidgetAccordion, :WidgetComposite,
        :WidgetLabel, :WidgetText, :WidgetTextarea, :WidgetTable, :WidgetBadge,
        :WidgetAlert, :WidgetProgressBar, :WidgetProgressRing, :WidgetSeparator,
        :WidgetButton, :WidgetLink, :Action, :WidgetCheckbox, :WidgetSwitch, :WidgetToggleGroup,
        :WidgetRadioGroup, :WidgetSelect, :WidgetSlider, :WidgetSpinBox, :WidgetList),
    StyleModule => (:Point2D, :Inset),
    LayoutModule => (:Fixed, :Content, :Relative, :Fill),
)

# The name a hit line opens with: the word its signature starts with.
_interface_hit_names(answer) =
    [String(found.captures[1]) for found in eachmatch(r"^- `([^`(\s{]+)"m, answer)]

# The example a docstring shows: every indented line under `# Example`, up to
# the next paragraph of prose.
function _interface_example(doc)
    lines = split(doc, '\n')
    start = findfirst(==("# Example"), lines)
    start === nothing && return ""
    code = String[]
    for line in lines[start + 1:end]
        if startswith(line, "    ")
            push!(code, strip(line))
        elseif !isempty(strip(line)) && !isempty(code)
            break
        end
    end
    join(code, '\n')
end

_has_parse_error(expression) =
    expression isa Expr && (expression.head in (:error, :incomplete) ||
                            any(_has_parse_error, expression.args))

function test_interface_api()
@testset "the interface vocabulary" begin
    marked = collect_marked_api()
    set = register_default_tools!(declare_api!(ToolSet(), marked))
    given = [(entry.first, name) for entry in INTERFACE_NAMES for name in entry.second]

    @testset "the interface names are marked for the assistant" begin
        offered = Set((entry.module_, name) for entry in marked for name in get_api_entry_names(entry))
        for (mod, name) in given
            @test (mod, name) in offered
        end
    end

    @testset "every name is declared once, and each carries what a model reads" begin
        declared = [String(name) for entry in set.api for name in get_api_entry_names(entry)]
        @test length(unique(declared)) == length(declared)
        @test length(given) == 33
        for (mod, name) in given
            doc = _binding_doc(mod, name)
            @test occursin("\nUse it to ", doc)
            @test occursin("\nSee also ", doc)
            example = _interface_example(doc)
            @test !isempty(example)
            # An example is code a model copies, so it must at least parse.
            @test !_has_parse_error(Meta.parseall(example))
        end
    end

    @testset "a sentence a person says finds the widget" begin
        first_hit(query) = first(_interface_hit_names(search_api(query; api = set.api)))
        @test first_hit("a card with a title around the plot") == "WidgetCard"
        @test first_hit("a button that runs the sweep again") == "WidgetButton"
        # A row and a split pane both put widgets side by side, and either is a
        # right answer. A sentence is ranked by its words here, with no model of
        # meaning, and "row" also names the rows of a table, so the answer is among
        # the first three.
        first_hits(query) = first(_interface_hit_names(search_api(query; api = set.api)), 3)
        @test any(in(("HorizontalLayout", "WidgetSplitPane")),
                  first_hits("a row of widgets side by side"))
        @test first_hit("a switch that is on or off") == "WidgetSwitch"
    end

    @testset "a type and a constant are read where the hit points" begin
        # `Point2D` is a type of `StyleModule`, which a widget takes; `Fill` is a
        # value, neither a type nor a function. Each hit carries a URI that reads.
        @test occursin("Use it to", read_resource(set, "resource://type/StyleModule/Point2D"))
        @test occursin("Use it to", read_resource(set, "resource://value/LayoutModule/Fill"))
        hits = search_api("SizePolicy"; api = set.api, detail = "names")
        @test occursin("`Fill -> SizePolicy` — value in LayoutModule", hits)
        @test occursin("`Fixed(n) -> SizePolicy` — function in LayoutModule", hits)
    end
end
end # test_interface_api
