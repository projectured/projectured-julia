"""
The declared API — what a model may write, and what it may find.

A `ToolSet` that names modules gets those and nothing else, in both directions:
`execute_julia_code` resolves their names and no others, and the documentation
tools offer their names and no others. The two are one list, because a model that
finds a function it cannot call wastes a round.
"""

using Test
using ProjecturedKernel.ToolModule

# A module of the kind a caller declares: a few verbs and nothing more. Julia
# allows `module` only at the top level, so the fixture lives here rather than
# inside the testset.
module ToyApi
export toy_verb, toy_count, toy_limit, _toy_inside
"""Answer the word this verb is named after."""
toy_verb() = "toy"
"""Count what it is given."""
toy_count(xs) = length(xs)
"""
    toy_limit

How many toys a box holds. Use it to bound a count.
"""
const toy_limit = 3
"""What the module keeps to itself, although it is exported."""
_toy_inside() = "inside"
end

# A docstring shaped the way this repository writes one: an indented signature
# block, a blank line, then the sentence that says what the thing does. Julia
# strips a docstring's common indentation before storing it, so that block
# arrives flush left — which is what made every entry index its signature and
# nothing else.
module ToyShaped
export toy_arrange
"""
    toy_arrange(window) -> String

Put every pane where the person asked for it.
"""
toy_arrange(window) = "arranged"
end

# A second one, to prove that two declared modules both arrive.
module ToyExtra
export toy_extra
"""A verb from a second declared module."""
toy_extra() = 7
end

# A module that re-exports another's verb: the same binding under two modules,
# which is what a wide declaration is full of.
module ToyEcho
import ..ToyApi: toy_verb
export toy_verb, toy_echo
"""Say the word twice."""
toy_echo() = "toytoy"
end

# A document type as `@document` writes one: the schema, and the names the macro
# writes beside it, one per storage kind. The macro exports them all.
module ToyStorage
export ToyBox, ACToyBox, DCToyBox, ICToyBox, MCToyBox, RCToyBox, AToyBox, MToyBox, Action
"""
    ToyBox(lid)

A box a document holds.
"""
struct ToyBox
    lid::Bool
end
const ACToyBox = ToyBox
const DCToyBox = ToyBox
const ICToyBox = ToyBox
const MCToyBox = ToyBox
const RCToyBox = ToyBox
const AToyBox = ToyBox
# The native layout is a struct of its own, not an alias.
struct MToyBox
    lid::Bool
end
"""A command, whose name opens with the letter of a variant."""
struct Action
    label::String
end
end

# A module with a verb of its own under a name another module also gives. This
# is the collision a declaration must refuse.
module ToyRival
export toy_verb
"""A different verb under a word another module owns."""
toy_verb(x) = x
end

