#!/usr/bin/env julia
#
# Session analysis script for Claude Code JSONL logs.
#
# Usage:
#   julia --project=program session/analyze-session.jl --latest
#   julia --project=program session/analyze-session.jl --latest 2
#   julia --project=program session/analyze-session.jl path/to/session.jsonl [path2.jsonl ...]
#   julia --project=program session/analyze-session.jl --name control path1.jsonl --name concepts path2.jsonl
#   julia --project=program session/analyze-session.jl --history
#   julia --project=program session/analyze-session.jl --history --subscription 100
#
# --subscription <amount>: monthly subscription fee ($/mo, default 20) used to
#   amortize costs; the plan tier is not recorded in the logs, so it is supplied
#   here. Costs are subscription-amortized, not API list price (see COST_WEIGHT).
#
# Output: session/{inv-key}-{last-alive}-{title}.md   (--latest / explicit files)
#         session/history/{group}/{inv-key}-{last-alive}-{title}.md + comparison   (--history)
#         (inv-key sorts newest-first; the comparison file is pinned to the folder top)

using JSON3, Printf, Dates

const PROJECTS_ROOT = joinpath(homedir(), ".claude", "projects")
const OUTPUT_DIR = joinpath(@__DIR__)
const HISTORY_DIR = joinpath(@__DIR__, "history")

# Inverse-timestamp reference: filenames are prefixed with (REF - mtime) so that
# newer sessions get a *smaller* key and sort first under ascending name order.
const SORT_REF = 9_999_999_999
inv_key(mt::Real) = @sprintf("%010d", SORT_REF - floor(Int, mt))
# Pinned to the top of each folder (all-zero key sorts before any session key).
const COMPARISON_NAME = "0000000000-history-comparison.md"

const COST_INPUT   = 5.00   # $/MTok fresh input (Opus 4.6/4.7/4.8)
const COST_OUTPUT  = 25.00  # $/MTok output
const COST_CACHE_W = 6.25   # $/MTok cache creation (1.25× input)
const COST_CACHE_R = 0.50   # $/MTok cache read (0.1× input)

# Subscription-amortized cost weighting.
#
# The rates above are pay-as-you-go API list prices; on a flat monthly
# subscription they wildly overstate what work actually costs. Usage resets
# every ~6 h (sub-buckets) and weekly (the binding quota), billed monthly; a
# 30-day month holds 30/7 ≈ 4.286 weekly windows. Assuming the weekly quota is
# fully used, the real cost of a week's work is just the weekly share of the fee.
#
#   weekly_budget = SUBSCRIPTION_MONTHLY * 7/30        # weekly share of the fee
#   L_week_full   = busiest rolling 7-day list cost    # ≈ one fully-used quota
#   COST_WEIGHT   = weekly_budget / L_week_full        # ≪ 1 in practice
#
# L_week_full is data-calibrated (cached, raw list dollars) and decoupled from
# the fee, so --subscription can vary per run without recomputing the sweep.
const WEEKS_PER_MONTH      = 30 / 7
const DEFAULT_SUBSCRIPTION = 20.00                          # $/mo; override --subscription
const WEIGHT_CACHE = joinpath(HISTORY_DIR, ".cost-weight")  # raw busiest-week list $
const COST_WEIGHT  = Ref(1.0)                              # global multiplier, set at runtime

# Max summed list cost over any rolling 7-day window. timed = (mtime, list_cost),
# computed while COST_WEIGHT[] == 1.0 (raw list prices).
function busiest_week_cost(timed::Vector{Tuple{Float64,Float64}})
    isempty(timed) && return 0.0
    sort!(timed; by = first)
    win = 7 * 24 * 3600.0
    best = 0.0
    for i in eachindex(timed)
        t0 = timed[i][1]
        s = 0.0
        for j in i:length(timed)
            timed[j][1] - t0 <= win || break
            s += timed[j][2]
        end
        best = max(best, s)
    end
    best
end

set_cost_weight!(sub::Real, l_week_full::Real) =
    (COST_WEIGHT[] = l_week_full > 0 ? (sub * 7 / 30) / l_week_full : 1.0)

# Claude Code encodes a workspace path into its projects-folder name by
# replacing every non-alphanumeric character with '-'.
slugify_path(p::AbstractString) = replace(abspath(String(p)), r"[^A-Za-z0-9]" => "-")

