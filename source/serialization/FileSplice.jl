# Fragment of `SerializationModule` — loading a set of files without a storage
# node in the document.
#
# Loading is two phases. Every file in the set is parsed by its own format, and
# a reference leaf is an ordinary leaf of the domain at that point: a `JsonString`
# that happens to hold a marker. Then every tree is walked, and each leaf the
# domain recognises as a reference is replaced, in its slot, by the node it
# names. After that no reference leaf remains; two leaves naming one node hold
# the same object, and a cycle is a cycle, because every tree existed before
# any splice.
#
# A reference to a file outside the set stays a leaf. A `JsonString` holding a
# marker is legal JSON: it renders as text and saves back as the same text, so
# a project can be opened one file at a time and lose nothing.

"""
    parse_file_content(::Type{<:FileDocument}, text) -> Document

The content a file's text parses to, with no splice. Every file type defines
it in one line, with the parser of its format.
"""
function parse_file_content end

"""
    make_file(::Type{T}, filename, text) -> file document

The file `text` holds, named `filename`. The default wraps what
[`parse_file_content`](@ref) read, which is what a file with a `content` field
is. A file whose whole node is its content — see [`is_own_content`](@ref) —
defines this instead, because its parser already built the file.
"""
make_file(T::Type, filename::AbstractString, text::AbstractString) =
    T(String(filename), parse_file_content(T, text))

"""
    load_project(base_dir, filenames; follow = false) -> FileProject

Parse every file named, in order, then splice each reference leaf into the node
it names. A marker naming a file outside the set stays a leaf.

`follow = true` opens the files the set reaches as well, and the files those
reach, until nothing is left unopened. That is how one page is opened without
opening every page beside it: name the page, and what the page embeds comes
with it.
"""
function load_project(base_dir::AbstractString, filenames::AbstractVector{<:AbstractString};
                      follow::Bool = false)
    project = FileProject(base_dir, Any[])
    queue = String[String(name) for name in filenames]
    opened = Set{String}()
    while !isempty(queue)
        name = popfirst!(queue)
        normpath(name) in opened && continue
        push!(opened, normpath(name))
        text = read(joinpath(base_dir, name), String)
        file = make_file(get_file_document_type(name), name, text)
        push!(project.files, file)
        follow && append!(queue, _referenced_filenames(file))
    end
    _splice!(project)
    project
end

"""
    load_file(base_dir, filename) -> file document

One file, parsed. A marker in it stays a leaf, because there is nothing in the
set to splice it to.
"""
load_file(base_dir::AbstractString, filename::AbstractString) =
    load_project(base_dir, [filename]).files[1]

# ── What a file reaches ──────────────────────────────────────────────────────

# Every file a marker in `file` names. `file("a.json")` is the only thing that
# names one, and it names one wherever it stands: on its own, as the first
# argument of `node`, or as an argument of a verb a package registered.
_referenced_filenames(file) =
    _collect_references!(String[], get_file_content(file), IdDict{Any,Bool}())

function _collect_references!(names::Vector{String}, node, visited::IdDict)
    node isa Document || return names
    haskey(visited, node) && return names
    visited[node] = true
    marker = find_reference_marker(node)
    if marker !== nothing
        expression = _parse_marker_expression(marker)
        expression === nothing || _collect_file_names!(names, expression)
        return names
    end
    for name in fieldnames(typeof(node))
        name === :selection && continue
        raw = getfield(node, name)
        value = raw isa AbstractCell ? raw[] : raw
        if is_element_collection(value) || value isa AbstractVector
            for element in value
                _collect_references!(names, element, visited)
            end
        else
            _collect_references!(names, value, visited)
        end
    end
    names
end

function _collect_file_names!(names::Vector{String}, e::Expr)
    if e.head === :call && e.args[1] === :file && length(e.args) == 2 &&
       e.args[2] isa AbstractString
        push!(names, String(e.args[2]))
        return names
    end
    for argument in e.args
        argument isa Expr && _collect_file_names!(names, argument)
    end
    names
end

# ── The splice ───────────────────────────────────────────────────────────────

function _splice!(project::FileProject)
    index = Dict{String,Any}(normpath(get_filename(file)) => file for file in project.files)
    visited = IdDict{Any,Bool}()
    for file in project.files
        # A file whose whole content is a reference: the save cut at its root, and
        # a one-statement file parses to the statement itself.
        target = _splice_target(project, index, get_file_content(file))
        if target !== nothing
            getfield(file, :content)[] = target
        else
            _splice_walk!(project, index, get_file_content(file), visited)
        end
    end
    project
end

# Every child slot of `node` whose leaf is a reference gets the node it names,
# written into the slot's cell. The walk visits each object once, so a graph
# the splice closes into a cycle still terminates.
function _splice_walk!(project, index, node, visited::IdDict)
    node isa Document || return
    haskey(visited, node) && return
    visited[node] = true
    for name in fieldnames(typeof(node))
        name === :selection && continue
        raw = getfield(node, name)
        value = raw isa AbstractCell ? raw[] : raw
        if is_element_collection(value)
            for index_in in eachindex(value)
                element = value[index_in]
                target = _splice_target(project, index, element)
                if target !== nothing
                    value[index_in] = target
                else
                    _splice_walk!(project, index, element, visited)
                end
            end
        elseif value isa Document
            target = _splice_target(project, index, value)
            if target !== nothing
                raw isa AbstractCell || error("load_project: a reference sits in a plain field, ",
                                              name, " of ", typeof(node), ", which cannot be spliced")
                raw[] = target
            else
                _splice_walk!(project, index, value, visited)
            end
        end
    end
