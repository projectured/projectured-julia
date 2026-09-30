# Fixture content for the file-system examples. Never loaded.

function main(args)
    config = read_config(joinpath(@__DIR__, "..", "data", "config.yaml"))
    for name in args
        println(greet(name, config))
    end
end