function current_sessions_dir()
    dir = joinpath(PROJECTS_ROOT, slugify_path(pwd()))
    if !isdir(dir)
        available = isdir(PROJECTS_ROOT) ?
            join(["  " * d for d in readdir(PROJECTS_ROOT)], "\n") : "  (none)"
        error("No Claude sessions folder for the current directory.\n" *
              "Expected: $dir\nAvailable projects under $PROJECTS_ROOT:\n$available")
    end
    dir
end

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
    files_read_chars::Dict{String,Int}  # normalized path => total chars from tool_results
    files_edited_chars::Dict{String,Int}
    tool_counts::Dict{String,Int}       # tool name => count
    tool_input::Dict{String,Int}        # tool name => sum of effective input across turns
    tool_output::Dict{String,Int}       # tool name => sum of output across turns
    malformed::Int
end

SessionMetrics(label, filename) = SessionMetrics(
    label, filename, "", "", 0, 0, 0, 0, 0, -1, 0,
    Dict{String,Int}(), Dict{String,Int}(),
    Dict{String,Int}(), Dict{String,Int}(),
    Dict{String,Int}(), Dict{String,Int}(), Dict{String,Int}(), 0
)

function norm_path(p::AbstractString)
    lowercase(replace(normpath(String(p)), '\\' => '/'))
end

function find_session_title(filepath::String)
    # A session can carry several ai-title records as the title is refined;
    # the last one is the current title.
    latest = ""
    for line in eachline(filepath)
        obj = try JSON3.read(line) catch; continue end
        if string(get(obj, :type, "")) == "ai-title"
            title = get(obj, :aiTitle, nothing)
            title !== nothing && (latest = String(title))
        end
    end
    return latest
end

function parse_session(filepath::String; label::String="")
    auto_title = isempty(label) ? find_session_title(filepath) : ""
    name = !isempty(label) ? label : !isempty(auto_title) ? auto_title : basename(filepath)
    m = SessionMetrics(name, basename(filepath))
    cumulative = 0
    seen_first_edit = false

    # Buffer pending tool_use calls from assistant turns: id => (normalized_path, tool_name)
    pending_tools = Dict{String,Tuple{String,String}}()
    # Per-turn token values for tool attribution
    last_turn_eff_input = 0
    last_turn_output = 0
    last_turn_tools = Set{String}()

    for line in eachline(filepath)
        isempty(strip(line)) && continue
        local obj
        try
            obj = JSON3.read(line)
        catch
            m.malformed += 1
            continue
        end

        record_type = string(get(obj, :type, ""))

        if record_type == "user"
            # Resolve pending tool_use calls via tool_result blocks
            msg = get(obj, :message, nothing)
            msg === nothing && continue
            content = get(msg, :content, nothing)
            content === nothing && continue
            content isa AbstractString && continue
            for block in content
                block isa AbstractString && continue
                string(get(block, :type, "")) == "tool_result" || continue
                tool_use_id = string(get(block, :tool_use_id, ""))
                isempty(tool_use_id) && continue
                haskey(pending_tools, tool_use_id) || continue
                np, tname = pending_tools[tool_use_id]
                result_content = get(block, :content, nothing)
                result_content === nothing && continue
                chars = if result_content isa AbstractString
                    length(result_content)
                elseif result_content isa AbstractVector
                    sum(length(string(get(sub, :text, ""))) for sub in result_content; init=0)
                else
                    0
                end
                if tname == "Read"
                    m.files_read_chars[np] = get(m.files_read_chars, np, 0) + chars
                elseif tname in ("Edit", "Write")
                    m.files_edited_chars[np] = get(m.files_edited_chars, np, 0) + chars
                end
            end
            continue
        end

        record_type == "assistant" || continue
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

        # Reset per-turn tracking
        empty!(pending_tools)
        empty!(last_turn_tools)
        last_turn_eff_input = 0
        last_turn_output = 0

        usage = get(msg, :usage, nothing)
        if usage !== nothing
            inp = get(usage, :input_tokens, 0)
            outp = get(usage, :output_tokens, 0)
            cc = get(usage, :cache_creation_input_tokens, 0)
            cr = get(usage, :cache_read_input_tokens, 0)
            m.total_input += inp
            m.total_output += outp
            m.cache_creation += cc
            m.cache_read += cr
            cumulative += inp + outp

            last_turn_eff_input = inp + cc + cr
            last_turn_output = outp

            if !seen_first_edit
                m.discovery_cost = cumulative
            end
        end

        m.turn_count += 1

        content = get(msg, :content, nothing)
        content === nothing && continue

        for block in content
            get(block, :type, nothing) == "tool_use" || continue
            tname = String(get(block, :name, "unknown"))
            m.tool_counts[tname] = get(m.tool_counts, tname, 0) + 1
            push!(last_turn_tools, tname)

            input = get(block, :input, nothing)
            input === nothing && continue

            tool_id = string(get(block, :id, ""))

            if tname == "Read"
                fp = get(input, :file_path, nothing)
                fp !== nothing || continue
                np = norm_path(fp)
                m.files_read[np] = get(m.files_read, np, 0) + 1
                !isempty(tool_id) && (pending_tools[tool_id] = (np, tname))
            elseif tname in ("Edit", "Write")
                fp = get(input, :file_path, nothing)
                fp !== nothing || continue
                np = norm_path(fp)
                m.files_edited[np] = get(m.files_edited, np, 0) + 1
                !isempty(tool_id) && (pending_tools[tool_id] = (np, tname))
                if !seen_first_edit
                    seen_first_edit = true
                    m.first_code_offset = cumulative
                end
            end
        end

        # Attribute turn tokens to each tool used in this turn
        for tname in last_turn_tools
            m.tool_input[tname] = get(m.tool_input, tname, 0) + last_turn_eff_input
            m.tool_output[tname] = get(m.tool_output, tname, 0) + last_turn_output
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

