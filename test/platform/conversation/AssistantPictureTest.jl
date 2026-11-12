# The folder of the pictures of the assistant keeps a picture for
# `PICTURE_KEEP_DAYS` days: the name of a new picture removes the older ones.

import ProjecturedPlatform.AssistantModule: _make_picture_filename, PICTURE_KEEP_DAYS

# Set the time of the last change of the file at `path` to `days` days ago.
_set_picture_age!(path, days) =
    run(`touch -m -d @$(round(Int, time() - days * 86400)) $path`)

function test_assistant_picture()
    @testset "the pictures of the assistant" begin
        @testset "a new picture removes the pictures that are older than the days they stay" begin
            mktempdir() do cache
                withenv("XDG_CACHE_HOME" => cache) do
                    directory = mkpath(joinpath(cache, "projectured", "pictures"))
                    old = joinpath(directory, "picture-20261001-120000.png")
                    recent = joinpath(directory, "picture-20261020-120000.png")
                    other = joinpath(directory, "notes.txt")
                    foreach(path -> write(path, "x"), (old, recent, other))
                    _set_picture_age!(old, PICTURE_KEEP_DAYS + 1)
                    _set_picture_age!(recent, PICTURE_KEEP_DAYS - 1)
                    _set_picture_age!(other, PICTURE_KEEP_DAYS + 1)
                    filename = _make_picture_filename()
                    @test sort(readdir(directory)) == ["notes.txt", "picture-20261020-120000.png"]
                    @test dirname(filename) == directory
                    @test startswith(basename(filename), "picture-") && endswith(filename, ".png")
                    @test !isfile(filename)
                end
            end
        end
    end
end
