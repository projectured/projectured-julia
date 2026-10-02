using Test
using ProjecturedPlatform.SerializationModule
using ProjecturedJSON.JsonModule
using ProjecturedXML.XmlModule
using ProjecturedAll.MarkdownModule
using ProjecturedAll.RstModule
using ProjecturedAll.JuliaModule
using ProjecturedKernel.DocumentModule: @document
using ProjecturedKernel.CellModule: ImmutableCell

# ── Helpers ─────────────────────────────────────────────────────────────────

"The value of the entry `key` holds, in a JSON object."
function _json_value(obj::JsonObject, key::AbstractString)
    for entry in getfield(obj, :entries)[]
        entry.key == key && return getfield(entry, :value)[]
    end
    error("no entry with key ", repr(key))
end

"The `i`-th element of a JSON array."
_json_element(array::JsonArray, i::Integer) = getfield(array, :elements)[][i]

"The `i`-th child of an XML element."
_xml_child(element::XmlElement, i::Integer) = getfield(element, :children)[][i]

"Parse the JSON file `name` in `dir` back, with no splice: what is on disk."
_json_on_disk(dir, name) = parse_json(read(joinpath(dir, name), String))

"The marker text a JSON string on disk carries, or `nothing`."
_marker_of(leaf::JsonString) = parse_marker_text(leaf.value)
_marker_of(::Any) = nothing

"The last element of a root document: where each page above holds its reference."
_last_child(root::MarkdownRoot) = getfield(root, :elements)[][end]
_last_child(root::RstRoot)      = getfield(root, :elements)[][end]
_last_child(root::JuliaBlock)   = getfield(root, :statements)[][end]

"A fresh directory, and a project of `files` in it."
_project(files...) = (d = mktempdir(); (d, FileProject(d, collect(files))))

"A document a `.pred` file may hold: a vector field, a count, a slot for anything."
@document struct TestRun
    name::String
    options::Any = nothing
    count::Int   = 0
    attachment::Any = nothing
end

"A document with a symbol field, for the `:name` literal of the notation."
@document struct TestState
    kind::Symbol = :new
end

"A document with a collection of cells, written as the list of what they hold."
@document struct TestBag
    items::CellVector = CellVector()
end

"A document with no field default, so the macro gives it no keyword constructor."
@document struct TestBare
    value::String
end

"A value that is data but not a document; the test lets a file build it."
struct TestWire
    port::Int
end
TestWire(; port) = TestWire(port)
SerializationModule.is_pred_constructible(::Type{TestWire}) = true

"A value that is not a document, and that no method lets a file build."
struct TestNotWire
    port::Int
end

# Two loaded document types with one name, in two modules.
module PredTwinFirst
import ProjecturedKernel.DocumentModule: Document
struct TestTwin <: Document end
end
module PredTwinSecond
import ProjecturedKernel.DocumentModule: Document
struct TestTwin <: Document end
end

"A document written by one of its concrete layouts."
@document struct TestLayout
    name::String
    count::Int = 0
end

"A document whose name is bound to its native struct, `ITestMark`."
@document ImmutableCell [I, C] struct TestMark
    at::Int
    selection::Nothing
end

"A document with a half it did not read: `width` and the panel it built."
@document struct TestWindow
    title::String
    width::Any = nothing
    panel::Any = nothing
end

# What its file writes, and how the rest of it comes back. The pair is what a
# document needs when it holds more than what a file says.
SerializationModule.pred_arguments(w::TestWindow) = ((), Pair{Symbol,Any}[:title => w.title])
SerializationModule.make_pred_document(::Type{<:TestWindow}, positional, keywords) =
    (title = String(last(first(keywords))); TestWindow(title, length(title)))

# ── The tests ────────────────────────────────────────────────────────────────

