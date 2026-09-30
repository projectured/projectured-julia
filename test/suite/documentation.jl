# ============================================================================
# The documentation guard — the part of `documentation/rule/writing-rules.md`
# that a program can check.
#
# **Static, and deliberately.** It reads Markdown files and the strings in
# `source/`. It loads no package, so it runs in under a second and it cannot be
# fooled by what happens to be in a session.
#
# **`plan/` is not checked.** A plan records what was decided and what was
# tried, it links to files that a step will write, and it keeps the names that
# a public document may not use. The guard reads the documents a reader of the
# repository reads.
# ============================================================================

# The Markdown files the guard reads: the root files and everything under these
# folders. `plan/` holds the plans, and the fixture is test data that a test
# writes and reads back.
const _DOCUMENT_FOLDERS = ("documentation", "test", "tool", "example", "asset",
                           "source", "package", "bin")
const _SKIPPED_FOLDERS = (joinpath("example", "platform", "filesystem", "fixture"), "build", ".git")

"""
    collect_documents(root) -> Vector{String}

Every Markdown file the guard reads, as a path relative to `root`.
"""
function collect_documents(root::AbstractString)
    found = String[]
    for name in sort(readdir(root))
        endswith(name, ".md") && isfile(joinpath(root, name)) && push!(found, name)
    end
    for folder in _DOCUMENT_FOLDERS
        directory = joinpath(root, folder)
        isdir(directory) || continue
        for (here, _dirs, files) in walkdir(directory), file in sort(files)
            endswith(file, ".md") || continue
            path = relpath(joinpath(here, file), root)
            any(skipped -> startswith(path, skipped), _SKIPPED_FOLDERS) && continue
            push!(found, path)
        end
    end
    found
end

# A heading of a Markdown file, as GitHub names its anchor: lower case, the
# spaces are hyphens, and only a letter, a digit, a hyphen or an underscore
# stays.
function _heading_anchors(text::AbstractString)
    anchors = Set{String}()
    in_code = false
    for line in split(text, '\n')
        startswith(line, "```") && (in_code = !in_code; continue)
        in_code && continue
        m = match(r"^#{1,6}\s+(.*?)\s*$", line)
        m === nothing && continue
        title = replace(m.captures[1], r"`|\*|\[|\]\([^)]*\)" => "")
        anchor = lowercase(strip(title))
        anchor = replace(anchor, r"[^\w\s-]" => "")
        push!(anchors, replace(strip(anchor), r"\s+" => "-"))
    end
    anchors
end

# Every `[text](target)` of a Markdown file, with the line it is on. A target
# that names a place outside this repository is left out.
function _links(text::AbstractString)
    found = Tuple{Int,String}[]
    for (number, line) in enumerate(split(text, '\n'))
        for m in eachmatch(r"\[[^\]]*\]\(([^)\s]+)\)", line)
            target = m.captures[1]
            startswith(target, "http") && continue
            startswith(target, "mailto:") && continue
            push!(found, (number, target))
        end
    end
    found
end

"""
    link_violations(root) -> Vector{String}

Every relative link whose file is not there, and every link to a heading that
the target file does not have.
"""
function link_violations(root::AbstractString)
    out = String[]
    texts = Dict{String,String}()
    read_text(path) = get!(() -> read(path, String), texts, path)
    for document in collect_documents(root)
        path = joinpath(root, document)
        text = read_text(path)
        for (number, target) in _links(text)
            file, anchor = occursin('#', target) ?
                (split(target, '#'; limit = 2)...,) : (target, "")
            full = isempty(file) ? path : normpath(joinpath(dirname(path), file))
            if !isempty(file) && !ispath(full)
                push!(out, "$document:$number links to $target, which is not there")
                continue
            end
            (isempty(anchor) || isdir(full)) && continue
            endswith(full, ".md") || continue
            anchor in _heading_anchors(read_text(full)) ||
                push!(out, "$document:$number links to the heading $target, " *
                           "which the file does not have")
        end
    end
    out
end

