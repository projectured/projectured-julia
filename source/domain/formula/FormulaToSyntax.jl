# Fragment of `FormulaModule`.
#
# Formula → Syntax projection, composed with the Julia and the math projections so a
# formula and the nodes of its code render through one shared `recursion`:
#
# - `FormulaFormula` → `SyntaxNode` with three layouts selected by the formula's
#   `display_mode` cell (`:code` / `:result` / `:both`).
# - `FormulaEnvironment` → `SyntaxNode`, one formula per line.
#
# Mappers follow the School-A peel-and-delegate pattern (see the tutorial and
# package/kernel/doc/projection-system.md): each node peels the one step it owns and delegates
# the tail through the stored child IO maps. `FormulaToSyntax()` merges the Julia
# type-dispatch table with the Formula entries into a single
# `TypeDispatchingProjection` (callers wrap it once in `RecursiveProjection`, as
# with `JuliaToSyntax`).
# ── Leaf helpers ─────────────────────────────────────────────────────────────

_empty(font) = TextString("", font)

# ── FormulaInsertionToSyntaxLeaf ───────────────────────────────────────────────
#
# The "insert formula" placeholder. A projection-introduced leaf with no editable
# input value, so the default mappers are correct: the backward map names a caret
# on the text by the leaf's own introduced step, and the forward map answers the
# path in the leaf. Each leaf of this file maps its paths forward into cells
# of its own.

function _make_forward_path_leaf(p, input, make_leaf)
    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(input, path -> begin
        iomap = iomap_cell[]
        iomap === nothing ? nothing : map_reference_forward(p, iomap, path)
    end)
    iomap = SimpleIoMap(p, input, make_leaf(paths))
    iomap_cell[] = iomap
    iomap
end

@projection UntrackedCell struct FormulaInsertionToSyntaxLeaf
    style::StyleText = get_formula_style(nothing, :insertion_text)
end

print_document(p::FormulaInsertionToSyntaxLeaf, recursion, b::FormulaInsertion, ctx) =
    _make_forward_path_leaf(p, b,
        paths -> SyntaxLeaf(TextString("insert formula", p.style); paths...))

# ── FormulaIdentifierToSyntaxLeaf ──────────────────────────────────────────────
#
# An identifier of the code of a formula: in the reference style when it refers to
# a formula of the sheet, and in the identifier style of Julia otherwise. The
# formula rule gives the code the set of its reference identifiers through the
# printer context, `:formula_references`, so a local name that a formula of the
# sheet also has stays plain. The print reads the set, so a change of it prints
# the identifier again. A callee draws through the call rule of Julia, and keeps
# the callee style.

@projection UntrackedCell struct FormulaIdentifierToSyntaxLeaf
    style::StyleText = JuliaModule.get_julia_style(nothing, :identifier_text)
    reference::StyleText = get_formula_style(nothing, :reference_text)
end

function print_document(p::FormulaIdentifierToSyntaxLeaf, recursion, identifier::JuliaIdentifier,
                        ctx)
    references = get(ctx.properties, :formula_references, nothing)
    style = references !== nothing && identifier in references[] ? p.reference : p.style
    print_template_document(p, recursion, identifier, ctx,
                            (p, v) -> SyntaxLeaf(TextString(() -> v.name, style)))
end

read_intent(p::FormulaIdentifierToSyntaxLeaf, recursion, change::Intent, iomap) =
    read_template_intent(p, recursion, change, iomap)

# ── FormulaFormulaToSyntaxNode ─────────────────────────────────────────────────
#
# Three layouts selected by the formula's `display_mode` cell:
#   :code   → recurse into `code`                         → children [code]
#   :result → recurse into `result`                       → children [result]
#   :both   → name " = " code " ⇒ " result                → children [code, result]
#
# In edit mode the draft takes the place of the code, and no value shows, because
# the stored value belongs to the code: `:both` is name " = " draft.
#
# The `code` child is recursed through the shared `recursion`; the `result` is a
# computed value of any type, so it shows as one leaf of its text rather than
# recursed (mirrors how EvaluatorForm renders its result). Only `code` therefore
# needs School-A delegation; its output child index depends on the mode.

