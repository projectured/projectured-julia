# Fragment of `EditorModule` — the wrappers of an editor, and `build_editor`,
# which chooses the backend, applies the wrappers and makes the editor.
#
# **A wrapper is a keyword of `build_editor`.** A package declares one with a
# method of each wrapper seam for `Val{keyword}`: what the wrapper does to the
# parts of an editor, the layers it acts in, the keywords it excludes, and
# whether it is on when the caller does not name it. The loaded packages are
# the list of the wrappers, and no table names them. `make_editor` applies no
# wrapper, so a test or a program that wants exact control calls it.

"""
    EditorParts

What a wrapper can change before the editor exists:

- `document` and `projection` — what the editor edits, and how it shows it;
- `backend` — the backend the editor runs on, which a wrapper reads and does not
  replace;
- `feeds` — the feeds of the editor;
- `start_steps` — the functions `editor -> nothing` that run once the editor
  exists, such as the attachment of a log to the fault store of the editor;
- `opened_window_projections` — the rows `type => projection` for the documents that a
  wrapper opens later in a window of their own;
- `settings` — the setting of each wrapper that is on, by its keyword, as
  [`make_wrapper_setting`](@ref) made it. A wrapper reads its own setting from its
  argument, and can read the setting of another wrapper here, such as an object
  that the projection of the editor shares with that wrapper. The kernel holds the
  settings and never reads them.
"""
mutable struct EditorParts
    document::Document
    projection::Projection
    backend::Backend
    feeds::Vector{Feed}
    start_steps::Vector{Any}
    opened_window_projections::Vector{Pair{Type,Any}}
    settings::Dict{Symbol,Any}
end

"""
The layers of the wrappers, from the inside out:

- `:document` — acts on each document;
- `:container` — holds the documents, such as tabs;
- `:window` — puts the root in a window of a screen;
- `:screen` — acts once, on the root.
"""
const EDITOR_WRAPPER_LAYERS = (:document, :container, :window, :screen)

"""
    wrap_editor!(::Val{keyword}, layer::Symbol, setting, parts::EditorParts) -> EditorParts

Apply the wrapper of `keyword` in `layer` to `parts`, and give `parts` back.
`setting` is the value of the keyword: `true` for the defaults, or a
`NamedTuple` of settings. The package that declares the wrapper adds the method.
"""
function wrap_editor! end

"""
    get_wrapper_layers(::Val{keyword}) -> Tuple of Pair{Symbol,Int}

The layers that the wrapper of `keyword` acts in, each with a number that orders
it among the wrappers of its layer, as `(:document => 70,)`. A method of this
seam is what makes `keyword` a wrapper of [`build_editor`](@ref).
"""
function get_wrapper_layers end

"""
    get_excluded_wrappers(::Val{keyword}) -> Tuple of Symbol

The keywords that can not be on together with `keyword`. None by default.
"""
get_excluded_wrappers(::Val) = ()

"""
    is_wrapper_default(::Val{keyword}) -> Bool

Whether the wrapper of `keyword` is on when the caller of
[`build_editor`](@ref) does not name it. A caller turns it off with
`keyword = false`. Off by default.
"""
is_wrapper_default(::Val) = false

"""
    make_wrapper_setting(::Val{keyword}, setting) -> setting

The value of the setting of the wrapper `keyword`, made before anything of the
editor is built: by default `setting` as it is. The package that declares a
wrapper can answer another value, such as a new object for `true`, so the
projection that [`build_editor`](@ref) makes and the wrapper share that object.
The kernel passes the value on and never reads it.
"""
make_wrapper_setting(::Val, setting) = setting

"""
    make_document_projection(document; settings...) -> Projection

The projection of an editor on `document` when the caller names none.
`settings` are the settings of the wrappers that are on, each by its keyword,
as [`make_wrapper_setting`](@ref) made them, so the projection can share an
object with a wrapper. The kernel declares the function with no method; a
package that can draw any document adds the one method, which takes every
keyword.
"""
function make_document_projection end