function fmt_cost(dollars::Float64)
    @sprintf("\$%.2f", dollars)
end

function cost_mtok(tokens::Int, rate::Float64)
    tokens / 1_000_000 * rate * COST_WEIGHT[]
end

function est_tokens(chars::Int)
    div(chars, 4)
end

function session_cost(m::SessionMetrics)
    cost_mtok(m.total_input, COST_INPUT) +
    cost_mtok(m.total_output, COST_OUTPUT) +
    cost_mtok(m.cache_creation, COST_CACHE_W) +
    cost_mtok(m.cache_read, COST_CACHE_R)
end

function short_path(p::AbstractString)
    idx = findfirst("projectured-julia/", p)
    idx !== nothing ? p[first(idx)+length("projectured-julia/"):end] : p
end

# Build a filesystem-safe stem from a session title: keep the first 3 words
# whole, truncate each later word to 4 chars, then restrict to [A-Za-z0-9-].
function condense_title(title::AbstractString; fallback::AbstractString="")
    words = split(strip(title))
    if isempty(words)
        title = fallback
        words = split(strip(title))
    end
    parts = String[]
    for (i, w) in enumerate(words)
        push!(parts, i <= 3 ? String(w) : String(w)[1:min(end, 4)])
    end
    name = join(parts, "-")
    name = replace(name, r"[^A-Za-z0-9-]" => "-")   # only alnum and '-'
    name = replace(name, r"-+" => "-")              # collapse runs
    name = strip(name, '-')
    isempty(name) ? "session" : name
end