@projection UntrackedCell struct FormulaFormulaToSyntaxNode
    name::StyleText = get_formula_style(nothing, :name_text)
    op::StyleText   = get_formula_style(nothing, :operator_text)
    # The result run shares the op font but is coloured distinctly (green).
    result::StyleText = get_formula_style(nothing, :result_text)
end

function print_document(p::FormulaFormulaToSyntaxNode, recursion, f::FormulaFormula, ctx)
    environment = get(ctx.properties, :formula_environment, nothing)
    references = Cell(@computation environment === nothing ? Base.IdSet{Any}() :
                                   _find_reference_identifiers(f, environment))
    # The code, or the draft in edit mode, each printed under its own field.
    code_iomap = Cell(@computation begin
        draft = f.draft
        step = draft === nothing ? (@reference_step code) : (@reference_step draft)
        context = with_property(make_child_context(ctx, f, step), :formula_references, references)
        print_child(recursion, draft === nothing ? f.code : draft, context)
    end)

    # The name leaf displays the formula name; renaming is a structural
    # operation, not character editing here, so it carries no input mapping.
    name_leaf = SyntaxLeaf(TextString(() -> f.name, p.name))
    eq_leaf = SyntaxLeaf(
        TextString("=", p.op);
        open=TextString(" ", p.op.font),
        close=TextString(" ", p.op.font))
    arrow_leaf = SyntaxLeaf(
        TextString("⇒", p.op);
        open=TextString(" ", p.op.font),
        close=TextString(" ", p.op.font))
    # The stored value, and a mark while a computation of it runs. A print runs no
    # code of the formula.
    result_leaf = SyntaxLeaf(TextString(() -> _format_stored_formula_value(f), p.result))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(f, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(@computation begin
            mode = f.display_mode
            if mode === :code
                SyntaxDocument[code_iomap[].output]
            elseif mode === :result
                SyntaxDocument[result_leaf]
            elseif f.draft !== nothing  # :both, in edit mode
                SyntaxDocument[name_leaf, eq_leaf, code_iomap[].output]
            else  # :both (default)
                SyntaxDocument[name_leaf, eq_leaf, code_iomap[].output,
                               arrow_leaf, result_leaf]
            end
        end);
        paths...)
    iomap = ChildrenIoMap(p, f, node, Cell(@computation IoMap[code_iomap[]]))
    iomap_cell[] = iomap
    iomap
end

# School A for `code`. Its output child index depends on the mode:
#   :code → children[1]
#   :both → children[3]   (after name + "=")
# (In :result mode `code` is not shown, so it has no output position.)
function _code_index(f::FormulaFormula)
    mode = f.display_mode
    mode === :code ? 1 : (mode === :result ? nothing : 3)
end

function map_reference_forward(p::FormulaFormulaToSyntaxNode, iomap::ChildrenIoMap, reference)
    f = iomap.input
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        # The name, where the layout shows it: as a whole, as a jump to the
        # definition selects it, and a place in it, where a key types.
        ::FormulaFormula.name => if f.display_mode === :both
            @reference ::SyntaxNode.children::CellVector[1]::SyntaxLeaf
        end
        ::FormulaFormula.name.rest... => if f.display_mode === :both &&
                                            rest isa ConcreteReference &&
                                            rest.head isa RangeReferenceStep
            @reference ::SyntaxNode.children::CellVector[1]::SyntaxLeaf.value::TextString.^(rest)
        end
        ::FormulaFormula.code.rest... => f.draft === nothing ? _map_code_forward(f, iomap, rest) : nothing
        ::FormulaFormula.draft.rest... => f.draft === nothing ? nothing : _map_code_forward(f, iomap, rest)
        __ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

# The output place of a place in the code, or in the draft in edit mode, which
# prints at the same child.
function _map_code_forward(f::FormulaFormula, iomap::ChildrenIoMap, rest)
    idx = _code_index(f)
    idx === nothing && return nothing
    child = iomap.child_iomaps[1]
    inner = map_reference_forward(child.projection, child, rest)
    inner === nothing ? nothing : (@reference ::SyntaxNode.children::CellVector[idx].^(inner))
end

