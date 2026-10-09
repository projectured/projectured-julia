# ============================================================================
# The export guard — the export block of a module, where a machine can read it.
#
# `documentation/rule/code-quality-rules.md` §1 says it: the export block has
# one statement for each fragment, in the order of the includes, and a
# statement names what one fragment defines, in the order that the fragment
# defines it. The interface fragment comes first and names every generic that
# it declares. No comment stands inside the block.
#
# **What a fragment defines** is read from its syntax: a function, a method, a
# `function f end` declaration, a type, a `const`, a global, a macro and the
# values of an `@enum`, also inside a macro call such as `@inline` or a
# docstring. A method that extends another module (`Base.show(…)`) defines no
# name. A fragment that includes another file defines what that file defines.
# A name is owned by the first fragment, in include order, that defines it, so
# an interface owns the generics that it declares.
#
# **Static.** It parses each file with the parser of Julia and loads nothing, so
# it runs in about a second.
# ============================================================================

"The folders the rule covers."
const EXPORT_ROOTS = ["source"]

# The module files whose purpose is to export again what other modules define, such
# as the names that most users call. Such a file includes no fragment and defines
# nothing, so the rule does not apply to it. A file here that includes a fragment
# is reported.
const EXPORT_REEXPORTING = Set(String[
    "source/platform/essentials/EssentialsModule.jl",
])

# The module files that do not follow the rule yet. The migration of
# `plan/pending/export-block-rule.md` empties this list. A file here that
# follows the rule is reported, so the list can not go stale.
const EXPORT_UNMIGRATED = Set(String[
    "source/platform/assistant/AssistantModule.jl",
    "source/domain/book/BookModule.jl",
    "source/domain/chart/ChartModule.jl",
    "source/platform/clipboard/ClipboardModule.jl",
    "source/platform/collection/CollectionModule.jl",
    "source/platform/conversation/ConversationModule.jl",
    "source/domain/database/DatabaseModule.jl",
    "source/domain/dbcatalog/DbCatalogModule.jl",
    "source/platform/domain/DomainModule.jl",
    "source/platform/dragging/DraggingModule.jl",
    "source/platform/fault/FaultViewModule.jl",
    "source/platform/fileformat/FileFormatModule.jl",
    "source/platform/filesystem/FileSystemModule.jl",
    "source/platform/focus/FocusModule.jl",
    "source/domain/formula/FormulaModule.jl",
    "source/domain/fsm/FsmModule.jl",
    "source/platform/gesturehelp/GestureHelpModule.jl",
    "source/platform/gesturelog/GestureLogModule.jl",
    "source/domain/graph/GraphModule.jl",
    "source/platform/graphics/GraphicsModule.jl",
    "source/platform/inspector/InspectorModule.jl",
    "source/domain/json/JsonModule.jl",
    "source/domain/julia/JuliaModule.jl",
    "source/kernel/agent/AgentModule.jl",
    "source/kernel/backend/BackendModule.jl",
    "source/kernel/binding/GestureBindingModule.jl",
    "source/kernel/document/DocumentModule.jl",
    "source/kernel/editor/EditorModule.jl",
    "source/kernel/fault/FaultModule.jl",
    "source/kernel/intent/IntentModule.jl",
    "source/kernel/iomap/IoMapModule.jl",
    "source/kernel/llm/LlmModule.jl",
    "source/kernel/operation/OperationModule.jl",
    "source/kernel/performance/PerformanceModule.jl",
    "source/kernel/projection/ProjectionModule.jl",
    "source/kernel/reference/ReferenceModule.jl",
    "source/kernel/selection/SelectionModule.jl",
    "source/kernel/tool/ToolModule.jl",
    "source/platform/layout/LayoutModule.jl",
    "source/platform/log/MessageLogModule.jl",
    "source/domain/markdown/MarkdownModule.jl",
    "source/domain/math/MathModule.jl",
    "source/platform/natural/NaturalModule.jl",
    "source/adapter/odbc/OdbcModule.jl",
    "source/platform/pane/PaneModule.jl",
    "source/platform/plot/PlotModule.jl",
    "source/platform/primitive/PrimitiveModule.jl",
    "source/domain/process/ProcessModule.jl",
    "source/platform/projection/ProjectionAlgebraModule.jl",
    "source/platform/reflection/ReflectionModule.jl",
    "source/domain/rst/RstModule.jl",
    "source/platform/screen/ScreenModule.jl",
    "source/domain/sequencechart/SequenceChartModule.jl",
    "source/platform/serialization/SerializationModule.jl",
    "source/platform/shell/ShellModule.jl",
    "source/domain/sql/SqlModule.jl",
    "source/platform/statistics/FrameStatisticsModule.jl",
    "source/platform/style/StyleModule.jl",
    "source/platform/syntax/SyntaxModule.jl",
    "source/platform/text/TextModule.jl",
    "source/platform/tooltip/TooltipModule.jl",
    "source/platform/undo/UndoModule.jl",
    "source/platform/versioning/VersioningModule.jl",
    "source/platform/widget/WidgetModule.jl",
    "source/domain/xml/XmlModule.jl",
    "source/domain/yaml/YamlModule.jl",
])

