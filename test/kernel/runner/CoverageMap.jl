# ============================================================================
# The map of what each part runs, and the parts of a change.
#
# A run with `--coverage FOLDER` writes, for each part, the source lines that the
# part executed (`run_covered`). `write_coverage_map` joins them into one map:
# each line that a part executed, with the parts that executed it. The parts of a
# change are then the parts that executed a line that the change touches, and not
# the parts of every package that uses a changed package. A change that no part
# runs, such as a `struct`, a `const` or a new file, keeps the rule of the folders
# (`reached_test_paths`).
# ============================================================================

"""
    write_coverage_map(folder, path; root = "") -> Int

Join the coverage files of `folder` (`FOLDER/index.tsv` and `FOLDER/parts`) into the
map file `path`, with one line `FILE LINE PART...` for each source line that a part
executed, the parts as `SUITE/NAME`. `FILE` is relative to `root` for a file in it, so
the map of a commit serves each checkout of the commit. Give the count of the lines.
"""
function write_coverage_map(folder::AbstractString, path::AbstractString; root::AbstractString = "")
    lines = Dict{Tuple{String, Int}, Set{String}}()
    index = joinpath(folder, "index.tsv")
    isfile(index) || error("no $index: the run had no --coverage")
    for entry in eachline(index)
        fields = split(entry, '\t')
        length(fields) == 3 || continue
        file, suite, name = fields
        key = isempty(suite) ? String(name) : string(suite, "/", name)
        source = ""
        for row in eachline(joinpath(folder, "parts", file))
            if startswith(row, "SF:")
                source = row[4:end]
                if !isempty(root) && startswith(source, rstrip(root, '/') * "/")
                    source = source[length(rstrip(root, '/')) + 2:end]
                end
            elseif startswith(row, "DA:")
                number, count = split(row[4:end], ',')[1:2]
                parse(Int, count) > 0 || continue
                push!(get!(Set{String}, lines, (source, parse(Int, number))), key)
            end
        end
    end
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        for ((source, number), keys) in sort!(collect(lines); by = first)
            println(io, source, '\t', number, '\t', join(sort!(collect(keys)), '\t'))
        end
    end
    length(lines)
end

"""
    read_coverage_map(path) -> Dict{String, Dict{Int, Vector{String}}}

The map of `write_coverage_map`: for each file, for each line, the parts that
executed it.
"""
function read_coverage_map(path::AbstractString)
    map = Dict{String, Dict{Int, Vector{String}}}()
    for row in eachline(path)
        fields = split(row, '\t')
        length(fields) >= 3 || continue
        get!(Dict{Int, Vector{String}}, map, fields[1])[parse(Int, fields[2])] = String.(fields[3:end])
    end
    map
end

"""
    test_coverage_store() -> String

The folder of the stored maps of the commits of `main`: the value of
`PROJECTURED_TEST_COVERAGE_STORE` when it is set, or else
`~/.cache/projectured-test-coverage`. The map of a commit is the file
`<repository>/<the first 12 characters of the commit>/map.tsv` in it.
"""
test_coverage_store() =
    get(ENV, "PROJECTURED_TEST_COVERAGE_STORE", joinpath(homedir(), ".cache", "projectured-test-coverage"))

"""
    find_coverage_map(root, base) -> (path, commit)

The stored map (`test_coverage_store`) of the newest commit at or before the fork of
`HEAD` from `base` in the repository at `root`, among the last 200 commits of the first
parents, and that commit; `("", "")` when no map is stored. The changes since that
commit then hold the changes of `main` after it too, so an older map chooses more parts.
"""
function find_coverage_map(root::AbstractString, base::AbstractString)
    store = joinpath(test_coverage_store(), repository_name(root))
    for commit in fork_commits(root, base)
        path = joinpath(store, commit[1:12], "map.tsv")
        isfile(path) && return (path, commit)
    end
    ("", "")
end

# The path relative to `root` of the file `key` of a map, or `nothing` for a file
# outside `root`.
function _map_file(key::AbstractString, root::AbstractString)
    isabspath(key) || return key
    startswith(key, root * "/") ? key[length(root) + 2:end] : nothing
end

