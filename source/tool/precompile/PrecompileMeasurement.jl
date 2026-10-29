# ──────────────────────────────────────────────────────────────────────────
# The measurements of U7 that each repository takes the same way: the build of
# the image of each package, and the build of a binary. The command
# `tool/measure-compile-ahead.jl` of each repository calls them and adds the
# measurements of its own.
# ──────────────────────────────────────────────────────────────────────────

"""
    measure_folder_bytes(folder) -> Int

The size of each file under `folder`, added up, and 0 when there is no folder.
"""
function measure_folder_bytes(folder::AbstractString)
    isdir(folder) || return 0
    sum((filesize(joinpath(root, file)) for (root, _, files) in walkdir(folder) for file in files);
        init = 0)
end

"""
    print_measurement_row(io, label, value, unit; digits = 1) -> Nothing

One line of a table of measurements: the label, then the value with `digits`
decimals and its unit, so that the tables of each repository read the same.
"""
function print_measurement_row(io::IO, label::AbstractString, value::Real, unit::AbstractString;
                               digits::Integer = 1)
    println(io, "  ", rpad(label, 44), " ", lpad(string(round(Float64(value); digits)), 9),
            " ", unit)
    nothing
end

"""
    measure_package_images(environment; io = stdout) -> Vector{NamedTuple}

Build the image of each package of `environment` in a depot of its own, so that
no image of an earlier build is reused, and answer `(; name, seconds, bytes)`
for each package, the slowest first, and last for all of them, with the wall
time of the build. The depot takes the packages, the artifacts and the
registries of the first depot of this process, so the build downloads nothing.
The table goes to `io`.
"""
function measure_package_images(environment::AbstractString; io::IO = stdout)
    depot = mktempdir()
    source = first(DEPOT_PATH)
    for folder in ("packages", "artifacts", "registries", "scratchspaces", "clones")
        isdir(joinpath(source, folder)) && symlink(joinpath(source, folder), joinpath(depot, folder))
    end
    command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment
                      -e "using Pkg; Pkg.precompile()"`,
                     "JULIA_DEPOT_PATH" => depot * (Sys.iswindows() ? ";" : ":"),
                     "JULIA_PKG_OFFLINE" => "true")
    output = IOBuffer()
    start = time()
    process = run(pipeline(ignorestatus(command); stdout = output, stderr = output))
    seconds = time() - start
    text = String(take!(output))
    success(process) || println(io, last(text, 4000))
    compiled = joinpath(depot, "compiled", "v$(VERSION.major).$(VERSION.minor)")
    rows = NamedTuple{(:name, :seconds, :bytes),Tuple{String,Float64,Int}}[]
    for found in eachmatch(r"(?m)^\s*([\d.]+) s\s+✓ (\S+)", text)
        name = String(found.captures[2])
        push!(rows, (; name, seconds = parse(Float64, found.captures[1]),
                     bytes = measure_folder_bytes(joinpath(compiled, name))))
    end
    sort!(rows; by = row -> -row.seconds)
    push!(rows, (; name = "all", seconds, bytes = measure_folder_bytes(compiled)))
    for row in rows
        println(io, "  ", rpad(row.name == "all" ? "all, the wall time" : row.name, 44), " ",
                lpad(string(round(row.seconds; digits = 1)), 8), " s ",
                lpad(string(round(row.bytes / 1e6; digits = 1)), 9), " MB")
    end
    rm(depot; recursive = true, force = true)
    rows
end

"""
    measure_process_median(command; runs = 3, io = stdout) -> Vector{Pair{String,Float64}}

Run `command` `runs` times, each in a new process, and answer the median of each
value that it prints on a line `MEASUREMENT <label>: <seconds>`, in the order of
the first run. A run that prints no such line counts for nothing. The table
goes to `io`.
"""
function measure_process_median(command::Cmd; runs::Integer = 3, io::IO = stdout)
    values = Dict{String,Vector{Float64}}()
    labels = String[]
    for _ in 1:runs
        for found in eachmatch(r"(?m)^MEASUREMENT (.+): (\S+)$", read(ignorestatus(command), String))
            label = String(found.captures[1])
            haskey(values, label) || (push!(labels, label); values[label] = Float64[])
            push!(values[label], parse(Float64, found.captures[2]))
        end
    end
    isempty(labels) && println(io, "  the process printed no measurement")
    medians = [label => sort(values[label])[cld(length(values[label]), 2)] for label in labels]
    for (label, seconds) in medians
        print_measurement_row(io, label, seconds, "s"; digits = 2)
    end
    medians
end

"""
    measure_binary_build(command, bundle; io = stdout) -> NamedTuple

Run `command`, which builds a binary into the folder `bundle`, and answer
`(; success, seconds, peak_bytes, bundle_bytes)`. The peak memory of the build
comes from `/usr/bin/time`, and it is `nothing` on a system that has none. The
table goes to `io`.
"""
function measure_binary_build(command::Cmd, bundle::AbstractString; io::IO = stdout)
    time_tool = "/usr/bin/time"
    report = tempname()
    isfile(time_tool) && (command = `$time_tool -f "%M" -o $report $command`)
    start = time()
    process = run(ignorestatus(command))
    seconds = time() - start
    built = success(process)
    built || println(io, "  the build failed")
    peak_bytes = isfile(report) ? 1024 * parse(Int, strip(last(readlines(report)))) : nothing
    bundle_bytes = measure_folder_bytes(bundle)
    print_measurement_row(io, "the build time", seconds, "s")
    peak_bytes === nothing ||
        print_measurement_row(io, "the peak memory of the build", peak_bytes / 2^30, "GiB")
    print_measurement_row(io, "the bundle", bundle_bytes / 1e6, "MB")
    (; success = built, seconds, peak_bytes, bundle_bytes)
end
