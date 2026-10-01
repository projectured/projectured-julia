# `load_installed_package!` loads a package by the environment of the session. The
# test starts a new Julia process whose environment holds a stand-in package, and
# whose load path reaches the platform through the environment of this test.

# A stand-in package at `folder/name`.
function _write_installed_package_fixture(folder, name, uuid)
    mkpath(joinpath(folder, name, "src"))
    write(joinpath(folder, name, "Project.toml"),
          "name = \"$name\"\nuuid = \"$uuid\"\nversion = \"0.1.0\"\n")
    write(joinpath(folder, name, "src", "$name.jl"), "module $name end\n")
end

function test_load_installed_package()
    @testset "a package loads when the environment of the session has it" begin
        folder = mktempdir()
        _write_installed_package_fixture(folder, "Installed",
                                         "10000000-0000-0000-0000-000000000011")
        environment = joinpath(folder, "environment")
        mkpath(environment)
        write(joinpath(environment, "Project.toml"), """
            [deps]
            Installed = "10000000-0000-0000-0000-000000000011"
            """)
        write(joinpath(environment, "Manifest.toml"), """
            manifest_format = "2.0"

            [[deps.Installed]]
            path = "../Installed"
            uuid = "10000000-0000-0000-0000-000000000011"
            version = "0.1.0"
            """)
        code = """
            using ProjecturedPlatform
            installed = load_installed_package!("Installed")
            missing_package = load_installed_package!("NoSuchPackage")
            print(installed === nothing ? "nothing" : nameof(installed), " ",
                  missing_package === nothing ? "nothing" : nameof(missing_package))
            """
        load_path = join(["@", dirname(Base.active_project()), "@stdlib"],
                         Sys.iswindows() ? ";" : ":")
        command = addenv(`$(Base.julia_cmd()) --startup-file=no --project=$environment -e $code`,
                         "JULIA_LOAD_PATH" => load_path, "JULIA_PKG_OFFLINE" => "true")
        @test read(command, String) == "Installed nothing"
    end
end
