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

A reference to a whole file is `<<file("b.xml")>>`. A reference to a node
inside a file is `<<node(file("b.xml"), "children[1]")>>`, where the path is
the reference DSL's text form.

The documents are built by hand, the way a user builds them in the editor:
no marker, no stub, foreign nodes held directly.
"""

using Test
using ProjecturedSerialization.SerializationModule
using ProjecturedJson.JsonModule
using ProjecturedXml.XmlModule

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

"A fresh directory, and a project of `files` in it."
_project(files...) = (d = mktempdir(); (d, FileProject(d, collect(files))))

# ── The tests ────────────────────────────────────────────────────────────────

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
        # a.json = {"x": <element>}   b.xml = <element> [array] </element>
        # element = <element> holding array; array = [ element ]
        array   = JsonArray()
        element = XmlElement("element", XmlAttribute[], [array])
        push!(array, element)
        d, project = _project(JsonFile("a.json", JsonObject("x" => element)),
                              XmlFile("b.xml", element))
        @test save_project!(project) === true
        @test _marker_of(_json_value(_json_on_disk(d, "a.json"), "x")) == "file(\"b.xml\")"
        # b.xml writes the element and, inside it, a reference to the array — which
        # the JSON file owns.
        @test occursin("node(file(\\\"a.json\\\")", read(joinpath(d, "b.xml"), String)) ||
              occursin("node(file(\"a.json\")", read(joinpath(d, "b.xml"), String))

        loaded = load_project(d, ["a.json", "b.xml"])
        json = get_file_content(loaded.files[1])
        xml  = get_file_content(loaded.files[2])
        @test _json_value(json, "x") === xml
        @test _xml_child(xml, 1) isa JsonArray
        @test _json_element(_xml_child(xml, 1), 1) === xml
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
        note = XmlElement("note", XmlAttribute[], [XmlText("hi")])
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

end # testset
end # test_file_project