function map_reference_backward(p::FormulaFormulaToSyntaxNode, iomap::ChildrenIoMap, reference)
    f = iomap.input
    idx = _code_index(f)
    @reference_case reference begin
        ∅ => @reference ::FormulaFormula
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            if idx !== nothing && child_i == idx
                # This child is the code sub-tree, or the draft in edit mode:
                # delegate to its mapper.
                child = iomap.child_iomaps[1]
                inner = map_reference_backward(child.projection, child, rest)
                inner === nothing ? nothing :
                    f.draft === nothing ? (@reference ::FormulaFormula.code.^(inner)) :
                                          (@reference ::FormulaFormula.draft.^(inner))
            elseif child_i == 1 && f.display_mode === :both
                # The text of the name leaf is the name.
                @reference_case rest begin
                    value.tail... => @reference ::FormulaFormula.name::String.^(tail)
                    __ => @invoke map_reference_backward(p::Projection, iomap, reference)
                end
            else
                # Projection-introduced child (name, "=", "⇒", result): wrap as
                # structural reference so the roundtrip can place a cursor.
                @invoke map_reference_backward(p::Projection, iomap, reference)
            end
        end
        __ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

# ── FormulaEnvironmentToSyntaxNode ─────────────────────────────────────────────
#
# A plain list — one formula per line — like BookmarkList in the tutorial.

@projection UntrackedCell struct FormulaEnvironmentToSyntaxNode
    font::StyleFont = get_formula_style(nothing, :plain_font)
end

function print_document(p::FormulaEnvironmentToSyntaxNode, recursion, e::FormulaEnvironment, ctx)
    # Each formula reads the sheet from the printer context, to find which of its
    # identifiers refer to a formula of it.
    child_iomaps = Cell(@computation([print_child(recursion, e.formulas[i],
             with_property(make_child_context(ctx, e, (@reference_step formulas),
                                              (@reference_step [i])),
                           :formula_environment, e))
         for i in 1:length(e.formulas)]))

    iomap_cell = Cell(nothing)
    paths = make_output_path_cells(e, path -> begin
        im = iomap_cell[]
        im === nothing ? nothing : map_reference_forward(p, im, path)
    end)
    node = SyntaxNode(
        CellVector(@computation SyntaxDocument[im.output for im in child_iomaps[]]);
        sep=TextString("\n", p.font),
        paths...)
    iomap = ChildrenIoMap(p, e, node, child_iomaps)
    iomap_cell[] = iomap
    iomap
end

function map_reference_forward(p::FormulaEnvironmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::SyntaxNode
        ::FormulaEnvironment.formulas{s:_}.rest... => begin
            child_i = s + 1
            ims = iomap.child_iomaps
            (child_i < 1 || child_i > length(ims)) && return nothing
            child = ims[child_i]
            inner = map_reference_forward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference ::SyntaxNode.children::CellVector[child_i].^(inner))
        end
        __ => @invoke map_reference_forward(p::Projection, iomap, reference)
    end
end

function map_reference_backward(p::FormulaEnvironmentToSyntaxNode, iomap::ChildrenIoMap, reference)
    @reference_case reference begin
        ∅ => @reference ::FormulaEnvironment
        ::SyntaxNode.children{s:_}.rest... => begin
            child_i = s + 1
            ims = iomap.child_iomaps
            (child_i < 1 || child_i > length(ims)) && return nothing
            child = ims[child_i]
            inner = map_reference_backward(child.projection, child, rest)
            inner === nothing ? nothing : (@reference ::FormulaEnvironment.formulas::CellVector[child_i].^(inner))
        end
        __ => @invoke map_reference_backward(p::Projection, iomap, reference)
    end
end

# ── Ctrl+click goes to the definition ────────────────────────────────────────
#
# Ctrl+click on an identifier that refers to a formula of the sheet selects the
# name of that formula, as Ctrl+click follows a link in the source of a page: a
# plain click selects the identifier, to edit it. The sheet reads the click,
# because it is the lowest node that holds both the reference and the definition.
# It reads the click where it is the root of the view; in a view that prints it
# inside a template, the parent asks only the gesture bindings of the parts.