# The changes of each file since `base`: the changed lines of the base side, the
# line ranges of the new side, and whether the file is new.
function _changed_lines(root::AbstractString, base::AbstractString)
    changes = Dict{String, NamedTuple{(:base, :new, :is_new), Tuple{Vector{Int}, Vector{UnitRange{Int}}, Bool}}}()
    file = ""
    for line in split(_git_text(root, `diff -U0 --no-color --no-renames $base --`), '\n')
        if startswith(line, "--- ")
            file = ""
        elseif startswith(line, "+++ ")
            path = line[5:end]
            file = path == "/dev/null" ? "" : replace(path, r"^b/" => "")
            isempty(file) || (changes[file] = (base = Int[], new = UnitRange{Int}[], is_new = false))
        elseif startswith(line, "@@") && !isempty(file)
            m = match(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@", line)
            m === nothing && continue
            a, b = parse(Int, m[1]), m[2] === nothing ? 1 : parse(Int, m[2])
            c, d = parse(Int, m[3]), m[4] === nothing ? 1 : parse(Int, m[4])
            entry = changes[file]
            # A line that went or changed; for a line that came, the two lines around it.
            append!(entry.base, b > 0 ? (a:a + b - 1) : (a:a + 1))
            d > 0 && push!(entry.new, c:c + d - 1)
            changes[file] = (base = entry.base, new = entry.new, is_new = a == 0 && b == 0)
        end
    end
    # A file that git does not hold yet is new.
    for path in split(_git_text(root, `ls-files --others --exclude-standard`), '\n')
        isempty(path) || (changes[String(path)] = (base = Int[], new = UnitRange{Int}[], is_new = true))
    end
    # A deleted file: each line of the base side went.
    for path in split(_git_text(root, `diff --name-only --diff-filter=D $base --`), '\n')
        isempty(path) && continue
        count = length(split(_git_text(root, `show $base:$path`), '\n'))
        changes[String(path)] = (base = collect(1:count), new = UnitRange{Int}[], is_new = false)
    end
    changes
end

# The functions that `text` defines, as (name, first line, last line of the header, last
# line), in modules too. The header is the docstring and the signature: the lines before
# the first line of the body.
function _definitions(text::AbstractString)
    found = Tuple{Symbol, Int, Int, Int}[]
    tree = try
        Meta.parseall(text)
    catch
        return found
    end
    last_line = count(==('\n'), text) + 1
    function name_of(signature)
        signature isa Expr || return nothing
        signature.head === :where && return name_of(signature.args[1])
        signature.head === :(::) && length(signature.args) == 2 && return name_of(signature.args[1])
        signature.head === :call || return nothing
        callee = signature.args[1]
        callee isa Symbol && return callee
        callee isa Expr && callee.head === :. && callee.args[end] isa QuoteNode && return callee.args[end].value
        nothing
    end
    function definition_of(ex)
        ex isa Expr || return nothing
        ex.head === :macrocall && return definition_of(ex.args[end])
        is_definition = ex.head === :function ||
            (ex.head === :(=) && ex.args[1] isa Expr && ex.args[1].head in (:call, :where))
        is_definition || return nothing
        name = name_of(ex.args[1])
        name === nothing && return nothing
        body = length(ex.args) >= 2 ? ex.args[2] : nothing
        line = body isa Expr && body.head === :block ?
            findfirst(a -> a isa LineNumberNode, body.args) : nothing
        (name, line === nothing ? 0 : body.args[line].line)
    end
    function walk(block, stop)
        arguments = block.args
        for (k, ex) in enumerate(arguments)
            ex isa LineNumberNode && continue
            start = k > 1 && arguments[k - 1] isa LineNumberNode ? arguments[k - 1].line : 0
            start == 0 && continue
            next = findnext(a -> a isa LineNumberNode, arguments, k + 1)
            finish = next === nothing ? stop : arguments[next].line - 1
            if ex isa Expr && ex.head === :module
                walk(ex.args[3], finish)
            else
                definition = definition_of(ex)
                if definition !== nothing
                    name, body = definition
                    header = body > start ? body - 1 : start
                    push!(found, (name, start, min(header, finish), finish))
                end
            end
        end
    end
    tree isa Expr && walk(tree, last_line)
    found
end

"""
    select_covered_parts(map, root, base) -> (parts, fallback, uncovered)

The parts of the changes since `base` in the repository at `root`, by the coverage
`map` of `base` (`read_coverage_map`): each part that executed a changed line; for a
changed signature and for a new method, each part that executed a method of that name;
and the parts of a changed test file stay with `fallback`. `fallback` holds the files
whose changes the map can not place: a new file, and lines that no part executed
outside a function. `uncovered` holds the `FILE:LINE` of the changed lines in a function
that no part executes.
"""
function select_covered_parts(map, root::AbstractString, base::AbstractString)
    parts, fallback, uncovered = Set{String}(), String[], String[]
    changes = _changed_lines(root, base)
    by_name = Dict{Symbol, Set{String}}()           # the parts of each function name
    definitions = Dict{String, Vector{Tuple{Symbol, Int, Int, Int}}}()
    function base_definitions(file)
        get!(definitions, file) do
            _definitions(_git_text(root, `show $base:$file`))
        end
    end
    function parts_of_name(name)
        get!(by_name, name) do
            found = Set{String}()
            for (key, lines) in map
                file = _map_file(key, root)
                file !== nothing && endswith(file, ".jl") || continue
                for (n, first, _, last) in base_definitions(file)
                    n == name || continue
                    for number in first:last
                        union!(found, get(lines, number, String[]))
                    end
                end
            end
            found
        end
    end
    for (file, change) in changes
        endswith(file, ".jl") || continue
        startswith(file, "test/") && (push!(fallback, file); continue)
        change.is_new && (push!(fallback, file); continue)
        lines = get(() -> get(map, joinpath(root, file), Dict{Int, Vector{String}}()), map, file)
        defs = base_definitions(file)
        for number in change.base
            inside = findfirst(d -> d[2] <= number <= d[4], defs)
            if inside !== nothing && number <= defs[inside][3]
                union!(parts, parts_of_name(defs[inside][1]))      # the docstring or the signature
            elseif haskey(lines, number)
                union!(parts, lines[number])
            elseif inside === nothing
                file in fallback || push!(fallback, file)          # runs at load
            else
                push!(uncovered, string(file, ":", number))        # no part runs it
            end
        end
        # A method that came: each part that executed a method of its name.
        current = isfile(joinpath(root, file)) ? read(joinpath(root, file), String) : ""
        for (name, first, _, last) in _definitions(current)
            any(range -> !isempty(intersect(range, first:last)), change.new) || continue
            any(d -> d[1] == name, defs) || continue
            union!(parts, parts_of_name(name))
        end
    end
    (parts, sort!(unique!(fallback)), uncovered)
end