end

# The node a reference leaf names, or `nothing` when the leaf is not a reference
# or names a file outside the set.
function _splice_target(project, index, leaf)
    marker = find_reference_marker(leaf)
    marker === nothing && return nothing
    expression = _parse_marker_expression(marker)
    expression === nothing &&
        error("load_project: not a marker expression: ", repr(marker))
    target = _evaluate_splice(project, index, expression)
    # `file(…)` names the file's content: the node the save cut at the root. As
    # an argument to another verb it is the file document, which every verb
    # that takes a document accepts.
    target !== nothing && is_file_document(target) ? get_file_content(target) : target
end

# The marker vocabulary, evaluated against the set: `file` and `node` here, a
# capitalised name as a constructor, any other verb through the registry, with
# the arguments evaluated the same way. A `file` naming a file outside the set
# answers `nothing`, and so does anything built on it.
function _evaluate_splice(project, index, e::Expr)
    e.head === :vect && return Any[_evaluate_splice(project, index, a) for a in e.args]
    verb = e.args[1]::Symbol
    positional, keywords = _splice_arguments(project, index, e)
    any(a -> a === nothing, positional) && return nothing
    if verb === :file
        length(positional) == 1 && positional[1] isa AbstractString ||
            error("file(…): expected one path string, got ", join(repr.(positional), ", "))
        return get(index, normpath(String(positional[1])), nothing)
    elseif verb === :node
        length(positional) == 2 && positional[2] isa AbstractString ||
            error("node(…): expected a file and a path string")
        file, text = positional
        return _evaluate_path_text(get_file_content(file), String(text))
    elseif _is_type_name(verb)
        # A capitalised name constructs the type it names: a document is a data
        # structure, and its constructor is how one is written down. Which types
        # a file may name is the registry's business.
        T = get_pred_type(String(verb))
        T === nothing &&
            error("marker: no type named ", verb, " is offered here — a package calls ",
                  "register_pred_type!(", verb, ") to say a file may construct one")
        return make_pred_document(T, positional, keywords)
    end
    f = get_marker_function(verb)
    f === nothing &&
        error("marker: unknown function ", verb, " in ", _canonical_marker(e),
              " — the vocabulary is (", join(marker_function_names(), ", "), ")")
    isempty(keywords) ? f(project, positional...) : f(project, positional...; keywords...)
end

# A literal stands for itself; `nothing` arrives as the name the parser made of
# the word.
_evaluate_splice(project, index, literal) = literal === :nothing ? nothing : literal

function _splice_arguments(project, index, e::Expr)
    positional = Any[]
    keywords = Pair{Symbol,Any}[]
    for argument in @view e.args[2:end]
        if argument isa Expr && argument.head === :parameters
            for kw in argument.args
                push!(keywords, kw.args[1] => _evaluate_splice(project, index, kw.args[2]))
            end
        elseif argument isa Expr && argument.head === :kw
            push!(keywords, argument.args[1] => _evaluate_splice(project, index, argument.args[2]))
        else
            push!(positional, _evaluate_splice(project, index, argument))
        end
    end
    positional, keywords
end

# A file's root is `file(…)`, so a path here always has a step. The text is the
# reference DSL's own form, `entries[2].value`, and the DSL's parser reads it
# back. The save writes a field step and an element index and nothing else, so
# any other step kind in a marker is an error, not a path.
function _evaluate_path_text(root, text::AbstractString)
    steps = ReferenceStep[]
    for step in parse_reference_path(Meta.parse(text))
        if step isa ReferenceSyntaxField
            push!(steps, FieldReferenceStep(step.name))
        elseif step isa ReferenceSyntaxIndex && step.expr isa Integer
            push!(steps, ElementReferenceStep(Int(step.expr)))
        else
            error("node(…): a path may hold field and index steps only, got ", repr(text))
        end
    end
    isempty(steps) && error("node(…): an empty path names the file; write file(…) instead")
    evaluate_reference(root, extend_reference(EmptyReference(), steps...))
end

"""
    evaluate_marker(source::AbstractString, project::FileProject) -> Any

The value a marker body stands for, against `project`: a `file(…)` in it names
one of the project's files, and the whole is what its verb returns. What the
splice does for every reference leaf, offered to a test and to a verb's caller.
"""
function evaluate_marker(source::AbstractString, project::FileProject)
    expression = _parse_marker_expression(source)
    expression === nothing &&
        error("evaluate_marker: not a marker expression: ", repr(source))
    index = Dict{String,Any}(normpath(get_filename(file)) => file for file in project.files)
    _evaluate_splice(project, index, expression)
end