"""
    guide_name_violations(root) -> Vector{String}

Every `resource://guide/<name>` that names no guide. The name of a guide comes
from its path, as `_all_guides()` in `source/kernel/tool/Documentation.jl`
derives it: `documentation/guide/x.md` is `guide/x`,
`documentation/package/<group>/<slice>/x.md` is `<group>/<slice>/x`, and
`documentation/package/x.md` is `package/x`.

**A guide name is part of the interface of the assistant.** A model asks for a
guide by that name, and a name that resolves to nothing costs it a turn.
"""
function guide_name_violations(root::AbstractString)
    guides = Set{String}()
    for (here, _dirs, files) in walkdir(joinpath(root, "documentation")), file in files
        endswith(file, ".md") || continue
        path = relpath(joinpath(here, file), joinpath(root, "documentation"))
        parts = splitpath(path)
        name = splitext(path)[1]
        if length(parts) > 2 && parts[1] == "package"
            name = join(vcat(parts[2:end-1], splitext(parts[end])[1]), "/")
        elseif length(parts) > 1
            name = join(vcat(parts[1:end-1], splitext(parts[end])[1]), "/")
        else
            name = splitext(parts[end])[1]
        end
        push!(guides, name)
    end
    out = String[]
    for area in ("source", "documentation"), (here, _dirs, files) in walkdir(joinpath(root, area))
        for file in files
            (endswith(file, ".jl") || endswith(file, ".md")) || continue
            path = joinpath(here, file)
            for (number, line) in enumerate(split(read(path, String), '\n'))
                for m in eachmatch(r"resource://guide/([\w/\-.]+)", line)
                    m.captures[1] in guides ||
                        push!(out, "$(relpath(path, root)):$number names the guide " *
                                   "$(m.captures[1]), which is not there")
                end
            end
        end
    end
    out
end

# The kinds that `documentation/README.md` defines. The last three are the kinds
# of folders that hold no document yet.
const _HEADER_KINDS = ["why", "what", "decision", "rule", "design", "reference",
                       "procedure", "evidence", "study", "history"]

"""
    header_violations(root) -> Vector{String}

Every document under `documentation/` without the header line, every one whose
header names a kind outside `_HEADER_KINDS`, and every one whose header is not
followed by a paragraph. A slide deck is left out: Marp reads its own front
matter and the first slide is its title.
"""
function header_violations(root::AbstractString)
    out = String[]
    for document in collect_documents(root)
        startswith(document, "documentation") || continue
        text = read(joinpath(root, document), String)
        startswith(text, "---\n") && occursin(r"(?m)^marp:\s*true", text) && continue
        lines = split(text, '\n')
        header = findfirst(line -> startswith(line, "> **Kind:**"), lines)
        if header === nothing
            push!(out, "$document has no `> **Kind:** … **Status:** … **Stands on:** …` line")
            continue
        end
        occursin("**Status:**", lines[header]) ||
            push!(out, "$document has a header line without a Status")
        kind = match(r"^> \*\*Kind:\*\* ([a-z]+)", lines[header])
        (kind !== nothing && kind.captures[1] in _HEADER_KINDS) ||
            push!(out, "$document has a header line whose Kind is not one of " *
                       join(_HEADER_KINDS, ", "))
        summary = findfirst(number -> number > header && !isempty(strip(lines[number])),
                            eachindex(lines))
        if summary === nothing || startswith(strip(lines[summary]), "#") ||
           startswith(strip(lines[summary]), ">")
            push!(out, "$document has no summary paragraph after its header line")
        end
    end
    out
end

# What `writing-rules.md` forbids, and the document itself is where they are
# written down, so it is the one file that may hold them.
const _BANNED_PHRASES = ["seamless", "powerful", "robust", "elegant",
                         "first-class", "out of the box", "batteries included",
                         "under the hood", "not bolted on", "literally",
                         "value proposition", "customers"]
const _PHRASE_EXCEPTIONS = (joinpath("documentation", "rule", "writing-rules.md"),)

"""
    phrase_violations(root) -> Vector{String}

Every phrase of the list in `writing-rules.md` that a document uses. The rule
document itself is where the list is written down, so it is left out.
"""
function phrase_violations(root::AbstractString)
    out = String[]
    for document in collect_documents(root)
        document in _PHRASE_EXCEPTIONS && continue
        for (number, line) in enumerate(split(read(joinpath(root, document), String), '\n'))
            lowered = lowercase(line)
            for phrase in _BANNED_PHRASES
                occursin(phrase, lowered) &&
                    push!(out, "$document:$number uses \"$phrase\"")
            end
        end
    end
    out
