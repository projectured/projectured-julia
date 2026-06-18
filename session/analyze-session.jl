#!/usr/bin/env julia
#
# Session analysis script for Claude Code JSONL logs.
#
# Usage:
#   julia --project=program session/analyze-session.jl --latest
#   julia --project=program session/analyze-session.jl --latest 2
#   julia --project=program session/analyze-session.jl path/to/session.jsonl [path2.jsonl ...]
#   julia --project=program session/analyze-session.jl --name control path1.jsonl --name concepts path2.jsonl
#
# Output: session/report-{timestamp}.md

using JSON3, Printf, Dates

const PROJECT_SLUG = "c--Users-balin-gitworkspace-projectured-julia"
const SESSIONS_DIR = joinpath(homedir(), ".claude", "projects", PROJECT_SLUG)
const OUTPUT_DIR = joinpath(@__DIR__)

mutable struct SessionMetrics
    label::String
    filename::String
    workspace::String
    git_branch::String
    total_input::Int
    total_output::Int
    cache_creation::Int
    cache_read::Int
    discovery_cost::Int
    first_code_offset::Int
    turn_count::Int
    files_read::Dict{String,Int}        # normalized path => read count
    files_edited::Dict{String,Int}      # normalized path => edit count
    tool_counts::Dict{String,Int}       # tool name => count
    malformed::Int
end

SessionMetrics(label, filename) = SessionMetrics(
    label, filename, "", "", 0, 0, 0, 0, 0, -1, 0,
    Dict{String,Int}(), Dict{String,Int}(), Dict{String,Int}(), 0
)

function norm_path(p::AbstractString)
    lowercase(replace(normpath(String(p)), '\\' => '/'))
end

function find_session_title(filepath::String)
    for line in eachline(filepath)
        obj = try JSON3.read(line) catch; continue end
        if string(get(obj, :type, "")) == "ai-title"
            title = get(obj, :aiTitle, nothing)
            title !== nothing && return String(title)
        end
    end
    return ""
end

function parse_session(filepath::String; label::String="")
    auto_title = isempty(label) ? find_session_title(filepath) : ""
    name = !isempty(label) ? label : !isempty(auto_title) ? auto_title : basename(filepath)
    m = SessionMetrics(name, basename(filepath))
    cumulative = 0
    seen_first_edit = false

    for line in eachline(filepath)
        isempty(strip(line)) && continue
        local obj
        try
            obj = JSON3.read(line)
        catch
            m.malformed += 1
            continue
        end

        string(get(obj, :type, "")) == "assistant" || continue
        msg = get(obj, :message, nothing)
        msg === nothing && continue

        if isempty(m.workspace)
            cwd = get(obj, :cwd, nothing)
            cwd !== nothing && (m.workspace = String(cwd))
        end
        if isempty(m.git_branch)
            branch = get(obj, :gitBranch, nothing)
            branch !== nothing && (m.git_branch = String(branch))
        end

        usage = get(msg, :usage, nothing)
        if usage !== nothing
            inp = get(usage, :input_tokens, 0)
            outp = get(usage, :output_tokens, 0)
            m.total_input += inp
            m.total_output += outp
            m.cache_creation += get(usage, :cache_creation_input_tokens, 0)
            m.cache_read += get(usage, :cache_read_input_tokens, 0)
            cumulative += inp + outp

            if !seen_first_edit
                m.discovery_cost = cumulative
            end
        end

        m.turn_count += 1

        content = get(msg, :content, nothing)
        content === nothing && continue

        for block in content
            get(block, :type, nothing) == "tool_use" || continue
            name = String(get(block, :name, "unknown"))
            m.tool_counts[name] = get(m.tool_counts, name, 0) + 1

            input = get(block, :input, nothing)
            input === nothing && continue

            if name == "Read"
                fp = get(input, :file_path, nothing)
                fp !== nothing || continue
                np = norm_path(fp)
                m.files_read[np] = get(m.files_read, np, 0) + 1
            elseif name in ("Edit", "Write")
                fp = get(input, :file_path, nothing)
                fp !== nothing || continue
                np = norm_path(fp)
                m.files_edited[np] = get(m.files_edited, np, 0) + 1
                if !seen_first_edit
                    seen_first_edit = true
                    m.first_code_offset = cumulative
                end
            end
        end
    end

    if !seen_first_edit
        m.discovery_cost = cumulative
        m.first_code_offset = cumulative
    end

    m
