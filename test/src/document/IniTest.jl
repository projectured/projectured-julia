function test_ini()
@testset "ReactiveINI" begin

# ── Leaf types ───────────────────────────────────────────────────────────

@testset "IniComment" begin
    c = IniComment(" this is a comment")
    @test c.text == " this is a comment"
    c.text = " updated"
    @test c.text == " updated"
end

@testset "IniInclude" begin
    inc = IniInclude("omnetpp.ini")
    @test inc.path == "omnetpp.ini"
    inc.path = "../common/config.ini"
    @test inc.path == "../common/config.ini"
end

@testset "IniInsertion" begin
    ins = IniInsertion()
    @test ins.value === nothing
end

# ── Entry types ──────────────────────────────────────────────────────────

@testset "IniConfigOption" begin
    opt = IniConfigOption("network", "Aloha")
    @test opt.key == "network"
    @test opt.value == "Aloha"
    @test opt.comment === nothing

    opt2 = IniConfigOption("sim-time-limit", "100h"; comment=" time limit")
    @test opt2.comment == " time limit"
end

@testset "IniParamAssignment" begin
    pa = IniParamAssignment("**.host[*].iaTime", "exponential(2s)")
    @test pa.key == "**.host[*].iaTime"
    @test pa.value == "exponential(2s)"
    @test pa.comment === nothing

    pa2 = IniParamAssignment("**.vector-recording", "false"; comment=" disable")
    @test pa2.comment == " disable"
end

# ── IniSection ───────────────────────────────────────────────────────────

@testset "IniSection" begin
    # auto-detect General
    gen = IniSection("General")
    @test gen.is_general == true
    @test gen.name == "General"
    @test isempty(gen)

    # named config
    cfg = IniSection("PureAloha1")
    @test cfg.is_general == false
    @test cfg.name == "PureAloha1"

    # with entries
    sec = IniSection("Foo", [
        IniConfigOption("network", "Bar"),
        IniParamAssignment("**.x", "1"),
        IniComment(" a comment"),
    ])
    @test length(sec) == 3
    @test sec[1] isa IniConfigOption
    @test sec[2] isa IniParamAssignment
    @test sec[3] isa IniComment

    # push / deleteat / insert
    push!(sec, IniInclude("other.ini"))
    @test length(sec) == 4
    @test sec[4] isa IniInclude

    deleteat!(sec, 3)
    @test length(sec) == 3

    insert!(sec, 1, IniComment(" first"))
    @test length(sec) == 4
    @test sec[1] isa IniComment
    @test sec[1].text == " first"

    # iterate
    count = 0
    for _ in sec
        count += 1
    end
    @test count == 4
end

# ── IniFile ──────────────────────────────────────────────────────────────

@testset "IniFile" begin
    f = IniFile()
    @test isempty(f)

    push!(f, IniComment(" top comment"))
    push!(f, IniSection("General", [IniConfigOption("network", "Net")]))
    push!(f, IniSection("Cfg1", [IniParamAssignment("**.x", "5")]))
    @test length(f) == 3
    @test f[1] isa IniComment
    @test f[2] isa IniSection
    @test f[2].is_general == true
    @test f[3].name == "Cfg1"

    deleteat!(f, 1)
    @test length(f) == 2
    @test f[1] isa IniSection

    # construct with vector
    f2 = IniFile([
        IniSection("General"),
        IniSection("Foo"),
    ])
    @test length(f2) == 2
end

end # @testset "ReactiveINI"
end # test_ini

function test_ini_parser()
@testset "IniParser" begin

# ── Basic parsing ────────────────────────────────────────────────────────

@testset "simple ini" begin
    text = """
    # top comment
    [General]
    network = Aloha
    sim-time-limit = 100h

    [Config PureAloha1]
    description = "pure Aloha"
    **.host[*].iaTime = exponential(2s)
    """
    f = iniparse(text)
    @test f isa IniFile

    # top comment + 2 sections
    @test length(f) == 3
    @test f[1] isa IniComment
    @test f[1].text == " top comment"

    gen = f[2]
    @test gen isa IniSection
    @test gen.is_general == true
    @test gen.name == "General"
    @test length(gen) == 2
    @test gen[1] isa IniConfigOption
    @test gen[1].key == "network"
    @test gen[1].value == "Aloha"
    @test gen[2].key == "sim-time-limit"
    @test gen[2].value == "100h"

    pa = f[3]
    @test pa.name == "PureAloha1"
    @test pa.is_general == false
    @test length(pa) == 2
    @test pa[1] isa IniConfigOption
    @test pa[1].key == "description"
    @test pa[1].value == "\"pure Aloha\""
    @test pa[2] isa IniParamAssignment
    @test pa[2].key == "**.host[*].iaTime"
    @test pa[2].value == "exponential(2s)"