function write_session_section(io, m::SessionMetrics; subscription::Real=DEFAULT_SUBSCRIPTION)
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

    cost_fresh = cost_mtok(m.total_input, COST_INPUT)
    cost_output = cost_mtok(m.total_output, COST_OUTPUT)
    cost_cache_w = cost_mtok(m.cache_creation, COST_CACHE_W)
    cost_cache_r = cost_mtok(m.cache_read, COST_CACHE_R)
    total_cost = cost_fresh + cost_output + cost_cache_w + cost_cache_r
    output_cost_pct = total_cost > 0 ? 100.0 * cost_output / total_cost : 0.0

    # How the cost was calculated (single-session framing): one session can't
    # observe a full week, so the weekly total is an *estimate* (the calibrated
    # busiest-week list cost = weekly_budget / weight).
    weekly_budget = subscription * 7 / 30
    weekly_total_est = COST_WEIGHT[] > 0 ? weekly_budget / COST_WEIGHT[] : 0.0
    println(io, "> **Cost basis:** subscription-amortized, not API list price. ",
        "Subscription \$$(@sprintf("%.0f", subscription))/mo (`--subscription`, default \$$(@sprintf("%.0f", DEFAULT_SUBSCRIPTION))) ",
        "→ weekly budget $(fmt_cost(weekly_budget)) (÷ $(@sprintf("%.3f", WEEKS_PER_MONTH)) wk/mo). ",
        "Weight = weekly budget ÷ *estimated* weekly usage $(fmt_cost(weekly_total_est)) = ",
        "**×$(@sprintf("%.4f", COST_WEIGHT[]))**. Est. Cost below is this weight applied to list price.\n")

    println(io, "### Token Usage\n")
    println(io, "| Metric | Value | \$/MTok | Rel. Weight | Est. Cost | Notes |")
    println(io, "|---|---:|---:|---:|---:|---|")
    println(io, "| **Effective total** | **$(fmt(effective_total))** | | | **$(fmt_cost(total_cost))** | input (all sources) + output |")
    println(io, "| Output | $(fmt(m.total_output)) | \$25.00 | **5.0×** | $(fmt_cost(cost_output)) | most expensive |")
    println(io, "| Fresh input | $(fmt(m.total_input)) | \$5.00 | 1.0× | $(fmt_cost(cost_fresh)) | non-cached input tokens |")
    println(io, "| Cache creation | $(fmt(m.cache_creation)) | \$6.25 | 1.25× | $(fmt_cost(cost_cache_w)) | new cache entries |")
    println(io, "| Cache read | $(fmt(m.cache_read)) | \$0.50 | 0.1× | $(fmt_cost(cost_cache_r)) | cheapest |")
    println(io, "| Effective input | $(fmt(effective_input)) | | | | fresh + cache creation + cache read |")
    println(io, "| Cache hit rate | $(pct(m.cache_read, effective_input)) | | | | cache read / effective input |")
    println(io, "| Discovery cost | $(fmt(m.discovery_cost)) | | | | tokens before first Edit/Write |")
    println(io)
    println(io, "> **Budget impact:** $(fmt_cost(total_cost)) — output tokens account for $(@sprintf("%.0f", output_cost_pct))% of cost\n")

    println(io, "### Activity\n")
    println(io, "| Metric | Count | Eff. Input | Output |")
    println(io, "|---|---:|---:|---:|")
    println(io, "| Assistant turns | $(m.turn_count) | $(fmt(effective_input)) | $(fmt(m.total_output)) |")
    println(io, "| Files read | $read_count | | |")
    println(io, "| Files edited | $edit_count | | |")
    println(io, "| Irrelevant reads ≈ | $(length(irrelevant)) | | |")
    println(io, "| Multi-edited ≈ | $multi_edited | | |")
    if m.first_code_offset >= 0
        println(io, "| First code at token | $(fmt(m.first_code_offset)) | | |")
    end
    println(io)

    println(io, "### Tool Calls\n")
    println(io, "| Tool | Count | Eff. Input ≈ | Output ≈ |")
    println(io, "|---|---:|---:|---:|")
    for tname in sort(collect(keys(m.tool_counts)))
        ti = fmt(get(m.tool_input, tname, 0))
        to = fmt(get(m.tool_output, tname, 0))
        println(io, "| $tname | $(m.tool_counts[tname]) | $ti | $to |")
    end
    println(io)

    # Files Read — table inside <details>
    println(io, "### Files Read\n")
    read_paths = sort(collect(keys(m.files_read)))
    total_read_est = sum(est_tokens(get(m.files_read_chars, p, 0)) for p in read_paths; init=0)
    total_read_cost = cost_mtok(total_read_est, COST_CACHE_R)
    println(io, "<details><summary>$(length(read_paths)) files, ~$(fmt(total_read_est)) est. tokens, ~$(fmt_cost(total_read_cost))</summary>\n")
    println(io, "| File | Reads | Est. Tokens | Est. Cost |")
    println(io, "|---|---:|---:|---:|")
    for p in read_paths
        cnt = m.files_read[p]
        chars = get(m.files_read_chars, p, 0)
        toks = est_tokens(chars)
        println(io, "| $(short_path(p)) | $cnt | $(fmt(toks)) | $(fmt_cost(cost_mtok(toks, COST_CACHE_R))) |")
    end
    println(io, "\n</details>\n")

    # Files Edited — table inside <details>
    println(io, "### Files Edited\n")
    edit_paths = sort(collect(keys(m.files_edited)))
    total_edit_est = sum(est_tokens(get(m.files_edited_chars, p, 0)) for p in edit_paths; init=0)
    total_edit_cost = cost_mtok(total_edit_est, COST_CACHE_R)
    println(io, "<details><summary>$(length(edit_paths)) files, ~$(fmt(total_edit_est)) est. tokens, ~$(fmt_cost(total_edit_cost))</summary>\n")
    println(io, "| File | Edits | Est. Tokens | Est. Cost |")
    println(io, "|---|---:|---:|---:|")
    for p in edit_paths
        cnt = m.files_edited[p]
        chars = get(m.files_edited_chars, p, 0)
        toks = est_tokens(chars)
        println(io, "| $(short_path(p)) | $cnt | $(fmt(toks)) | $(fmt_cost(cost_mtok(toks, COST_CACHE_R))) |")
    end
    println(io, "\n</details>\n")

    # Irrelevant Reads — table inside <details>
    if !isempty(irrelevant)
        println(io, "### Irrelevant Reads (approx)\n")
        irr_sorted = sort(collect(irrelevant))
        total_irr_est = sum(est_tokens(get(m.files_read_chars, p, 0)) for p in irr_sorted; init=0)
        total_irr_cost = cost_mtok(total_irr_est, COST_CACHE_R)
        println(io, "<details><summary>$(length(irr_sorted)) files read but never edited, ~$(fmt(total_irr_est)) est. tokens wasted, ~$(fmt_cost(total_irr_cost))</summary>\n")
        println(io, "| File | Reads | Est. Tokens | Est. Cost |")
        println(io, "|---|---:|---:|---:|")
        for p in irr_sorted
            cnt = get(m.files_read, p, 0)
            chars = get(m.files_read_chars, p, 0)
            toks = est_tokens(chars)
            println(io, "| $(short_path(p)) | $cnt | $(fmt(toks)) | $(fmt_cost(cost_mtok(toks, COST_CACHE_R))) |")
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
        ("Cache hit rate", [pct(s.cache_read, s.total_input + s.cache_creation + s.cache_read) for s in sessions]),
        ("**Est. Cost**", ["**$(fmt_cost(session_cost(s)))**" for s in sessions]),
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