end

function pct(part, total)
    total == 0 ? "—" : @sprintf("%.1f%%", 100.0 * part / total)
end

function fmt(n::Int)
    s = string(n)
    parts = String[]
    while length(s) > 3
        push!(parts, s[end-2:end])
        s = s[1:end-3]
    end
    push!(parts, s)
    join(reverse(parts), ",")
end

function short_path(p::AbstractString)
    idx = findfirst("projectured-julia/", p)
    idx !== nothing ? p[first(idx)+length("projectured-julia/"):end] : p
end

function write_session_section(io, m::SessionMetrics)
    total = m.total_input + m.total_output
    read_count = length(m.files_read)
    edit_count = length(m.files_edited)
    irrelevant = setdiff(keys(m.files_read), keys(m.files_edited))
    multi_edited = count(v -> v > 1, values(m.files_edited))

    println(io, "## Session: $(m.label)\n")
    details = String[]
    m.label != m.filename && push!(details, "Source: `$(m.filename)`")
    !isempty(m.workspace) && push!(details, "Workspace: `$(m.workspace)`")
    !isempty(m.git_branch) && push!(details, "Branch: `$(m.git_branch)`")
    if !isempty(details)
        println(io, join(details, " | "), "\n")
    end

    effective_input = m.total_input + m.cache_creation + m.cache_read
    effective_total = effective_input + m.total_output

    println(io, "### Token Usage\n")
    println(io, "| Metric | Value | Notes |")
    println(io, "|---|---:|---|")
    println(io, "| **Effective total** | **$(fmt(effective_total))** | input (all sources) + output |")
    println(io, "| Effective input | $(fmt(effective_input)) | fresh + cache creation + cache read |")
    println(io, "| Output | $(fmt(m.total_output)) | |")
    println(io, "| Fresh input | $(fmt(m.total_input)) | non-cached input tokens |")
    println(io, "| Cache creation | $(fmt(m.cache_creation)) | new cache entries |")
    println(io, "| Cache read | $(fmt(m.cache_read)) | reused from cache |")
    println(io, "| Cache hit rate | $(pct(m.cache_read, effective_input)) | cache read / effective input |")
    println(io, "| Discovery cost | $(fmt(m.discovery_cost)) | output tokens before first Edit/Write |")
    println(io)

    println(io, "### Activity\n")
    println(io, "| Metric | Count |")
    println(io, "|---|---:|")
    println(io, "| Assistant turns | $(m.turn_count) |")
    println(io, "| Files read | $read_count |")
    println(io, "| Files edited | $edit_count |")
    println(io, "| Irrelevant reads ≈ | $(length(irrelevant)) |")
    println(io, "| Multi-edited ≈ | $multi_edited |")
    if m.first_code_offset >= 0
        println(io, "| First code at token | $(fmt(m.first_code_offset)) |")
    end
    println(io)

    println(io, "### Tool Calls\n")
    println(io, "| Tool | Count |")
    println(io, "|---|---:|")
    for name in sort(collect(keys(m.tool_counts)))
        println(io, "| $name | $(m.tool_counts[name]) |")
    end
    println(io)

    println(io, "### Files Read\n")
    read_paths = sort(collect(keys(m.files_read)))
    println(io, "<details><summary>$(length(read_paths)) files</summary>\n")
    for p in read_paths
        cnt = m.files_read[p]
        suffix = cnt > 1 ? " (×$cnt)" : ""
        println(io, "- $(short_path(p))$suffix")
    end
    println(io, "\n</details>\n")

    println(io, "### Files Edited\n")
    edit_paths = sort(collect(keys(m.files_edited)))
    println(io, "<details><summary>$(length(edit_paths)) files</summary>\n")
    for p in edit_paths
        cnt = m.files_edited[p]
        suffix = cnt > 1 ? " (×$cnt)" : ""
        println(io, "- $(short_path(p))$suffix")
    end
    println(io, "\n</details>\n")

    if !isempty(irrelevant)
        println(io, "### Irrelevant Reads (approx)\n")
        println(io, "<details><summary>$(length(irrelevant)) files read but never edited</summary>\n")
        for p in sort(collect(irrelevant))
            println(io, "- $(short_path(p))")
        end
        println(io, "\n</details>\n")
    end

    if m.malformed > 0
        println(io, "> ⚠ $(m.malformed) malformed JSONL lines skipped\n")
    end
end

