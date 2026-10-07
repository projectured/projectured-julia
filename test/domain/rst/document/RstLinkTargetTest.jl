# What the target of an rst reference names, for a navigator: the part after an
# `.. _name:` target, a section by its title, a file beside the file of the
# document, and nothing for a URL.

function test_rst_link_target()
@testset "rst link targets" begin
    source = """
    Guide
    =====

    .. _ug:cha:queueing:

    Queueing
    --------

    Text.

    Routing Tables
    --------------

    More.
    """
    root = parse_rst(source)
    guide = root.elements[1]
    @test guide isa RstSection
    found = find_navigator_target(root, "ug:cha:queueing")
    @test found !== nothing
    @test evaluate_reference(root, found) isa RstSection
    @test get_rst_title_text(evaluate_reference(root, found)) == "Queueing"
    # A section by its title, as rst compares names: no case, one space.
    found = find_navigator_target(root, "routing   tables")
    @test get_rst_title_text(evaluate_reference(root, found)) == "Routing Tables"
    @test find_navigator_target(root, "nothing") === nothing
    folder = mktempdir()
    write(joinpath(folder, "other.rst"), "Other\n=====\n")
    file = RstFile(joinpath(folder, "index.rst"), root)
    @test get_rst_title_text(evaluate_reference(file, find_navigator_target(file, "Queueing"))) == "Queueing"
    @test find_navigator_target(file, "other.rst") == joinpath(folder, "other.rst")
    @test find_navigator_target(file, "https://omnetpp.org") === nothing
end
end