function read_intent(p::FormulaEnvironmentToSyntaxNode, recursion, change::Intent, iomap)
    # A formula in edit mode takes Enter and Escape first.
    own = _read_formula_edit_key(iomap.input, change)
    own === nothing ||
        return Intent(change.gesture, _give_formula_environment(own, iomap.input), "Edit the formula", "formula")
    answer = @invoke read_intent(p::Projection, recursion, change::Intent, iomap)
    # A commit of a formula computes it again in this sheet, and a write of the code
    # of a formula in value mode starts its edit mode.
    answer.operation === nothing || (answer = _read_formula_edit(iomap.input, answer))
    # A key that types in a name renames the formula; see the section below.
    answer.operation isa ReplaceStringRangeOperation && return _read_rename(iomap.input, answer)
    gesture = change.gesture
    (gesture isa MouseClick && gesture.button === :left &&
     gesture.modifiers == ModifierKeys(ctrl = true)) || return answer
    operation = answer.operation
    operation isa ReplaceSelectionOperation || return answer
    definition = _find_definition_reference(iomap.input, operation.path)
    definition === nothing && return answer
    Intent(gesture, ReplaceSelectionOperation(definition), "Go to the definition", "formula")
end

# The reference, from the sheet, of the definition that the identifier at `path`
# refers to: the name of the formula where its layout shows the name, and the
# formula otherwise. `nothing` when `path` reaches no reference identifier.
function _find_definition_reference(env::FormulaEnvironment, path)
    identifier = _find_last_identifier(env, path)
    identifier === nothing && return nothing
    for formula in env.formulas
        identifier in _find_reference_identifiers(formula, env) || continue
        target = resolve(env, identifier.name)
        index = findfirst(f -> f === target, collect(env.formulas))
        return target.display_mode === :both ? @reference(env, formulas[index].name) :
                                               @reference(env, formulas[index])
    end
    nothing
end

# The deepest identifier that `path` goes through from `node`.
function _find_last_identifier(node, path)
    found = nothing
    while path isa ConcreteReference
        node = try
            evaluate_reference_step(path.head, node)
        catch exception
            is_fault_exception(exception) || rethrow()
            break
        end
        node isa JuliaIdentifier && (found = node)
        path = path.tail
    end
    found
end

# ── A key in the name renames the formula ─────────────────────────────────────
#
# A key that types in the name of a formula renames it: the edit of the name and
# the new name in each use of the formula, as one operation, so every use keeps
# its formula while a person types. Undo takes back one key; an undo buffer can
# merge the keys of one name. A key that would make a use mean something else does
# nothing, and the description of the answer says why: a math formula uses the
# name (its uses are math nodes, and a rename writes Julia identifiers), another
# formula has the new name, or a local name of the code would take the use.

function _read_rename(env::FormulaEnvironment, answer::Intent)
    edit = answer.operation
    steps = get_reference_steps(strip_reference_types(edit.reference))
    (length(steps) == 4 && steps[1] == FieldReferenceStep("formulas") &&
     steps[2] isa RangeReferenceStep && steps[3] == FieldReferenceStep("name") &&
     steps[4] isa RangeReferenceStep) || return answer
    formula = env.formulas[steps[2].stop]
    name = splice_string(formula.name, steps[4].start, steps[4].stop, edit.replacement)
    writes, reason = _make_rename_writes(env, formula, name)
    reason === nothing || return Intent(answer.gesture, nothing, reason, "formula")
    # A name that adds, removes or changes the parameter changes what the formula
    # and the formulas that name it mean, so the formula computes again.
    changes_parameter = _find_formula_parameter(formula) != _find_formula_parameter(name)
    isempty(writes) && !changes_parameter && return answer
    operations = Any[edit, writes...]
    changes_parameter && push!(operations, ComputeFormulasOperation(env, FormulaFormula[formula]))
    Intent(answer.gesture, CompoundOperation(operations),
           "Rename the formula and its uses", "formula")
end

# Whether the math notation reads a name; `f(` is half a name and reads as none.
function _is_readable_name(name::AbstractString)
    try
        parse_math(String(name))
        return true
    catch e
        e isa ErrorException || rethrow()
    end
    false
end