function write_comparison(io, sessions::Vector{SessionMetrics})
    length(sessions) < 2 && return

    println(io, "## Comparison\n")

    names = [s.label for s in sessions]
    header = "| Metric | " * join(names, " | ") * " |"
    sep = "|---|" * join(fill("---:|", length(sessions))) * ""

    println(io, header)
    println(io, sep)

    rows = [
        ("Effective total", [fmt(s.total_input + s.cache_creation + s.cache_read + s.total_output) for s in sessions]),
        ("Effective input", [fmt(s.total_input + s.cache_creation + s.cache_read) for s in sessions]),
        ("Output tokens", [fmt(s.total_output) for s in sessions]),
        ("Fresh input", [fmt(s.total_input) for s in sessions]),
        ("Cache creation", [fmt(s.cache_creation) for s in sessions]),
        ("Cache read", [fmt(s.cache_read) for s in sessions]),
        ("Discovery cost", [fmt(s.discovery_cost) for s in sessions]),
        ("First code at token", [fmt(s.first_code_offset) for s in sessions]),
        ("Assistant turns", [string(s.turn_count) for s in sessions]),
        ("Files read", [string(length(s.files_read)) for s in sessions]),
        ("Files edited", [string(length(s.files_edited)) for s in sessions]),
        ("Irrelevant reads ≈", [string(length(setdiff(keys(s.files_read), keys(s.files_edited)))) for s in sessions]),
        ("Multi-edited ≈", [string(count(v -> v > 1, values(s.files_edited))) for s in sessions]),
    ]

    for (label, vals) in rows
        println(io, "| $label | " * join(vals, " | ") * " |")
    end
    println(io)
end

function resolve_latest(n::Int)
    isdir(SESSIONS_DIR) || error("Sessions directory not found: $SESSIONS_DIR")
    files = filter(f -> endswith(f, ".jsonl"), readdir(SESSIONS_DIR; join=true))
    isempty(files) && error("No JSONL files found in $SESSIONS_DIR")
    sort!(files; by=mtime, rev=true)
    n = min(n, length(files))

    result = files[1:n]

    age_seconds = time() - mtime(result[1])
    if age_seconds < 60
        @warn "Most recent session was modified $(round(Int, age_seconds))s ago — likely still active. Results may be partial."
    end

    result
end

function main()
    args = copy(ARGS)
    entries = Tuple{String,String}[]  # (label, path)

    i = 1
    while i <= length(args)
        if args[i] == "--latest"
            n = 1
            if i + 1 <= length(args) && all(isdigit, args[i+1])
                n = parse(Int, args[i+1])
                i += 1
            end
            for p in resolve_latest(n)
                push!(entries, ("", p))
            end
        elseif args[i] == "--name"
            i + 2 <= length(args) || error("--name requires a label and a file path")
            push!(entries, (args[i+1], args[i+2]))
            i += 2
        else
            push!(entries, ("", args[i]))
        end
        i += 1
    end

    if isempty(entries)
        println(stderr, """
        Usage:
          julia --project=program session/analyze-session.jl --latest
          julia --project=program session/analyze-session.jl --latest 2
          julia --project=program session/analyze-session.jl path/to/session.jsonl [...]
          julia --project=program session/analyze-session.jl --name control path1.jsonl --name concepts path2.jsonl
        """)
        exit(1)
    end

    for (_, p) in entries
        isfile(p) || error("File not found: $p")
    end

    sessions = SessionMetrics[]
    for (label, p) in entries
        println(stderr, "Parsing $(basename(p))$(isempty(label) ? "" : " as \"$label\"")...")
        push!(sessions, parse_session(p; label))
    end

    timestamp = Dates.format(now(), "yyyymmdd-HHMMSS")
    outpath = joinpath(OUTPUT_DIR, "report-$timestamp.md")

    open(outpath, "w") do io
        println(io, "# Session Analysis Report\n")
        println(io, "**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM"))")
        println(io, "**Sessions:** $(length(sessions))")
        println(io, "**Input files:**")
        for (label, p) in entries
            prefix = isempty(label) ? "" : "**$label:** "
            println(io, "- $(prefix)`$(basename(p))`")
        end
        println(io, "\n---\n")

        for m in sessions
            write_session_section(io, m)
            println(io, "---\n")
        end

        write_comparison(io, sessions)
    end

    println(stderr, "Report written to $outpath")
    println(outpath)
end

main()