end

# The names a public document must not carry: the repositories, the products and
# the company of the work that is not published. A plan, a commit message, a
# test and an example may name them, and the guard reads none of those. They are
# written as patterns rather than as names, because this file is public too.
const _PRIVATE_NAME_PATTERNS = [r"omne\w*"i, r"\binet\w*"i, r"qtenv"i]

"""
    private_name_violations(root) -> Vector{String}

Every private name that a document carries. A document of this repository names
the work it stands on by what it is — "the C++ original", "a downstream
program" — and never by the name of a product that is not published here.
"""
function private_name_violations(root::AbstractString)
    out = String[]
    for document in collect_documents(root)
        for (number, line) in enumerate(split(read(joinpath(root, document), String), '\n'))
            for pattern in _PRIVATE_NAME_PATTERNS
                m = match(pattern, line)
                m === nothing && continue
                push!(out, "$document:$number names $(m.match), which is private; " *
                           "write what the thing is instead")
            end
        end
    end
    out
end

# A path that no longer exists, in any shape a document writes it.
const _DEAD_PATHS = [r"package/[a-z]+/main\b" => "source/<group>/<slice>/",
                     r"(?<![\w/])visual/" => "the real folder under source/",
                     r"package/[a-z]+/doc\b" => "documentation/package/<group>/<slice>/"]

"""
    dead_path_violations(root) -> Vector{String}

Every path of the tree before the move that a document still names.
"""
function dead_path_violations(root::AbstractString)
    out = String[]
    for document in collect_documents(root)
        for (number, line) in enumerate(split(read(joinpath(root, document), String), '\n'))
            for (pattern, instead) in _DEAD_PATHS
                m = match(pattern, line)
                m === nothing && continue
                push!(out, "$document:$number names $(m.match), which is not there; " *
                           "write $instead")
            end
        end
    end
    out
end

"""
    documentation_violations(root) -> Vector{String}

Every rule of `documentation/rule/writing-rules.md` that a program can check,
as lines a reader can act on.
"""
documentation_violations(root::AbstractString) =
    vcat(link_violations(root), guide_name_violations(root), header_violations(root),
         phrase_violations(root), dead_path_violations(root),
         private_name_violations(root))

# The verbs that make an object act like a person. A sentence that uses one is
# not always wrong, so this is a report and not a rule.
const _PERSON_VERBS = ["knows", "wants", "asks for", "decides", "refuses",
                       "offers", "promises", "tells", "believes", "thinks"]

"""
    documentation_report(root) -> Vector{String}

What a person must read and judge: the sentences that give a verb of a person
to an object, and the slices under `source/` that no guide names.
"""
function documentation_report(root::AbstractString)
    out = String[]
    for document in collect_documents(root)
        startswith(document, "documentation") || continue
        for (number, line) in enumerate(split(read(joinpath(root, document), String), '\n'))
            lowered = lowercase(line)
            for verb in _PERSON_VERBS
                occursin(" " * verb * " ", lowered) &&
                    push!(out, "$document:$number: \"$verb\" — read the sentence")
            end
        end
    end
    named = join([read(joinpath(root, document), String)
                  for document in collect_documents(root)
                  if startswith(document, "documentation")], "\n")
    for slice in sort(readdir(joinpath(root, "source")))
        isdir(joinpath(root, "source", slice)) || continue
        occursin("source/" * slice, named) || occursin("`" * slice * "`", named) ||
            push!(out, "no guide under documentation/ names the slice source/$slice")
    end
    out
end

# Runnable on its own. It needs no environment and no dependency:
#
#     julia test/suite/documentation.jl
#
if abspath(PROGRAM_FILE) == @__FILE__
    root = normpath(joinpath(@__DIR__, "..", ".."))
    bad = documentation_violations(root)
    report = documentation_report(root)
    if isempty(bad)
        println("every document keeps the rules a program can check")
    else
        println("$(length(bad)) violation(s) of the writing rules:")
        foreach(violation -> println("  ", violation), bad)
    end
    println("\n$(length(report)) line(s) for a person to read:")
    foreach(line -> println("  ", line), report)
    exit(isempty(bad) ? 0 : 1)
end