"""
    test_file_project()

A file reference is a fact about storage, not a node in the document. These
tests state what saving and loading must do once that holds. They are written
before the code, and the names they use are the API the plan adopts:

- `FileProject(base_dir, files)` — the save and load context: an ordered set
  of file documents and the directory they live in.
- `save_project!(project) -> Bool` — cut, print, write. Returns `false` and
  logs an error when a node has no file to be written into; writes nothing then.
- `load_project(base_dir, filenames) -> FileProject` — parse every file, then
  splice each reference leaf into the node it names.
- `save_file!(file, base_dir) -> Bool` — one file, no context, so no reference
  can be written: the content must be a pure tree of the file's domain, or the
  save logs why and returns `false`. `load_file(base_dir, filename)` is its
  inverse; a marker in it stays a leaf.

A reference to a whole file is `<<file("b.xml")>>`. A reference to a node
inside a file is `<<node(file("b.xml"), "children[1]")>>`, where the path is
the reference DSL's text form.

- `PredFile(filename, document)` — a `.pred` file: any loaded document type,
  written as its own constructor and read by the marker interpreter.

The documents are built by hand, the way a user builds them in the editor:
no marker, no stub, foreign nodes held directly.
"""
function test_file_project()
@testset "FileProject: a file reference is not a node" begin

    @testset "a shared subtree inside one file is written once" begin
        # a.json = [ {"back": <the same array>} ]
        array  = JsonArray()
        object = JsonObject("back" => array)
        push!(array, object)
        d, project = _project(JsonFile("a.json", array))
        @test save_project!(project) === true

        disk = _json_on_disk(d, "a.json")
        @test disk isa JsonArray
        back = _json_value(_json_element(disk, 1), "back")
        @test _marker_of(back) == "file(\"a.json\")"

        loaded = load_project(d, ["a.json"])
        root = get_file_content(loaded.files[1])
        @test root isa JsonArray
        @test _json_value(_json_element(root, 1), "back") === root
    end

    @testset "an XML element deep in a JSON file, owned by an XML file" begin
        # a.json = {"outer": {"inner": [ <note> ]}}     b.xml = <root><note/></root>
        note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
        xml_root = XmlElement("root", XmlAttribute[], [note])
        json_root = JsonObject("outer" => JsonObject("inner" => JsonArray([note])))
        d, project = _project(JsonFile("a.json", json_root), XmlFile("b.xml", xml_root))
        @test save_project!(project) === true

        disk = _json_on_disk(d, "a.json")
        slot = _json_element(_json_value(_json_value(disk, "outer"), "inner"), 1)
        @test _marker_of(slot) == "node(file(\"b.xml\"), \"children[1]\")"
        @test occursin("<note>", read(joinpath(d, "b.xml"), String))

        loaded = load_project(d, ["a.json", "b.xml"])
        json = get_file_content(loaded.files[1])
        xml  = get_file_content(loaded.files[2])
        spliced = _json_element(_json_value(_json_value(json, "outer"), "inner"), 1)
        @test spliced isa XmlElement
        @test spliced === _xml_child(xml, 1)
    end

    @testset "an XML element that is the whole XML file" begin
        note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
        d, project = _project(JsonFile("a.json", JsonObject("n" => note)),
                              XmlFile("b.xml", note))
        @test save_project!(project) === true
        @test _marker_of(_json_value(_json_on_disk(d, "a.json"), "n")) == "file(\"b.xml\")"

        loaded = load_project(d, ["a.json", "b.xml"])
        @test _json_value(get_file_content(loaded.files[1]), "n") ===
              get_file_content(loaded.files[2])
    end

    @testset "two files hold each other's inner documents" begin
        # a.json = {"x": <element>, "arr": [ <element> ]}   b.xml = <element> [array] </element>
        # The element holds the array and the array holds the element. Each is
        # held by the file of its own domain, which is what lets both be written.
        array   = JsonArray()
        element = XmlElement("element", XmlAttribute[], [array])
        push!(array, element)
        d, project = _project(JsonFile("a.json", JsonObject("x" => element, "arr" => array)),
                              XmlFile("b.xml", element))
        @test save_project!(project) === true
        disk = _json_on_disk(d, "a.json")
        @test _marker_of(_json_value(disk, "x")) == "file(\"b.xml\")"
        @test _marker_of(_json_element(_json_value(disk, "arr"), 1)) == "file(\"b.xml\")"
        # b.xml writes the element and, inside it, a reference to the array, which
        # the JSON file owns at entries[2].value.
        @test occursin("node(file(\"a.json\"), \"entries[2].value\")", read(joinpath(d, "b.xml"), String))

        loaded = load_project(d, ["a.json", "b.xml"])
        json = get_file_content(loaded.files[1])
        xml  = get_file_content(loaded.files[2])
        @test _json_value(json, "x") === xml
        @test _xml_child(xml, 1) === _json_value(json, "arr")
        @test _json_element(_json_value(json, "arr"), 1) === xml
    end

    @testset "an XML element in no XML file is an orphan: the save aborts" begin
        note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
        d, project = _project(JsonFile("a.json", JsonObject("n" => note)))
        result = @test_logs (:error, r"no file of its domain") save_project!(project)
        @test result === false
        @test isempty(readdir(d))
    end

    @testset "a JSON object reachable only through an XML element is an orphan" begin
        # a.json = {"n": <note> {"k": "v"} </note>}   b.xml = <note> {"k": "v"} </note>
        # The object is JSON, but no JSON file reaches it through JSON nodes.
        inner = JsonObject("k" => JsonString("v"))
        note  = XmlElement("note", XmlAttribute[], [inner])
        d, project = _project(JsonFile("a.json", JsonObject("n" => note)),
                              XmlFile("b.xml", note))
        result = @test_logs (:error, r"no file of its domain") save_project!(project)
        @test result === false
        @test isempty(readdir(d))
    end

    @testset "a file document held as a value is a reference to that file" begin
        child = JsonFile("child.json", JsonString("leaf"))
        d, project = _project(JsonFile("root.json", JsonObject("c" => child)), child)
        @test save_project!(project) === true
        @test _marker_of(_json_value(_json_on_disk(d, "root.json"), "c")) == "file(\"child.json\")"
    end

    @testset "a reference to a file outside the loaded set stays a string" begin
        note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
        d, project = _project(JsonFile("a.json", JsonObject("n" => note)),
                              XmlFile("b.xml", note))
        @test save_project!(project) === true

        partial = load_project(d, ["a.json"])
        slot = _json_value(get_file_content(partial.files[1]), "n")
        @test slot isa JsonString
        @test _marker_of(slot) == "file(\"b.xml\")"

        # Saving the partial set again changes no byte.
        before = mtime(joinpath(d, "a.json"))
        sleep(0.01)
        @test save_project!(partial) === true
        @test mtime(joinpath(d, "a.json")) == before
    end

    @testset "two references to one node splice the same object" begin
        note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
        d, project = _project(JsonFile("a.json", JsonObject("p" => note, "q" => note)),
                              XmlFile("b.xml", note))
        @test save_project!(project) === true
        loaded = load_project(d, ["a.json", "b.xml"])
        json = get_file_content(loaded.files[1])
        @test _json_value(json, "p") === _json_value(json, "q")
        @test _json_value(json, "p") === get_file_content(loaded.files[2])
    end

    @testset "save, load, save: the second save writes nothing" begin
        # An attribute-only element: the XML printer indents a text child and
        # the parser keeps the indentation as text, so a text child is not
        # stable across print, parse, print. That is the XML domain's to fix.
        note = XmlElement("note", [XmlAttribute("lang", "en")], XmlDocument[])
        d, project = _project(JsonFile("a.json", JsonObject("n" => note, "m" => JsonNumber(1))),
                              XmlFile("b.xml", note))
        @test save_project!(project) === true
        stamps = Dict(f => mtime(joinpath(d, f)) for f in ("a.json", "b.xml"))
        sleep(0.01)
        loaded = load_project(d, ["a.json", "b.xml"])
        @test save_project!(loaded) === true
        for (f, stamp) in stamps
            @test mtime(joinpath(d, f)) == stamp
        end
    end

    @testset "a string that is not a marker is left alone" begin
        d, project = _project(JsonFile("a.json", JsonObject("s" => JsonString("<<not a marker"))))
        @test save_project!(project) === true
        loaded = load_project(d, ["a.json"])
        slot = _json_value(get_file_content(loaded.files[1]), "s")
        @test slot isa JsonString
        @test slot.value == "<<not a marker"
    end

    @testset "a marker with an unknown verb names the verb" begin
        d = mktempdir()
        write(joinpath(d, "a.json"), "{\"n\": \"<<nonsense(1)>>\"}")
        @test_throws r"nonsense" load_project(d, ["a.json"])
    end

    @testset "one file at a time" begin

        @testset "a pure file saves and loads back" begin
            d = mktempdir()
            file = JsonFile("a.json", JsonObject("n" => JsonNumber(1), "s" => JsonString("x")))
            @test save_file!(file, d) === true
            back = load_file(d, "a.json")
            @test back isa JsonFile
            @test _json_value(get_file_content(back), "s").value == "x"
        end

        @testset "a foreign node is rejected: it would need a reference" begin
            note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
            d = mktempdir()
            result = @test_logs (:error, r"needs a reference") save_file!(
                JsonFile("a.json", JsonObject("n" => note)), d)
            @test result === false
            @test isempty(readdir(d))
        end

        @testset "a shared subtree is rejected: a single file cannot refer to itself" begin
            shared = JsonObject("k" => JsonString("v"))
            d = mktempdir()
            result = @test_logs (:error, r"twice") save_file!(
                JsonFile("a.json", JsonObject("p" => shared, "q" => shared)), d)
            @test result === false
            @test isempty(readdir(d))
        end

        @testset "a cycle is rejected the same way" begin
            array = JsonArray()
            push!(array, JsonObject("back" => array))
            d = mktempdir()
            result = @test_logs (:error, r"twice") save_file!(JsonFile("a.json", array), d)
            @test result === false
            @test isempty(readdir(d))
        end

        @testset "a marker string is a plain string, and saves" begin
            d = mktempdir()
            file = JsonFile("a.json", JsonObject("n" => JsonString("<<file(\"b.xml\")>>")))
            @test save_file!(file, d) === true
            @test _marker_of(_json_value(_json_on_disk(d, "a.json"), "n")) == "file(\"b.xml\")"
            @test _json_value(get_file_content(load_file(d, "a.json")), "n") isa JsonString
        end

    end

    @testset "every other format spells its own leaf" begin
        # A page in each format holds a JSON object that a JSON file owns. Each
        # writes the reference in its own notation and reads it back.
        for (label, make_page, file_type, name, spelling) in (
                ("markdown", obj -> MarkdownRoot([MarkdownParagraph([MarkdownText("Hi")]), obj]),
                 MarkdownFile, "page.md",  "```pred-ref"),
                ("rst",      obj -> RstRoot([RstParagraph([RstText("Hi")]), obj]),
                 RstFile,      "page.rst", ".. pred-ref::"),
                ("julia",    obj -> JuliaBlock([JuliaIdentifier("x"), obj]),
                 JuliaFile,    "page.jl",  "pred_ref("))
            @testset "$label" begin
                obj = JsonObject("k" => JsonString("v"))
                d, project = _project(file_type(name, make_page(obj)), JsonFile("a.json", obj))
                @test save_project!(project) === true
                text = read(joinpath(d, name), String)
                @test occursin(spelling, text)
                @test occursin("file(", text) && occursin("a.json", text)
                loaded = load_project(d, [name, "a.json"])
                page = get_file_content(loaded.files[1])
                @test _last_child(page) === get_file_content(loaded.files[2])
            end
        end
    end

    @testset "a file whose whole content is a reference" begin
        # a.json holds the XML element as its root, so the save cuts at the root
        # and the file is one string; the load puts the element back as the root.
        note = XmlElement("note", [XmlAttribute("lang", "en")], XmlDocument[])
        d, project = _project(JsonFile("a.json", note), XmlFile("b.xml", note))
        @test save_project!(project) === true
        @test _marker_of(_json_on_disk(d, "a.json")) == "file(\"b.xml\")"
        loaded = load_project(d, ["a.json", "b.xml"])
        @test get_file_content(loaded.files[1]) === get_file_content(loaded.files[2])
    end

    @testset "a load may follow what a file names" begin
        # One page is opened without opening every page beside it: name the
        # page, and what it embeds comes with it.
        note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
        d, project = _project(JsonFile("a.json", JsonObject("deep" => JsonObject("x" => note))),
                              XmlFile("b.xml", note))
        @test save_project!(project) === true
        alone = load_project(d, ["a.json"])
        @test length(alone.files) == 1
        # Nothing to splice it to, so the marker is still a string.
        @test _marker_of(_json_value(_json_value(get_file_content(alone.files[1]), "deep"), "x")) ==
              "file(\"b.xml\")"
        followed = load_project(d, ["a.json"]; follow = true)
        @test length(followed.files) == 2
        @test _json_value(_json_value(get_file_content(followed.files[1]), "deep"), "x") ===
              get_file_content(followed.files[2])
        # A file named twice is opened once, and a file already named is not
        # opened again for being reached.
        @test length(load_project(d, ["a.json", "b.xml"]; follow = true).files) == 2
    end

    @testset "a tolerant load opens what it can" begin
        # A page embedding a document of a package this session never loaded
        # still opens, with its prose and every other embed.
        d = mktempdir()
        try
            write(joinpath(d, "good.pred"), "TestRun(name = \"ok\")\n")
            write(joinpath(d, "foreign.pred"), "NotOffered(name = \"x\")\n")
            write(joinpath(d, "page.md"),
                  "# Page\n\nProse.\n\n```pred-ref\n<<file(\"good.pred\")>>\n```\n\n" *
                  "```pred-ref\n<<file(\"foreign.pred\")>>\n```\n")
            # Without it the whole page is lost to the one file that will not open.
            @test_throws Exception load_project(d, ["page.md"]; follow = true)
            project = load_project(d, ["page.md"]; follow = true, tolerant = true)
            elements = collect(getfield(get_file_content(project.files[1]), :elements)[])
            @test any(e -> e isa TestRun, elements)
            # The marker it could not open is the text it was.
            @test any(e -> e isa MarkdownCodeBlock &&
                           find_reference_marker(e) == "file(\"foreign.pred\")", elements)
            @test any(e -> e isa MarkdownParagraph, elements)
        finally
            rm(d; recursive = true, force = true)
        end
    end

    @testset "a .pred file: the document as its constructor" begin

        @testset "a symbol writes as :name and reads back" begin
            text = print_pred_text(TestState(kind = :holds))
            @test text == "TestState(\n    kind = :holds,\n)"
            loaded = parse_pred_text(text)
            @test loaded isa TestState && loaded.kind === :holds
            # A symbol whose name is not an identifier would print as a call, so
            # the writer refuses it, and a call in the reader names a type.
            @test_throws FileCutException print_pred_text(TestState(kind = Symbol("a b")))
            @test_throws Exception parse_pred_text("TestState(kind = Symbol(\"a b\"))")
        end

        @testset "a type with no keyword constructor is built from its fields" begin
            loaded = parse_pred_text("TestBare(value = \"hi\")")
            @test loaded isa TestBare && loaded.value == "hi"
            @test parse_pred_text(print_pred_text(loaded)).value == "hi"
            @test_throws "gives no value" parse_pred_text("TestBare(other = 1)")
        end

        @testset "a type that is not a document is built only when its package allows it" begin
            @test parse_pred_text("TestWire(port = 5000)") == TestWire(5000)
            @test get_pred_type("TestNotWire") === nothing
        end

        @testset "a value that a file may build writes as its call on one line" begin
            text = print_pred_text(TestWire(5000))
            @test text == "TestWire(port = 5000)"
            @test parse_pred_text(text) == TestWire(5000)
            @test_throws FileCutException print_pred_text(TestNotWire(5000))
        end

        @testset "a name that two loaded document types have is an error that names both" begin
            @test_throws r"PredTwinFirst\.TestTwin and .*PredTwinSecond\.TestTwin|PredTwinSecond\.TestTwin and .*PredTwinFirst\.TestTwin" get_pred_type("TestTwin")
        end

        @testset "a file names a document by its schema, whatever its layout" begin
            # A concrete layout has no keyword constructor, so the name builds
            # the type that the schema's module binds to it.
            @test get_pred_type("TestLayout") === TestLayout
            loaded = parse_pred_text("TestLayout(name = \"a\")")
            @test loaded isa TestLayout && loaded.name == "a"
            # The name a file writes is the schema's, also when the schema binds
            # it to a native struct of another name.
            @test get_pred_type("TestMark") === TestMark
            @test parse_pred_text("TestMark(3)").at == 3
        end

        @testset "a collection of cells writes as a list" begin
            bag = TestBag(items = CellVector(Cell[Cell(TestRun(name = "a")), Cell(TestRun(name = "b"))]))
            text = print_pred_text(bag)
            @test occursin("items = [\n", text)
            loaded = parse_pred_text(text)
            @test loaded isa TestBag && length(loaded.items) == 2
            @test loaded.items[2].name == "b"
            @test print_pred_text(loaded) == text
            # A list read from a file is a plain vector in a cell, and a reference
            # in it splices like an element of a collection of cells.
            d = mktempdir()
            try
                write(joinpath(d, "a.pred"), "TestRun(name = \"a\")\n")
                write(joinpath(d, "bag.pred"), "TestBag(items = [file(\"a.pred\")])\n")
                project = load_project(d, ["bag.pred"]; follow = true)
                bag_back = get_file_content(project.files[1])
                @test bag_back.items[1] isa TestRun && bag_back.items[1].name == "a"
            finally
                rm(d; recursive = true, force = true)
            end
        end

        @testset "a document with a vector field round-trips, byte-stable" begin
            d = mktempdir()
            run = TestRun(name = "aloha", options = ["a", "b"], count = 2)
            @test save_file!(PredFile("run.pred", run), d) === true
            text = read(joinpath(d, "run.pred"), String)
            @test startswith(text, "TestRun(")
            @test occursin("options = [\"a\", \"b\"]", text)
            back = get_file_content(load_file(d, "run.pred"))
            @test back isa TestRun
            @test back.name == "aloha" && back.options == ["a", "b"] && back.count == 2
            stamp = mtime(joinpath(d, "run.pred"))
            sleep(0.01)
            @test save_file!(PredFile("run.pred", back), d) === true
            @test mtime(joinpath(d, "run.pred")) == stamp
        end

        @testset "a .pred referenced from a JSON file splices its document" begin
            run = TestRun(name = "aloha")
            d, project = _project(JsonFile("a.json", JsonObject("run" => run)),
                                  PredFile("run.pred", run))
            @test save_project!(project) === true
            @test _marker_of(_json_value(_json_on_disk(d, "a.json"), "run")) == "file(\"run.pred\")"
            loaded = load_project(d, ["a.json", "run.pred"])
            @test _json_value(get_file_content(loaded.files[1]), "run") ===
                  get_file_content(loaded.files[2])
        end

        @testset "a .pred holding a foreign node writes the reference as a call" begin
            note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
            run  = TestRun(name = "aloha", attachment = note)
            d, project = _project(PredFile("run.pred", run), XmlFile("b.xml", note))
            @test save_project!(project) === true
            @test occursin("attachment = file(\"b.xml\")", read(joinpath(d, "run.pred"), String))
            loaded = load_project(d, ["run.pred", "b.xml"])
            @test get_file_content(loaded.files[1]).attachment === get_file_content(loaded.files[2])
        end

        @testset "a .pred file cannot run code" begin
            d = mktempdir()
            write(joinpath(d, "run.pred"), "TestRun(name = run(`touch pwned`))")
            @test_throws r"marker" load_file(d, "run.pred")
            @test !isfile(joinpath(d, "pwned"))
            write(joinpath(d, "sum.pred"), "TestRun(name = 1 + 1)")
            @test_throws r"marker" load_file(d, "sum.pred")
        end

        @testset "a name that no loaded document type has is refused by name" begin
            d = mktempdir()
            write(joinpath(d, "x.pred"), "Secret(key = 1)")
            @test_throws r"Secret" load_file(d, "x.pred")
        end

        @testset "a mapping of names to values is a named tuple" begin
            d = mktempdir()
            try
                run = TestRun(name = "queue",
                              options = [(name = "idle", level = 1), (name = "busy", level = 2)],
                              attachment = (arrival_rate = 12.0, capacity = 5))
                @test save_file!(PredFile("run.pred", run), d) === true
                text = read(joinpath(d, "run.pred"), String)
                @test occursin("attachment = (arrival_rate = 12.0, capacity = 5)", text)
                @test occursin("[(name = \"idle\", level = 1), (name = \"busy\", level = 2)]", text)
                back = get_file_content(load_file(d, "run.pred"))
                @test back.attachment == (arrival_rate = 12.0, capacity = 5)
                @test back.options[2] == (name = "busy", level = 2)
                # A key that is a path and not a name makes the mapping a list
                # of groups, which is the same tuple without the names.
                paths = TestRun(name = "s", options = [("mm1k.sink", (lifeTime = "histogram",))])
                @test save_file!(PredFile("paths.pred", paths), d) === true
                @test occursin("[(\"mm1k.sink\", (lifeTime = \"histogram\",))]",
                               read(joinpath(d, "paths.pred"), String))
                @test get_file_content(load_file(d, "paths.pred")).options[1] ==
                      ("mm1k.sink", (lifeTime = "histogram",))
                # One field keeps the comma that makes it a mapping and not a
                # parenthesis, and the bytes do not move on a second save.
                @test save_file!(PredFile("one.pred", TestRun(name = "x", count = 1,
                                                             attachment = (events = 20000,))), d)
                @test occursin("attachment = (events = 20000,)", read(joinpath(d, "one.pred"), String))
                stamp = mtime(joinpath(d, "one.pred"))
                sleep(0.01)
                @test save_file!(PredFile("one.pred", get_file_content(load_file(d, "one.pred"))), d)
                @test mtime(joinpath(d, "one.pred")) == stamp
            finally
                rm(d; recursive = true, force = true)
            end
        end

        @testset "a document may write a reduced form of itself" begin
            d = mktempdir()
            try
                # The panel is a document of no file's domain. Nothing writes
                # it, so the save does not walk it and does not call it an
                # orphan — a `GestureLog` holds the live entries it recorded
                # this way.
                window = TestWindow("Aloha", 5, JsonObject("live" => JsonString("x")))
                @test save_file!(PredFile("w.pred", window), d) === true
                # Only what the document called its file half is on disk, one
                # field to a line.
                @test read(joinpath(d, "w.pred"), String) ==
                      "TestWindow(\n    title = \"Aloha\",\n)\n"
                back = get_file_content(load_file(d, "w.pred"))
                @test back.title == "Aloha"
                # And the rest of it was built on the way back in.
                @test back.width == 5
            finally
                rm(d; recursive = true, force = true)
            end
        end

        @testset "a value the notation cannot write is refused at save" begin
            d = mktempdir()
            run = TestRun(name = "aloha", attachment = Dict("k" => 1))
            result = @test_logs (:error, r"cannot write") save_file!(PredFile("run.pred", run), d)
            @test result === false
            @test isempty(readdir(d))
        end
    end

end # testset
end # test_file_project
