# Fragment of `ProjecturedExample` — the corpus of this repository at scale, and
# the questions asked of it.
#
# A window declares what one pane needs, about a hundred names. This declares
# twenty-five modules, about 2,400 names, which is what a window reaches when it
# declares what it can draw and not only what one pane holds. The questions are
# what a person says, not what a docstring says, so a name that is found only by
# its own words is found here only by luck.

"""
    SCALE_SEARCH_MODULE_NAMES

The modules of the scale corpus: the kernel's own, the substrate that draws, the
widgets and the layouts, the panes, and four domains. A module is named and not
gathered, so that the corpus is the same on every run.
"""
const SCALE_SEARCH_MODULE_NAMES =
    (:CellModule, :CollectionModule, :DocumentModule, :DomainModule, :EventModule,
     :IoMapModule, :OperationModule, :PrimitiveModule, :ProjectionModule, :ReferenceModule,
     :SelectionModule, :SerializationModule, :StyleModule, :SyntaxModule, :TextModule,
     :GraphicsModule, :LayoutModule, :WidgetModule, :PaneModule, :ChartModule,
     :JsonModule, :XmlModule, :MarkdownModule, :FormulaModule, :ToolModule)

"""
    get_scale_search_modules() -> Vector{Module}

The modules [`SCALE_SEARCH_MODULE_NAMES`](@ref) names.
"""
get_scale_search_modules() =
    Module[getfield(Projectured, name) for name in SCALE_SEARCH_MODULE_NAMES]

"""
    SCALE_SEARCH_QUESTIONS

What a person asks of the scale corpus, each with the name or the guide it
means. A sentence says what the thing does and avoids the words of its name
where a person would, so the table shows what the search adds to the spelling.
"""
const SCALE_SEARCH_QUESTIONS = ScaleQuestion[
    # What is drawn, and how it is placed.
    (sentence = "put widgets beside each other in one row",
     expected = "HorizontalLayout", kind = :api),
    (sentence = "stack widgets one under the other",
     expected = "VerticalLayout", kind = :api),
    (sentence = "arrange children in columns and rows",
     expected = "GridLayout", kind = :api),
    (sentence = "a surface with a heading around a table",
     expected = "WidgetCard", kind = :api),
    (sentence = "a control a person clicks to run a command",
     expected = "WidgetButton", kind = :api),
    (sentence = "let a person scroll over content taller than the space",
     expected = "WidgetScrollPane", kind = :api),
    (sentence = "two views with a divider a person drags",
     expected = "WidgetSplitPane", kind = :api),
    (sentence = "rows and columns of cells with headers",
     expected = "WidgetTable", kind = :api),
    (sentence = "a pair of numbers that says where something sits",
     expected = "Point2D", kind = :api),
    (sentence = "the space kept on each side of a widget",
     expected = "Inset", kind = :api),
    (sentence = "a child that takes everything its parent offers",
     expected = "Fill", kind = :api),
    (sentence = "a child that stays as big as what it shows",
     expected = "Content", kind = :api),
    # The window.
    (sentence = "show a document in a new tab of the window",
     expected = "open_pane!", kind = :api),
    (sentence = "show what is where in the windows",
     expected = "show_layout", kind = :api),
    (sentence = "write a new value where a reference points",
     expected = "replace_referenced_value!", kind = :api),
    (sentence = "bring a pane to the front",
     expected = "focus_pane!", kind = :api),
    # The engine.
    (sentence = "a value that is computed again when what it reads changes",
     expected = "Cell", kind = :api),
    (sentence = "make a field of a document computed",
     expected = "set_cell_computation!", kind = :api),
    (sentence = "turn a document into what the screen shows",
     expected = "print_document", kind = :api),
    (sentence = "turn a key press into an edit of the document",
     expected = "read_intent", kind = :api),
    (sentence = "apply an edit to the document",
     expected = "evaluate_operation", kind = :api),
    (sentence = "follow a place in the document through a projection",
     expected = "map_reference_forward", kind = :api),
    (sentence = "read a saved document back from its text",
     expected = "parse_pred_text", kind = :api),
    # What a model may do.
    (sentence = "run Julia code in the editor process",
     expected = "execute_julia_code!", kind = :api),
    (sentence = "say which names a model may write",
     expected = "declare_api!", kind = :api),
    (sentence = "find a function by what it does",
     expected = "search_api", kind = :api),
    # The guides.
    (sentence = "how a value is computed again when its inputs change",
     expected = "kernel/cell", kind = :guide),
    (sentence = "how should I name a new function",
     expected = "rule/naming-rules", kind = :guide),
    (sentence = "which test should I run after I change a file",
     expected = "guide/testing-guide", kind = :guide),
    (sentence = "what a package may depend on",
     expected = "rule/package-rules", kind = :guide),
    (sentence = "how the editor turns a key press into an edit",
     expected = "kernel/editor", kind = :guide),
    (sentence = "how to add support for a new file format as a domain",
     expected = "guide/new-domain-guide", kind = :guide),
]

"""
    measure_projectured_search_scale!(; backend = nothing, io = stdout) -> Vector

Ask [`SCALE_SEARCH_QUESTIONS`](@ref) of the corpus
[`SCALE_SEARCH_MODULE_NAMES`](@ref) declares, and print what the search cost and
answered. `backend` is a language model with a meaning model; a local one is
`make_llm(:ollama)`, which needs `ProjecturedOllama` loaded.

It reads a clock, so it wants a machine that is not busy.
"""
measure_projectured_search_scale!(; backend = nothing, io::IO = stdout) =
    measure_search_scale!(; modules = get_scale_search_modules(),
                          questions = SCALE_SEARCH_QUESTIONS, backend = backend, io = io)