function resolve_latest(n::Int, sessions_dir::AbstractString=current_sessions_dir())
    files = filter(f -> endswith(f, ".jsonl"), readdir(sessions_dir; join=true))
    isempty(files) && error("No JSONL files found in $sessions_dir")
    sort!(files; by=mtime, rev=true)
    n = min(n, length(files))

    result = files[1:n]

    age_seconds = time() - mtime(result[1])
    if age_seconds < 60
        @warn "Most recent session was modified $(round(Int, age_seconds))s ago — likely still active. Results may be partial."
    end

    result
end

function write_single_report(io, m::SessionMetrics, source::AbstractString;
                             subscription::Real=DEFAULT_SUBSCRIPTION)
    println(io, "# Session Analysis Report\n")
    println(io, "**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM"))")
    println(io, "**Source:** `$source`\n")
    println(io, "---\n")
    write_session_section(io, m; subscription)
end

basename_path(p::AbstractString) =
    isempty(strip(p)) ? "" : String(last(split(strip(String(p)), r"[/\\]"; keepempty=false)))

# Subfolder for a session: its workspace folder name, else branch, else "unknown".
function session_group(m::SessionMetrics)
    g = basename_path(m.workspace)
    isempty(g) && (g = m.git_branch)
    isempty(g) && (g = "unknown")
    g = replace(g, r"[^A-Za-z0-9-]" => "-")
    strip(replace(g, r"-+" => "-"), '-')
end

# One row of the comparison tables.
struct HistoryRow
    m::SessionMetrics
    rel::String     # path relative to HISTORY_DIR, '/'-separated
    group::String
    mt::Float64     # source .jsonl mtime, for ordering
end