"One `export` statement: where it stands, and the names it lists."
struct ExportStatement
    line::Int
    names::Vector{Symbol}
end

"The name that a signature or a type head introduces, or `nothing`."
function _get_defined_name(head)
    head isa Symbol && return head
    head isa Expr || return nothing
    if head.head in (:where, :(::), :(<:)) && !isempty(head.args)
        return _get_defined_name(head.args[1])
    elseif head.head === :curly
        return _get_defined_name(head.args[1])
    elseif head.head === :call
        callee = head.args[1]
        # `Base.show(…)` and `(::T)(…)` extend what exists; they name nothing new.
        callee isa Symbol && return callee
        callee isa Expr && callee.head === :curly && return _get_defined_name(callee)
        return nothing
    end
    return nothing
end

function _collect_defined_names!(found, expression, directory, seen_files)
    expression isa Expr || return
    head = expression.head
    if head === :function || head === :macro
        signature = expression.args[1]
        name = _get_defined_name(signature)
        name === nothing && return
        push!(found, head === :macro ? Symbol("@", name) : name)
    elseif head === :(=) && expression.args[1] isa Expr &&
           expression.args[1].head in (:call, :where, :(::))
        name = _get_defined_name(expression.args[1])
        name === nothing || push!(found, name)
    elseif head === :(=) && expression.args[1] isa Symbol
        push!(found, expression.args[1])
    elseif head === :const || head === :global
        for argument in expression.args
            _collect_defined_names!(found, argument, directory, seen_files)
        end
    elseif head === :struct
        name = _get_defined_name(expression.args[2])
        name === nothing || push!(found, name)
    elseif head === :abstract || head === :primitive
        name = _get_defined_name(expression.args[1])
        name === nothing || push!(found, name)
    elseif head === :macrocall
        macro_name = expression.args[1]
        arguments = filter(a -> !(a isa LineNumberNode), expression.args[2:end])
        # `@theme struct T` defines `T` and its scaled theme `ScaledT`.
        if macro_name === Symbol("@enum") && !isempty(arguments)
            push!(found, _get_defined_name(arguments[1]))
            for value in arguments[2:end]
                value isa Symbol && push!(found, value)
                value isa Expr && value.head === :block &&
                    foreach(v -> v isa Symbol && push!(found, v), value.args)
            end
        else
            for argument in arguments
                _collect_defined_names!(found, argument, directory, seen_files)
            end
        end
        # `@theme struct T` defines `T` and, after it, its scaled theme `ScaledT`.
        declared = isempty(arguments) ? nothing : arguments[end]
        if macro_name === Symbol("@theme") && declared isa Expr && declared.head === :struct
            name = _get_defined_name(declared.args[2])
            name === nothing || push!(found, Symbol("Scaled", name))
        end
    elseif head === :call && expression.args[1] === :include &&
           length(expression.args) == 2 && expression.args[2] isa String
        _collect_fragment_file_names!(found, joinpath(directory, expression.args[2]),
                                      seen_files)
    elseif head in (:block, :toplevel, :if, :elseif)
        for argument in expression.args
            _collect_defined_names!(found, argument, directory, seen_files)
        end
    end
    nothing
end

function _collect_fragment_file_names!(found, file, seen_files)
    (file in seen_files || !isfile(file)) && return
    push!(seen_files, file)
    tree = Meta.parseall(read(file, String); filename = file)
    _collect_defined_names!(found, tree, dirname(file), seen_files)
end

"""
    find_fragment_names(file) -> Vector{Symbol}

Every name that a fragment file defines, in the order that it defines them, the
files that it includes counted in.
"""
function find_fragment_names(file::AbstractString)
    found = Symbol[]
    _collect_fragment_file_names!(found, file, Set{String}())
    unique!(found)
end

"The body of the first `module` in a parsed file, or `nothing`."
function _find_module_body(tree)
    tree isa Expr || return nothing
    tree.head === :module && return tree.args[3]
    for argument in tree.args
        body = _find_module_body(argument)
        body === nothing || return body
    end
    nothing
end

"""
    read_module_header(file) -> (; exports, includes)

The `export` statements of a module file with their lines, and the files that it
includes, in order.
"""
function read_module_header(file::AbstractString)
    body = _find_module_body(Meta.parseall(read(file, String); filename = file))
    exports = ExportStatement[]
    includes = String[]
    line = 0
    body === nothing && return (; exports, includes)
    for statement in body.args
        if statement isa LineNumberNode
            line = statement.line
        elseif statement isa Expr && statement.head === :export
            push!(exports, ExportStatement(line, Symbol[a for a in statement.args]))
        elseif statement isa Expr && statement.head === :call &&
               statement.args[1] === :include && length(statement.args) == 2 &&
               statement.args[2] isa String
            push!(includes, statement.args[2])
        end
    end
    (; exports, includes)
