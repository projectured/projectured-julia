# Record the calls that the parts of the test packages compile, into
# `package/<TestPackage>/precompile/workload.txt` (compile-ahead.md, Decision 11):
#
#     julia --project=environment/all tool/record-test-calls.jl [--jobs N] [PACKAGE...]
#     julia --project=environment/all tool/record-test-calls.jl --changed BASE [--jobs N]
#     julia --project=environment/all tool/record-test-calls.jl --changed BASE --list
#
# With no package, each test package with a workload records. With `--changed BASE`,
# each test package whose files changed since the commit BASE records: a file of its
# folder, or a file that its entry file includes. A package records after each test
# package that it depends on and that records too, so that no call goes into two lists
# (Decision 7). `--jobs N` records N packages at the same time (default 2). Run it
# with no network, as `julia-worktree run` does, so that no part reaches a model.

const PRECOMPILE = Base.require(Base.PkgId(Base.UUID("8baac0ef-e501-42fc-bcd5-0b2a8f58a069"),
                                           "ProjecturedPrecompile"))
const ROOT = normpath(joinpath(@__DIR__, ".."))
const ENVIRONMENT = joinpath(ROOT, "environment", "all")

# The files of the test package `name`: its folder, and each file that its entry file
# includes, and the files that those include.
function package_files(name::AbstractString)
    folder = joinpath(ROOT, "package", name)
    files = Set{String}()
    for (directory, _, names) in walkdir(folder), file in names
        push!(files, relpath(joinpath(directory, file), ROOT))
    end
    pending = [joinpath(folder, "src", name * ".jl")]
    scanned = Set{String}()
    while !isempty(pending)
        path = pop!(pending)
        (path in scanned || !isfile(path)) && continue
        push!(scanned, path)
        for found in eachmatch(r"(?m)^\s*include\(\"([^\"]+)\"\)", read(path, String))
            included = normpath(joinpath(dirname(path), found[1]))
            push!(files, relpath(included, ROOT))
            push!(pending, included)
        end
    end
    files
end

function changed_since(base::AbstractString)
    text = readchomp(`git -C $ROOT diff --name-only $base --`)
    Set(filter(!isempty, split(text, '\n')))
end

function main(arguments)
    jobs, base, names, is_list = 2, "", String[], false
    k = 1
    while k <= length(arguments)
        word = arguments[k]
        if word == "--jobs"
            jobs = parse(Int, arguments[k + 1]); k += 2
        elseif word == "--changed"
            base = arguments[k + 1]; k += 2
        elseif word == "--list"
            is_list = true; k += 1
        else
            push!(names, word); k += 1
        end
    end
    tests = filter(name -> endswith(name, "Test") &&
                           PRECOMPILE.has_package_workload(joinpath(ROOT, "package", name)),
                   PRECOMPILE.collect_compiling_packages(ROOT))
    if !isempty(base)
        changed = changed_since(base)
        names = filter(name -> !isempty(intersect(package_files(name), changed)), tests)
    elseif isempty(names)
        names = tests
    end
    isempty(names) && (println("No test package records."); return 0)
    closures = PRECOMPILE.collect_package_closures(ENVIRONMENT)
    waits_for(name) = [other for other in names
                       if other != name && other in get(closures, name, Set{String}())]
    is_list && (foreach(println, sort(names)); return 0)
    println("Recording ", length(names), " test packages: ", join(sort(names), ", "))
    done = Set{String}()
    started = Set{String}()
    failed = String[]
    slots = Base.Semaphore(jobs)
    finished = Channel{String}(Inf)
    @sync while length(done) < length(names)
        for name in names
            name in started && continue
            all(in(done), waits_for(name)) || continue
            push!(started, name)
            @async begin
                Base.acquire(slots)
                try
                    seconds = @elapsed path = PRECOMPILE.record_package_calls!(name; root = ROOT,
                                                                               environment = ENVIRONMENT)
                    calls = count(line -> !startswith(line, "#") && !isempty(line), eachline(path))
                    println("Recorded ", name, ": ", calls, " calls in ", round(seconds; digits = 1), " s.")
                catch error
                    push!(failed, name)
                    println("The recording of ", name, " failed: ", sprint(showerror, error))
                finally
                    Base.release(slots)
                    put!(finished, name)
                end
            end
        end
        push!(done, take!(finished))
    end
    isempty(failed) ? 0 : 1
end

exit(main(ARGS))