# The writes that give each use of `formula` the name `name`, and `nothing`; or no
# writes, and the reason that the rename refuses. A use spelled as the name of the
# formula takes `name`, and a use spelled as its key, such as `rho` for `ρ`, takes
# the key of `name`.
function _make_rename_writes(env::FormulaEnvironment, formula::FormulaFormula, name::String)
    writes = Any[]
    holder = resolve(env, name)
    for (index, user) in enumerate(env.formulas)
        if !(user.code isa JuliaDocument)
            any(used -> resolve(env, used) === formula, _find_readable_names(user)) &&
                return (Any[], "The math formula $(user.name) uses the name, and a rename " *
                               "does not rewrite math")
            continue
        end
        uses = Base.IdSet{Any}(use for use in _find_reference_identifiers(user, env)
                               if resolve(env, use.name) === formula)
        isempty(uses) && continue
        holder === nothing || holder === formula ||
            return (Any[], "The formula $(holder.name) has the name $name")
        scopes = _find_identifier_scopes(user)
        places = _collect_node_steps!(IdDict{Any,Vector{Any}}(), user.code, uses, Any[])
        for use in uses
            spelling = use.name == formula.name ? name : get_formula_key(name)
            # A name that does not read yet, such as `f(`, gives the use no name.
            _is_readable_name(name) || continue
            spelling in scopes[use] &&
                return (Any[], "A local $spelling of $(user.name) would take the use")
            reference = Reference(FieldReferenceStep("formulas"), ElementReferenceStep(index),
                                  FieldReferenceStep("code"), places[use]...,
                                  FieldReferenceStep("name"))
            push!(writes, ReplaceReferencedValueOperation(nothing, reference, spelling))
        end
    end
    (writes, nothing)
end

# The steps from `node` to each node of `wanted`, by field and by element.
function _collect_node_steps!(found::IdDict, node, wanted, steps::Vector{Any})
    node in wanted && (found[node] = copy(steps))
    node isa Document || return found
    for fname in fieldnames(typeof(node))
        is_view_state_field(fname) && continue
        child = getfield(node, fname)[]
        push!(steps, FieldReferenceStep(String(fname)))
        if child isa CellVector
            for (index, element) in enumerate(child)
                push!(steps, ElementReferenceStep(index))
                _collect_node_steps!(found, element, wanted, steps)
                pop!(steps)
            end
        else
            _collect_node_steps!(found, child, wanted, steps)
        end
        pop!(steps)
    end
    found
end

# ── FormulaToSyntax convenience constructor ────────────────────────────────────
#
# Merge the Julia type-dispatch table with the Formula entries and the rules of
# the math notation into one TypeDispatchingProjection, wrapped once in
# RecursiveProjection, so the same `recursion` renders a formula, Julia code and
# math code, which prints in its linear form, such as `C/2`.

# Returns a bare `TypeDispatchingProjection` (the convention used by
# JuliaToSyntax / JsonToSyntax / BookToSyntax); callers wrap it once in a
# `RecursiveProjection` so node projections can recurse children.
#
# The builder gives each projection the style of its role with
# `get_formula_style`, from `theme`, a `FormulaTheme` scaled or not, or the
# default styles for `nothing`; `julia_theme`, `math_theme` and `syntax_theme`
# style the Julia and the math nodes that the code of a formula is built from,
# through `JuliaToSyntax` and `MathToSyntax`.
function FormulaToSyntax(; theme = nothing, julia_theme = nothing, math_theme = nothing,
                         syntax_theme = nothing)
    get_style(name) = get_formula_style(theme, name)
    math = MathToSyntax(; theme = math_theme, syntax_theme)
    julia = JuliaToSyntax(
        FormulaInsertion   => FormulaInsertionToSyntaxLeaf(; style = get_style(:insertion_text)),
        FormulaFormula     => FormulaFormulaToSyntaxNode(; name = get_style(:name_text),
                                                            op = get_style(:operator_text),
                                                            result = get_style(:result_text)),
        FormulaEnvironment => FormulaEnvironmentToSyntaxNode(; font = get_style(:plain_font)),
        math.dispatch...;
        theme = julia_theme, syntax_theme)
    # The identifier rule goes first, because the dispatch takes the first match and
    # the Julia table holds a rule for every identifier.
    identifier = FormulaIdentifierToSyntaxLeaf(;
        style = JuliaModule.get_julia_style(julia_theme, :identifier_text),
        reference = get_style(:reference_text))
    TypeDispatchingProjection(JuliaIdentifier => identifier, julia.dispatch...)
end