end

"The lines of the export block that hold a comment, from the first statement to the last."
function _find_export_comments(file, exports)
    isempty(exports) && return Int[]
    lines = readlines(file)
    found = Int[]
    first_line = exports[1].line
    last_line = exports[end].line
    # The last statement ends where a line of it no longer ends in a comma.
    while last_line < length(lines)
        code = strip(split(lines[last_line], '#'; limit = 2)[1])
        (endswith(code, ",") || isempty(code)) || break
        last_line += 1
    end
    for number in first_line:last_line
        occursin('#', lines[number]) && push!(found, number)
    end
    found
end

"""
    export_violations(root) -> Vector{String}

Every place where a module file breaks the rule of the export block, as
`file:line: what`. A module in `EXPORT_UNMIGRATED` is excused, and reported when
it follows the rule. A module in `EXPORT_REEXPORTING` exports what other modules
define, and is reported when it includes a fragment.
"""
function export_violations(root::AbstractString)
    violations = String[]
    for folder in EXPORT_ROOTS, (directory, _, files) in walkdir(joinpath(root, folder))
        for name in sort(files)
            endswith(name, "Module.jl") || continue
            file = joinpath(directory, name)
            relative = relpath(file, root)
            if relative in EXPORT_REEXPORTING
                isempty(read_module_header(file).includes) || push!(violations,
                    "$relative: includes a fragment; remove it from EXPORT_REEXPORTING")
                continue
            end
            found = check_export_block(file)
            if relative in EXPORT_UNMIGRATED
                isempty(found) && push!(violations,
                    "$relative: follows the rule; remove it from EXPORT_UNMIGRATED")
            else
                append!(violations, found)
            end
        end
    end
    violations
end

"""
    check_export_block(file) -> Vector{String}

What breaks the rule of the export block in one module file.
"""
function check_export_block(file::AbstractString)
    found = String[]
    relative = relpath(file, normpath(joinpath(@__DIR__, "..", "..")))
    header = read_module_header(file)
    isempty(header.exports) && return found
    directory = dirname(file)
    fragment_names = [find_fragment_names(joinpath(directory, fragment))
                      for fragment in header.includes]
    owner(name) = findfirst(names -> name in names, fragment_names)
    last_fragment = 0
    for statement in header.exports
        owners = [owner(name) for name in statement.names]
        for (name, index) in zip(statement.names, owners)
            index === nothing && push!(found,
                "$relative:$(statement.line): no fragment defines `$name`; another " *
                "module or a macro exports it already")
        end
        known = unique(filter(!isnothing, owners))
        if length(known) > 1
            push!(found, "$relative:$(statement.line): one statement names " *
                         join(header.includes[known], ", "))
        end
        isempty(known) && continue
        fragment = first(known)
        if fragment <= last_fragment
            push!(found, "$relative:$(statement.line): $(header.includes[fragment]) " *
                         "comes after a later fragment or has two statements")
        end
        last_fragment = max(last_fragment, fragment)
        if length(known) == 1
            order = filter(!isnothing, [findfirst(==(name), fragment_names[fragment])
                                        for name in statement.names])
            issorted(order) || push!(found, "$relative:$(statement.line): the names " *
                "are not in the order that $(header.includes[fragment]) defines them")
        end
    end
    for line in _find_export_comments(file, header.exports)
        push!(found, "$relative:$line: a comment inside the export block")
    end
    found
end

"""
    export_report(root)

Print every module file under the roots with what breaks the rule in it, and
whether `EXPORT_UNMIGRATED` names it.
"""
function export_report(root::AbstractString)
    for folder in EXPORT_ROOTS, (directory, _, files) in walkdir(joinpath(root, folder))
        for name in sort(files)
            endswith(name, "Module.jl") || continue
            file = joinpath(directory, name)
            relative = relpath(file, root)
            found = check_export_block(file)
            state = isempty(found) ? "follows" : "$(length(found)) problem(s)"
            listed = relative in EXPORT_UNMIGRATED ? ", listed" : ""
            println(rpad(relative, 60), state, listed)
            foreach(f -> println("    ", f), found)
        end
    end
    nothing
end

# Runnable on its own. It needs no environment and no dependency:
#
#     julia test/suite/exports.jl
#     julia test/suite/exports.jl --report
#
if abspath(PROGRAM_FILE) == @__FILE__
    root = normpath(joinpath(@__DIR__, "..", ".."))
    if "--report" in ARGS
        export_report(root)
    else
        bad = export_violations(root)
        if isempty(bad)
            println("every export block has one statement for each fragment")
        else
            println("$(length(bad)) export violation(s):")
            foreach(v -> println("  ", v), bad)
            exit(1)
        end
    end
end