function test_declared_api()
@testset "Declared API" begin

    @testset "an empty declaration is the whole surface" begin
        set = ToolSet()
        @test isempty(set.api)
        # `Cell` is a kernel name, so it resolves through the default gathering.
        @test occursin("Cell", execute_julia_code(set, nothing, "string(Cell)"))
    end

    @testset "a call with no code answers that, rather than answering nothing" begin
        # Empty source evaluates to nothing and prints nothing, so the tool used to
        # answer an empty string — which a model reads as a broken tool rather than
        # as its own mistake, and then it stops writing code at all.
        set = ToolSet()
        for blank in ("", "\n", "   \n  ")
            answer = execute_julia_code(set, nothing, blank)
            @test occursin("No code was given", answer)
            @test occursin("`code`", answer)
        end
        # And a real call still runs.
        @test strip(execute_julia_code(set, nothing, "1 + 1")) == "2"
    end

    @testset "a function's documentation is reachable as a tool" begin
        # `search_api` answers a `read_function_documentation(…)` call for every
        # function it finds, and a module or a type has a resource:// URI. A
        # function has none, so without this tool the only way to a docstring is
        # to write Julia — and a model told to "call read_function_documentation"
        # looks for a tool of that name, finds none, and sends an empty call.
        set = ToolSet(; api = Module[ToyApi])
        register_default_tools!(set)
        tool = only([t for t in set.tools if t.name == "read_function_documentation"])
        answer = tool.handler(nothing, Dict("module_name" => "ToyApi",
                                            "function_name" => "toy_verb"))
        @test occursin("Answer the word this verb is named after", answer)
    end

    # A model looks for a verb by what it does, and the words for that are in the
    # description. Scored on the signature alone, `search_api` could answer a name
    # and never a sentence: `show_layout`'s docstring said "Which panes are open"
    # and a search for "panes" answered nothing at all.
    @testset "a verb is found by its description, not only by its name" begin
        set = ToolSet(; api = Module[ToyShaped])
        register_default_tools!(set)
        search = only([t for t in set.tools if t.name == "search_api"])

        # Each of these words is in the description and nowhere else — not in the
        # verb's name, not in its module's, not in its signature.
        for word in ("pane", "person", "asked")
            @test occursin("toy_arrange", search.handler(nothing, Dict("query" => word)))
        end

        # What a hit SHOWS is still the signature. The prompt promises one, and a
        # model calls a verb off it without reading the documentation.
        @test occursin("toy_arrange(window) -> String",
                       search.handler(nothing, Dict("query" => "toy_arrange")))
    end

    # Half of a turn was a lookup pair: a search for the name, then a read for
    # its documentation. These three cut the pair to one call, and they cut the
    # round a miss used to cost.
    @testset "a search answers in one round what took two" begin
        set = ToolSet(; api = Module[ToyShaped])
        register_default_tools!(set)
        search = only([t for t in set.tools if t.name == "search_api"])
        ask(query) = search.handler(nothing, Dict("query" => query))

        # One clear hit answers the WHOLE documentation, not the signature and a
        # locator to call next round.
        answer = ask("toy_arrange")
        @test occursin("the one API match", answer)
        @test occursin("toy_arrange(window) -> String", answer)
        # A sentence that lives below the signature, which the old answer cut.
        @test occursin("person", answer)
        # And it does not ask for another round.
        @test !occursin("Read one in full", answer)

        # A query that matches several still lists them, one line each.
        many = ask("toy")
        @test occursin("API matches for", many)
        @test !occursin("the one API match", many)

        # A plural is the same question as its singular. The verb is named
        # `toy_arrange` and the docstring says "panes"; both spellings find it.
        @test occursin("toy_arrange", ask("pane"))
        @test occursin("toy_arrange", ask("panes"))

        # **A stem may not claim a name.** A query scores against a NAME exactly
        # as it was written, and against the prose in any of its forms. Let a
        # stem claim a name and every verb holding the stem as a substring
        # arrives first: measured, "stop runs" answered
        # `run_simulations_in_conversation` before `stop_simulations`, because
        # `run` is inside almost every verb of that module.
        both = ToolSet(; api = Any[ToyApi, ToyShaped])
        register_default_tools!(both)
        wider = only([t for t in both.tools if t.name == "search_api"])
        ask_both(query) = wider.handler(nothing, Dict("query" => query))

        # `toy_count` is the one named for counting, whatever the prose says.
        counted = ask_both("count toy")
        @test occursin("toy_count", first(l for l in split(counted, "\n")
                                          if startswith(l, "- `")))

        # **A hit shows the name a caller writes.** A declared name arrives
        # unqualified, so a hit that led with `Module.name` invited a caller to
        # copy that shape and guess the module — measured, one did, and lost the
        # turn to an `UndefVarError`. The module is context, after the name.
        @test occursin("`toy_count` — function in ToyApi", counted)
        @test !occursin("`ToyApi.toy_count`", counted)

        # A miss says what there IS, in the round that asked.
        missed = ask("xyzzy")
        @test occursin("No API matches", missed)
        @test occursin("What you may write", missed)
        @test occursin("toy_arrange", missed)
    end

    @testset "a declared module is what resolves" begin
        set = ToolSet(; api = Module[ToyApi])
        @test execute_julia_code(set, nothing, "toy_verb()") |> strip == "\"toy\""
        @test strip(execute_julia_code(set, nothing, "toy_count([1, 2, 3])")) == "3"
    end

    # ── A declaration of names ───────────────────────────────────────────────
    #
    # A module is the shorthand for all of its exports. A `module => names` pair
    # is what a surface wants when a module has eighty-six exported names and a
    # verb wants eight of them, and it is what lets a name arrive unqualified
    # with no module re-exporting a name it does not own.
    @testset "a pair gives the names it lists, and no others" begin
        set = ToolSet(; api = [ToyApi => (:toy_verb,)])
        @test strip(execute_julia_code(set, nothing, "toy_verb()")) == "\"toy\""

        # `toy_count` is exported by the same module, and the declaration left it
        # out, so it is not a name this model may write.
        answer = execute_julia_code(set, nothing, "toy_count([1, 2])")
        @test occursin("UndefVarError", answer)
        @test occursin("toy_count", answer)
    end

    # A model told which modules it has lists one of them before it writes. The
    # listing verbs are in scope with the declaration applied, so the module is
    # found, and what they list is what the code can call.
    @testset "a declared module can be listed, and lists what it gives" begin
        set = ToolSet(; api = [ToyApi => (:toy_verb,)])
        functions = execute_julia_code(set, nothing, "list_functions(\"ToyApi\")")
        @test !occursin("not found", functions)
        @test occursin("toy_verb", functions)
        @test !occursin("toy_count", functions)
        @test !occursin("not found", execute_julia_code(set, nothing, "list_types(\"ToyApi\")"))
        @test occursin("ToyApi", execute_julia_code(set, nothing, "list_modules()"))
        # A module the declaration does not name is not found, as its names do not resolve.
        @test occursin("not found", execute_julia_code(set, nothing, "list_functions(\"ToolModule\")"))
    end

    # The module's own name stays bound, and that is deliberate. The harm a wide
    # declaration does is to DISCOVERY — a search that answers thirty generated
    # schema variants instead of the verb — and narrowing the index is what fixes
    # that. Reachability is not the measure: a declaration is a focus mechanism
    # and not a security boundary, which is what `ToolSet` already says of itself.
    @testset "a narrowed module keeps its own name" begin
        set = ToolSet(; api = [ToyApi => (:toy_verb,)])
        @test strip(execute_julia_code(set, nothing, "ToyApi.toy_count([1, 2])")) == "2"
    end

    # Two packages own the same common word often enough that a surface would
    # have to drop one of them. A rename is a declaration, not a wrapper: the
    # owning module is untouched and there is one function, not two.
    @testset "a declared name can be given another name" begin
        set = ToolSet(; api = [ToyApi => (:toy_verb => :say_toy, :toy_count)])

        # The model writes the name it was given.
        @test strip(execute_julia_code(set, nothing, "say_toy()")) == "\"toy\""
        # And the one that was not renamed is itself.
        @test strip(execute_julia_code(set, nothing, "toy_count([1, 2])")) == "2"
        # The module's own word is not what this model writes.
        @test occursin("UndefVarError", execute_julia_code(set, nothing, "toy_verb()"))

        # It is findable and readable under the new name, and its documentation
        # is still its own.
        register_default_tools!(set)
        search = only([t for t in set.tools if t.name == "search_api"])
        @test occursin("say_toy", search.handler(nothing, Dict("query" => "say_toy")))
        reader = only([t for t in set.tools if t.name == "read_function_documentation"])
        answer = reader.handler(nothing, Dict("module_name" => "ToyApi",
                                              "function_name" => "say_toy"))
        @test !occursin("not found", answer)
        @test !occursin("not one of the names", answer)

        # The refusal reads the module's own name, so a rename of a name that is
        # not there is still refused.
        message = try
            declare_api!(ToolSet(), [ToyApi => (:toy_missing => :anything,)])
            ""
        catch error
            sprint(showerror, error)
        end
        @test occursin("toy_missing", message)
    end

    # Half of what a turn spends is finding out what it may call. The signature
    # lines are what a search hit shows anyway, so a prompt that carries them
    # spends no round on the lookup.
    @testset "the declaration renders as the lines a prompt carries" begin
        text = describe_api(Any[ToyApi => (:toy_verb => :say_toy, :toy_count)])
        @test occursin("ToyApi", text)
        # The name the MODEL writes, with its signature on one line.
        @test occursin("say_toy", text)
        @test !occursin("toy_verb", text)
        @test occursin("toy_count", text)
        # One line each, and no prose: the paragraph under the signature stays
        # where it is, one `read_function_documentation` away.
        @test length(split(text, "\n")) == 3

        # A name the declaration left out is not in it either.
        @test !occursin("toy_count", describe_api(Any[ToyApi => (:toy_verb,)]))
    end

    @testset "a name its module does not have is refused" begin
        set = ToolSet()
        message = try
            declare_api!(set, [ToyApi => (:toy_verb, :toy_missing)])
            ""
        catch error
            sprint(showerror, error)
        end
        @test occursin("ToyApi", message)
        @test occursin("toy_missing", message)
        @test isempty(set.api)
    end

    @testset "a generated schema variant is not a hit" begin
        set = register_default_tools!(ToolSet(; api = Module[ToyStorage]))
        entries = ProjecturedKernel.ToolModule._api_index(set.api)
        types = [entry.qualname for entry in entries if entry.kind == "type"]
        # The schema is a hit; the six names the macro writes beside it are not.
        @test "ToyStorage.ToyBox" in types
        @test !any(name -> occursin("ToyBox", name) && name != "ToyStorage.ToyBox", types)
        # A name that merely starts with the letter of a variant stays.
        @test "ToyStorage.Action" in types
        # A variant is no resource either, and the model may still write it.
        @test !any(resource -> occursin("ToyBox", resource.uri) &&
                               !endswith(resource.uri, "/ToyBox"), list_resources(set))
        @test occursin("ToyStorage.ToyBox",
                       execute_julia_code(set, nothing, "string(DCToyBox)"))
    end

    @testset "the module catalogue names each module once, with its declared types" begin
        set = register_default_tools!(ToolSet(; api = [ToyStorage => (:ToyBox, :MToyBox),
                                                       ToyStorage => (:Action,)]))
        listed = read_resource(set, "resource://modules")
        @test count("**ToyStorage**", listed) == 1
        # The two declared types, and not the schema variant that the first
        # entry also names.
        @test occursin("Types: Action, ToyBox\n", listed * "\n")
        @test !occursin("MToyBox", listed)
    end

    @testset "a name two modules re-export is one hit, and one binding" begin
        set = register_default_tools!(ToolSet())
        declare_api!(set, [ToyApi, ToyEcho])
        entries = ProjecturedKernel.ToolModule._api_index(set.api)
        # One binding is one hit, although two modules give the word.
        @test count(entry -> endswith(entry.qualname, ".toy_verb"), entries) == 1
        @test count(entry -> endswith(entry.qualname, ".toy_echo"), entries) == 1
        @test strip(execute_julia_code(set, nothing, "toy_verb()")) == "\"toy\""
        @test strip(execute_julia_code(set, nothing, "toy_echo()")) == "\"toytoy\""
    end

    @testset "two entries that give one name are refused" begin
        set = ToolSet()
        message = try
            declare_api!(set, [ToyApi, ToyRival])
            ""
        catch error
            sprint(showerror, error)
        end
        @test occursin("toy_verb", message)
        @test occursin("ToyApi", message)
        @test occursin("ToyRival", message)
        # Nothing was declared by the refusal.
        @test isempty(set.api)
    end

    # What is discoverable is what is callable, and a pair narrows both halves.
    @testset "a name the declaration left out is not discoverable either" begin
        set = ToolSet(; api = [ToyApi => (:toy_verb,)])
        register_default_tools!(set)
        search = only([t for t in set.tools if t.name == "search_api"])
        read = only([t for t in set.tools if t.name == "read_function_documentation"])

        found = search.handler(nothing, Dict("query" => "toy"))
        @test occursin("toy_verb", found)
        @test !occursin("toy_count", found)

        @test occursin("Count what it is given",
                       read.handler(nothing, Dict("module_name" => "ToyApi",
                                                  "function_name" => "toy_verb"))) == false
        refused = read.handler(nothing, Dict("module_name" => "ToyApi",
                                             "function_name" => "toy_count"))
        @test occursin("not one of the names you may write", refused)
    end

    # "The functions of ToyApi" is false of a declaration that took one of them,
    # so the description counts the names instead of naming their module.
    @testset "the description does not claim a whole module it did not take" begin
        whole = ToolSet(; api = Module[ToyApi])
        register_default_tools!(whole)
        @test occursin("The functions of ToyApi",
                       only([t for t in whole.tools if t.name == "execute_julia_code"]).description)

        narrow = ToolSet(; api = [ToyApi => (:toy_verb,)])
        register_default_tools!(narrow)
        text = only([t for t in narrow.tools if t.name == "execute_julia_code"]).description
        @test !occursin("The functions of ToyApi", text)
        @test occursin("1 names this editor declares", text)
    end

    # A model that finds an object again in every call spends a round on each, so
    # both descriptions tell it to keep what it found in numbered variables.
    @testset "the description tells the model to keep objects in numbered variables" begin
        for set in (ToolSet(), ToolSet(; api = Module[ToyApi]))
            register_default_tools!(set)
            text = only([t for t in set.tools if t.name == "execute_julia_code"]).description
            @test occursin("still there in every later call", text)
            @test occursin("`rows_2`, and do not overwrite the first", text)
            @test occursin("as the Julia REPL shows it", text)
            @test occursin("not by a direct write", text)
        end
        whole = ToolSet()
        register_default_tools!(whole)
        @test occursin("evaluate_operation(editor, operation)",
                       only([t for t in whole.tools if t.name == "execute_julia_code"]).description)
        narrow = ToolSet(; api = Module[ToyApi])
        register_default_tools!(narrow)
        text = only([t for t in narrow.tools if t.name == "execute_julia_code"]).description
        @test !occursin("replace_referenced_value!", text)
        @test !occursin("insert_elements!", text)
        @test !occursin("evaluate_operation", text)
    end

    @testset "a name outside the declaration fails in the round that used it" begin
        set = ToolSet(; api = Module[ToyApi])
        answer = execute_julia_code(set, nothing, "Cell(1)")
        @test occursin("UndefVarError", answer)
        @test occursin("Cell", answer)
    end

    # The declaration opens as much as it narrows. The default gathering collects
    # modules by PACKAGE name, so a module in a package not called `Projectured…`
    # — every module of every other repository — is unreachable until a `ToolSet`
    # names it. This fixture cannot show that half: it lives inside
    # `ProjecturedKernelTest`, which the default gathering does reach. What it can
    # show is the narrowing, and that a declaration is what carries a module in.
    @testset "the declaration decides, in both directions" begin
        wide = ToolSet()
        narrow = ToolSet(; api = Module[ToyApi])
        @test occursin("Cell", execute_julia_code(wide, nothing, "string(Cell)"))
        @test occursin("UndefVarError", execute_julia_code(narrow, nothing, "string(Cell)"))
        @test strip(execute_julia_code(narrow, nothing, "toy_verb()")) == "\"toy\""
    end

    @testset "two declared modules both arrive" begin
        set = ToolSet(; api = Module[ToyApi, ToyExtra])
        @test strip(execute_julia_code(set, nothing, "toy_verb()")) == "\"toy\""
        @test strip(execute_julia_code(set, nothing, "string(toy_extra())")) == "\"7\""
    end

    @testset "state still survives between calls" begin
        set = ToolSet(; api = Module[ToyApi])
        execute_julia_code(set, nothing, "kept = toy_count([1, 2])")
        @test strip(execute_julia_code(set, nothing, "string(kept)")) == "\"2\""
    end

    @testset "the target is still bound as editor" begin
        set = ToolSet(; api = Module[ToyApi])
        @test strip(execute_julia_code(set, (name = "a",), "editor.name")) == "\"a\""
    end

    # Both directions of the invariant. Every name the tools offer resolves, and
    # nothing else does.
    @testset "what is discoverable is what is callable" begin
        set = ToolSet(; api = Module[ToyApi])
        found = search_api("toy"; api = set.api)
        @test occursin("toy_verb", found)
        @test occursin("toy_count", found)
        # A name of the wider surface is not offered. The answer echoes the query,
        # so the assertion is that nothing was found, not that the word is absent.
        @test occursin("No API matches", search_api("CellVector"; api = set.api))
        # And every name that IS offered resolves in the scratch module.
        for verb in ("toy_verb", "toy_count")
            @test !occursin("UndefVarError",
                            execute_julia_code(set, nothing, "string(" * verb * ")"))
        end
    end

    @testset "a declared constant is found, and read where its hit points" begin
        set = register_default_tools!(ToolSet(; api = Module[ToyApi]))
        hits = search_api("bound a count"; api = set.api)
        @test occursin("`toy_limit` — value in ToyApi", hits)
        # A name that opens with an underscore is the module's own business.
        @test !occursin("_toy_inside", search_api("toy"; api = set.api, detail = "names"))
        @test occursin("How many toys a box holds.", hits)
        @test occursin("bound a count", read_resource(set, "resource://value/ToyApi/toy_limit"))
        @test startswith(read_resource(set, "resource://value/ToyApi/nothing_here"), "Value 'nothing_here' is not")
        @test strip(execute_julia_code(set, nothing, "toy_limit + 1")) == "4"
    end

    @testset "a name read under the wrong module is pointed to its own" begin
        # A model guesses the module of a verb it found, and guesses wrong; the
        # answer says where the name is and the URI that reads it there.
        set = register_default_tools!(ToolSet(; api = Module[ToyApi, ToyExtra]))
        @test read_resource(set, "resource://function/ToyExtra/toy_verb") ==
              "Function 'toy_verb' is not in module 'ToyExtra'. It is declared in 'ToyApi': " *
              "read `resource://function/ToyApi/toy_verb`."
        @test read_resource(set, "resource://value/ToyExtra/toy_limit") ==
              "Value 'toy_limit' is not in module 'ToyExtra'. It is declared in 'ToyApi': " *
              "read `resource://value/ToyApi/toy_limit`."
        @test startswith(read_resource(set, "resource://function/ToyExtra/nothing_here"),
                         "Function 'nothing_here' is not one of the names you may write.")
    end

    # The resources a declared set publishes are its own modules AND the guides.
    #
    # The guides were once withheld from a declared set, on the reasoning that
    # they describe the whole editor and would send a model to read about a
    # surface it cannot reach. That was wrong in one way and then wrong in
    # another. `search_guides` went on printing `resource://guide/…` for
    # every hit it found, and `read_resource` could not resolve one, so a model
    # told to read a guide spent a round on "Resource not found" — measured
    # 2026-09-13. And an application registers guides of its own with
    # `register_guide_root!`: prose about the window a declared surface belongs
    # to, which is the documentation such a surface most wants.
    #
    # A declaration narrows the NAMES a model may write. It is not a reason to
    # withhold the prose about how to write them.
    @testset "the resources are the declared modules and the guides" begin
        set = register_default_tools!(ToolSet(; api = Module[ToyApi]))
        uris = [r.uri for r in list_resources(set)]
        @test "resource://module/ToyApi" in uris
        @test "resource://modules" in uris
        @test occursin("ToyApi", read_resource(set, "resource://modules"))
        @test occursin("Answer the word", read_resource(set, "resource://module/ToyApi")) ||
              occursin("ToyApi", read_resource(set, "resource://module/ToyApi"))

        # Every guide a search can name, a read can fetch.
        guides = [u for u in uris if startswith(u, "resource://guide/")]
        @test !isempty(guides)
        @test !occursin("not found", read_resource(set, first(guides)))

        wide = register_default_tools!(ToolSet())
        wide_uris = [r.uri for r in list_resources(wide)]
        @test any(u -> startswith(u, "resource://guide"), wide_uris)
    end

    # The folder lives until the process ends, as the registered root does.
    @testset "a guide root that an application registers is read" begin
        directory = mktempdir()
        write(joinpath(directory, "toy-guide.md"),
              "# Toy guide\n\nA toy box keeps its zephyrquartz lid shut.\n")
        register_guide_root!(directory; prefix = "toyroot/")
        @test occursin("zephyrquartz", read_guide("toyroot/toy-guide"))
        set = register_default_tools!(ToolSet(; api = Module[ToyApi]))
        @test occursin("zephyrquartz",
                       read_resource(set, "resource://guide/toyroot/toy-guide"))
        @test occursin("resource://guide/toyroot/toy-guide#toy-guide",
                       search_guides("zephyrquartz"))
    end

    # The description the model reads names the modules it may call, so it is not
    # sent to read five guides about a surface it does not have.
    @testset "the tool description follows the declaration" begin
        set = register_default_tools!(ToolSet(; api = Module[ToyApi]))
        tool = only(t for t in list_tools(set) if t.name == "execute_julia_code")
        @test occursin("ToyApi", tool.description)
        @test !occursin("resource://guide/getting-started", tool.description)

        wide = only(t for t in list_tools(register_default_tools!(ToolSet()))
                    if t.name == "execute_julia_code")
        @test occursin("Projectured", wide.description)
    end

    # A declaration that arrives after the namespace was built must still take
    # effect, so it drops the namespace.
    @testset "declaring after the first evaluation still takes effect" begin
        set = ToolSet()
        @test occursin("Cell", execute_julia_code(set, nothing, "string(Cell)"))
        declare_api!(set, Module[ToyApi])
        @test occursin("UndefVarError", execute_julia_code(set, nothing, "string(Cell)"))
        @test strip(execute_julia_code(set, nothing, "toy_verb()")) == "\"toy\""
        declare_api!(set, Module[])
        @test occursin("Cell", execute_julia_code(set, nothing, "string(Cell)"))
    end

    # How to look is always in scope, and it looks only at what was declared.
    @testset "the model can look things up from the code it writes" begin
        set = ToolSet(; api = Module[ToyApi])
        found = execute_julia_code(set, nothing, "search_api(\"toy\")")
        @test occursin("toy_verb", found)
        doc = execute_julia_code(set, nothing,
                                 "read_function_documentation(\"ToyApi\", \"toy_verb\")")
        @test occursin("Answer the word", doc)
        # It cannot widen its own view: the declaration is applied for it.
        @test occursin("No API matches", execute_julia_code(set, nothing, "search_api(\"Cell\")"))
    end

    @testset "a docstring is the interface, and it is readable" begin
        set = ToolSet(; api = Module[ToyApi])
        doc = read_function_documentation("ToyApi", "toy_verb"; api = set.api)
        @test occursin("Answer the word", doc)
    end

end
end # test_declared_api