function write_comparison(path::AbstractString, rows::Vector{HistoryRow}, title::AbstractString;
                          link_fn, subscription::Real=DEFAULT_SUBSCRIPTION)
    sorted = sort(rows; by=r -> r.mt, rev=true)   # hottest (most recently changed) first
    weekly_budget = subscription * 7 / 30
    l_week_full = COST_WEIGHT[] > 0 ? weekly_budget / COST_WEIGHT[] : 0.0
    open(path, "w") do io
        println(io, "# $title\n")
        println(io, "**Generated:** $(Dates.format(now(), "yyyy-mm-dd HH:MM"))")
        println(io, "**Sessions:** $(length(sorted))  (ordered by last change, newest first)\n")
        println(io, "> **Cost basis:** subscription-amortized, not API list price. ",
            "Subscription \$$(@sprintf("%.0f", subscription))/mo (`--subscription`, default \$$(@sprintf("%.0f", DEFAULT_SUBSCRIPTION))) ",
            "→ weekly budget $(fmt_cost(weekly_budget)) (÷ $(@sprintf("%.3f", WEEKS_PER_MONTH)) wk/mo). ",
            "Weight = weekly budget ÷ busiest 7-day list cost $(fmt_cost(l_week_full)) (≈ one fully-used weekly quota, ",
            "aggregated across all sessions) = **×$(@sprintf("%.4f", COST_WEIGHT[]))**.\n")
        println(io, "> _More work raises the aggregated weekly total, shrinking the weight — so each report grows relatively cheaper over time._\n")
        println(io, "| Session | Last change | Group | Eff. total | Output | Discovery | Turns | Read | Edited | Est. Cost |")
        println(io, "|---|---|---|---:|---:|---:|---:|---:|---:|---:|")
        for r in sorted
            m = r.m
            eff = m.total_input + m.cache_creation + m.cache_read + m.total_output
            changed = Dates.format(unix2datetime(r.mt), "yyyy-mm-dd HH:MM")
            link = "[$(m.label)]($(link_fn(r)))"
            println(io, "| $link | $changed | `$(r.group)` | $(fmt(eff)) | $(fmt(m.total_output)) | " *
                        "$(fmt(m.discovery_cost)) | $(m.turn_count) | " *
                        "$(length(m.files_read)) | $(length(m.files_edited)) | $(fmt_cost(session_cost(m))) |")
        end
    end
end

# Sweep every Claude project folder and write one report per session into
# session/history/<group>/, plus a per-group history-comparison.md and a
# top-level history-comparison.md covering all sessions. A session report is
# regenerated only when its source .jsonl is newer than the existing report.
function run_history(subscription::Real=DEFAULT_SUBSCRIPTION)
    isdir(PROJECTS_ROOT) || error("Projects root not found: $PROJECTS_ROOT")
    mkpath(HISTORY_DIR)

    used_rels = Set{String}()
    rows = HistoryRow[]
    sources = Dict{String,String}()   # rel => source .jsonl path, for pass 2

    # Pass 1: parse every session and assign output paths (no reports written yet,
    # so the cost weight can be calibrated from the full population first).
    for proj in sort(readdir(PROJECTS_ROOT))
        projdir = joinpath(PROJECTS_ROOT, proj)
        isdir(projdir) || continue
        for f in sort(filter(x -> endswith(x, ".jsonl"), readdir(projdir; join=true)))
            session_id = first(splitext(basename(f)))
            m = parse_session(f)
            group = session_group(m)
            mt = mtime(f)
            stem = condense_title(m.label; fallback=session_id)
            # Prefix: inverse-time sort key + the readable last-alive datetime, so
            # the folder lists newest-first while the real time stays visible.
            last_alive = Dates.format(unix2datetime(mt), "yyyymmdd-HHMMSS")
            stem = "$(inv_key(mt))-$last_alive-$stem"
            # Disambiguate filename collisions within the group.
            fname = "$stem.md"
            if "$group/$fname" in used_rels
                fname = "$stem-$(first(session_id, 8)).md"
            end
            rel = "$group/$fname"
            push!(used_rels, rel)
            sources[rel] = f
            push!(rows, HistoryRow(m, rel, group, mt))
        end
    end

    isempty(rows) && (println(stderr, "No sessions found under $PROJECTS_ROOT"); return)

    # Calibrate the weight from raw list costs (COST_WEIGHT[] still 1.0), cache the
    # busiest-week list cost, then switch on weighting for all writes below.
    timed = Tuple{Float64,Float64}[(r.mt, session_cost(r.m)) for r in rows]
    l_week_full = busiest_week_cost(timed)
    try
        write(WEIGHT_CACHE, @sprintf("%.6f\n", l_week_full))
    catch e
        @warn "Could not write weight cache" path=WEIGHT_CACHE exception=e
    end
    set_cost_weight!(subscription, l_week_full)
    println(stderr, @sprintf("Cost weight ×%.4f  (sub \$%.0f/mo ÷ %.3f wk ÷ busiest-week \$%.2f)",
        COST_WEIGHT[], subscription, WEEKS_PER_MONTH, l_week_full))
    COST_WEIGHT[] > 1.0 && println(stderr,
        "  note: weight > 1 — usage is below the weekly budget, so each token costs more than list price.")

    # Pass 2: write per-session reports (regenerate only when the source is newer).
    for r in rows
        report = joinpath(HISTORY_DIR, r.rel)
        mkpath(dirname(report))
        if isfile(report) && mtime(report) >= r.mt
            println(stderr, "Up to date: $(r.rel)")
        else
            open(report, "w") do io
                write_single_report(io, r.m, sources[r.rel]; subscription)
            end
            println(stderr, "Wrote $(r.rel)")
        end
    end

    # Per-group comparison (related sessions only), links relative to the group folder.
    for group in sort(unique(r.group for r in rows))
        group_rows = filter(r -> r.group == group, rows)
        write_comparison(joinpath(HISTORY_DIR, group, COMPARISON_NAME), group_rows,
            "Session History — $group"; link_fn = r -> basename(r.rel), subscription)
    end

    # Top-level comparison across all sessions, links into the group subfolders.
    cmp = joinpath(HISTORY_DIR, COMPARISON_NAME)
    write_comparison(cmp, rows, "Session History Comparison (all)"; link_fn = r -> r.rel, subscription)

    println(stderr, "Comparison written to $cmp")
    println(cmp)