"""
    build_editor(document, projection; backend = nothing, devices, feeds,
                 fault_policy, wrappers...) -> Editor
    build_editor(document; ...) -> Editor

Make an editor on `document` with its wrappers:

1. With no `backend`, choose it with [`make_default_backend`](@ref).
2. Collect the wrappers that are on: each keyword whose value is not `false` or
   `nothing`, and each wrapper that is on by default unless its keyword is
   `false`. A keyword that no loaded package declares is an error when it is on,
   and is ignored when it is off. Two wrappers that exclude each other are an
   error. Each setting is made with [`make_wrapper_setting`](@ref).
3. Apply them with [`wrap_editor!`](@ref), layer by layer from the inside out,
   and in the order of their numbers inside a layer.
4. Make the editor with [`make_editor`](@ref), and run the start steps of the
   wrappers.

With no `projection`, the projection is
[`make_document_projection`](@ref)`(document; settings...)`, with the settings of
the wrappers made first, and the wrappers get the same settings.
"""
function build_editor(document::Document, projection;
                      backend::Union{Backend,Nothing} = nothing,
                      devices::Vector{Device} = _make_default_devices(),
                      feeds::Vector{Feed} = Feed[],
                      fault_policy::FaultPolicy = FaultPolicy(),
                      wrappers...)
    backend === nothing && (backend = make_default_backend(:windows))
    settings = _make_wrapper_settings(_collect_wrapper_settings(wrappers))
    _check_excluded_wrappers(settings)
    parts = EditorParts(document, projection, backend, copy(feeds), Any[], Pair{Type,Any}[],
                        settings)
    for (keyword, layer) in _order_wrapper_steps(settings)
        wrap_editor!(Val(keyword), layer, settings[keyword], parts)
    end
    editor = make_editor(parts.document, parts.projection; backend = parts.backend,
                         devices = devices, feeds = parts.feeds,
                         fault_policy = fault_policy)
    for step in parts.start_steps
        step(editor)
    end
    editor
end

function build_editor(document::Document; keywords...)
    hasmethod(make_document_projection, Tuple{typeof(document)}) ||
        error("No projection is given for a document of type $(typeof(document)), and no ",
              "loaded package makes one. Pass a projection, or load a package that adds a ",
              "method of `make_document_projection`, such as ProjecturedPlatform.")
    wrappers = Dict{Symbol,Any}(k => v for (k, v) in keywords if !(k in _BUILD_KEYWORDS))
    settings = _make_wrapper_settings(_collect_wrapper_settings(wrappers))
    projection = make_document_projection(document; settings...)
    build_editor(document, projection; keywords..., settings...)
end

# The keywords of `build_editor` that name no wrapper.
const _BUILD_KEYWORDS = (:backend, :devices, :feeds, :fault_policy)

# Each setting as the package of its wrapper makes it.
_make_wrapper_settings(settings::Dict{Symbol,Any}) =
    Dict{Symbol,Any}(keyword => make_wrapper_setting(Val(keyword), setting)
                     for (keyword, setting) in settings)

# Whether a loaded package declares the wrapper `keyword`.
_is_wrapper(keyword::Symbol) = hasmethod(get_wrapper_layers, Tuple{Val{keyword}})

# The keywords of the method table of `seam`, one for each method for a
# `Val{keyword}` of one keyword.
function _collect_wrapper_keywords(seam)
    keywords = Symbol[]
    for method in methods(seam)
        signature = Base.unwrap_unionall(method.sig)
        length(signature.parameters) >= 2 || continue
        argument = signature.parameters[2]
        (argument isa DataType && argument <: Val && length(argument.parameters) == 1) ||
            continue
        keyword = argument.parameters[1]
        keyword isa Symbol && push!(keywords, keyword)
    end
    sort!(unique!(keywords))
end

# The setting of each wrapper that is on, by its keyword.
function _collect_wrapper_settings(wrappers)
    settings = Dict{Symbol,Any}()
    for (keyword, setting) in wrappers
        (setting === false || setting === nothing) && continue
        _is_wrapper(keyword) ||
            error("No loaded package declares the wrapper `$(keyword)`. The loaded wrappers: ",
                  join(_collect_wrapper_keywords(get_wrapper_layers), ", "), ".")
        settings[keyword] = setting
    end
    for keyword in _collect_wrapper_keywords(is_wrapper_default)
        haskey(wrappers, keyword) && continue
        is_wrapper_default(Val(keyword)) && (settings[keyword] = true)
    end
    settings
end

function _check_excluded_wrappers(settings::Dict{Symbol,Any})
    for keyword in sort!(collect(keys(settings)))
        for excluded in get_excluded_wrappers(Val(keyword))
            haskey(settings, excluded) &&
                error("The wrappers `$(keyword)` and `$(excluded)` can not be on together.")
        end
    end
end

# Each step `(keyword, layer)` of the wrappers that are on, from the inside out.
function _order_wrapper_steps(settings::Dict{Symbol,Any})
    steps = Tuple{Int,Int,Symbol,Symbol}[]
    for keyword in keys(settings)
        for (layer, order) in get_wrapper_layers(Val(keyword))
            position = findfirst(==(layer), EDITOR_WRAPPER_LAYERS)
            position === nothing &&
                error("The wrapper `$(keyword)` names the layer `$(layer)`, which is not one of ",
                      join(EDITOR_WRAPPER_LAYERS, ", "), ".")
            push!(steps, (position, order, keyword, layer))
        end
    end
    sort!(steps)
    [(keyword, layer) for (_, _, keyword, layer) in steps]
end