end

# ── Section name normalisation ───────────────────────────────────────────

@testset "section names" begin
    text = """
    [General]
    [Config Foo]
    [Bar]
    """
    f = iniparse(text)
    sections = [f[i] for i in 1:length(f)]
    @test sections[1].name == "General"
    @test sections[1].is_general == true
    @test sections[2].name == "Foo"
    @test sections[2].is_general == false
    @test sections[3].name == "Bar"
    @test sections[3].is_general == false
end

# ── Include directive ────────────────────────────────────────────────────

@testset "include directive" begin
    text = """
    include omnetpp.ini

    [General]
    network = Aloha
    """
    f = iniparse(text)
    @test f[1] isa IniInclude
    @test f[1].path == "omnetpp.ini"
end

# ── Inline comments ──────────────────────────────────────────────────────

@testset "inline comments" begin
    text = """
    [General]
    network = Aloha # the network
    description = "has # inside" # real comment
    **.x = 5
    """
    f = iniparse(text)
    gen = f[1]
    @test gen[1].value == "Aloha"
    @test gen[1].comment == " the network"
    # hash inside quotes should not split
    @test gen[2].value == "\"has # inside\""
    @test gen[2].comment == " real comment"
    @test gen[3].comment === nothing
end

# ── Iteration variables ─────────────────────────────────────────────────

@testset "iteration variables in values" begin
    text = """
    [Config Study]
    *.numHosts = \${numHosts=10,15,20}
    **.iaTime = exponential(\${iaMean=1,2,3}s)
    """
    f = iniparse(text)
    sec = f[1]
    @test sec[1].value == "\${numHosts=10,15,20}"
    @test sec[2].value == "exponential(\${iaMean=1,2,3}s)"
end

# ── Backslash line continuation ──────────────────────────────────────────

@testset "backslash continuation" begin
    text = "[General]\n**.url = \"http://example.com/very\\\n-long-url\"\n"
    f = iniparse(text)
    gen = f[1]
    @test gen[1].value == "\"http://example.com/very-long-url\""
end

# ── Commented-out entries ────────────────────────────────────────────────

@testset "commented entries are IniComment" begin
    text = """
    [General]
    #debug-on-errors = true
    network = Foo
    """
    f = iniparse(text)
    gen = f[1]
    @test gen[1] isa IniComment
    @test gen[1].text == "debug-on-errors = true"
    @test gen[2] isa IniConfigOption
end

# ── Parse real aloha/omnetpp.ini ─────────────────────────────────────────

@testset "parse aloha sample" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "omnetpp", "samples", "aloha", "omnetpp.ini")
    if isfile(path)
        f = iniparse_file(path)
        @test f isa IniFile
        # count sections (skip top-level comments)
        sections = [f[i] for i in 1:length(f) if f[i] isa IniSection]
        @test length(sections) >= 2  # at least General + one config
        # General section has a network entry
        gen = sections[1]
        @test gen.is_general == true
        network_entries = [gen[i] for i in 1:length(gen) if gen[i] isa IniConfigOption && gen[i].key == "network"]
        @test length(network_entries) >= 1
    end
end

# ── Parse aloha/akaroa.ini (include directive) ───────────────────────────

@testset "parse akaroa sample" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "omnetpp", "samples", "aloha", "akaroa.ini")
    if isfile(path)
        f = iniparse_file(path)
        @test f isa IniFile
        # should have an include directive
        includes = [f[i] for i in 1:length(f) if f[i] isa IniInclude]
        @test length(includes) >= 1
        @test includes[1].path == "omnetpp.ini"
    end
end

end # @testset "IniParser"
end # test_ini_parser