end

function main()
    args = copy(ARGS)

    # Pull out --subscription <amount> (monthly fee, $/mo) anywhere in the args.
    subscription = DEFAULT_SUBSCRIPTION
    j = findfirst(==("--subscription"), args)
    if j !== nothing
        j + 1 <= length(args) || error("--subscription requires an amount")
        subscription = parse(Float64, args[j+1])
        deleteat!(args, j:j+1)
    end

    if "--history" in args
        run_history(subscription)
        return
    end

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
          julia --project=program session/analyze-session.jl --history
          (any of the above may add: --subscription <amount>   # monthly fee \$/mo, default $(@sprintf("%.0f", DEFAULT_SUBSCRIPTION)))
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

    # A single session can't observe a full week, so reuse the cached busiest-week
    # list cost (from the last --history run) as an estimated weekly total.
    if isfile(WEIGHT_CACHE)
        l_week_full = tryparse(Float64, strip(read(WEIGHT_CACHE, String)))
        if l_week_full === nothing || l_week_full <= 0
            @warn "Ignoring unusable weight cache; using unweighted list prices." path=WEIGHT_CACHE
        else
            set_cost_weight!(subscription, l_week_full)
            println(stderr, @sprintf("Cost weight ×%.4f  (sub \$%.0f/mo, cached weekly est. \$%.2f)",
                COST_WEIGHT[], subscription, l_week_full))
        end
    else
        @warn "No weight cache — run `--history` once to calibrate. Using unweighted API list prices."
    end

    # Name: <inv-key>-<last-alive>-<condensed primary title>, matching the
    # history scheme: prefix by the newest session's last-alive time so reports
    # sort newest-first, with the readable datetime kept in the name.
    mt = maximum(mtime(p) for (_, p) in entries)
    last_alive = Dates.format(unix2datetime(mt), "yyyymmdd-HHMMSS")
    stem = condense_title(sessions[1].label; fallback="report")
    length(sessions) > 1 && (stem *= "-plus$(length(sessions) - 1)")
    outpath = joinpath(OUTPUT_DIR, "$(inv_key(mt))-$last_alive-$stem.md")

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
            write_session_section(io, m; subscription)
            println(io, "---\n")
        end

        write_comparison(io, sessions)
    end

    println(stderr, "Report written to $outpath")
    println(outpath)
end

main()
