function test_ned()
@testset "ReactiveNED" begin

# ── Leaf types ───────────────────────────────────────────────────────────

@testset "NedInsertion" begin
    ins = NedInsertion()
    @test ins.value === nothing
end

@testset "NedExtends" begin
    e = NedExtends("BaseModule")
    @test e.name == "BaseModule"
    e.name = "OtherModule"
    @test e.name == "OtherModule"
end

@testset "NedInterfaceName" begin
    iface = NedInterfaceName("ITransport")
    @test iface.name == "ITransport"
end

@testset "NedLoop" begin
    l = NedLoop("i"; from="0", to="n-1")
    @test l.param_name == "i"
    @test l.from_value == "0"
    @test l.to_value == "n-1"

    l2 = NedLoop("j")
    @test l2.from_value === nothing
    @test l2.to_value === nothing
end

@testset "NedCondition" begin
    c = NedCondition("index > 0")
    @test c.condition == "index > 0"

    c2 = NedCondition()
    @test c2.condition === nothing
end

@testset "NedLiteral" begin
    lit = NedLiteral(:string; text="\"hello\"", value="hello")
    @test lit.type == :string
    @test lit.text == "\"hello\""
    @test lit.value == "hello"
end

# ── Mid-level types ──────────────────────────────────────────────────────

@testset "NedPropertyKey" begin
    pk = NedPropertyKey(; name="title", literals=[NedLiteral(:string; text="\"Radio state\"")])
    @test pk.name == "title"
    @test length(pk.literals) == 1
end

@testset "NedProperty" begin
    p = NedProperty("display"; keys=[NedPropertyKey(; literals=[NedLiteral(:string; text="\"i=block/queue\"")])])
    @test p.name == "display"
    @test p.index === nothing
    @test p.is_implicit == false
    @test length(p.keys) == 1

    p2 = NedProperty("signal"; index="state")
    @test p2.index == "state"
end

@testset "NedPropertyDecl" begin
    pd = NedPropertyDecl("unit")
    @test pd.name == "unit"
    @test pd.is_array == false
end

@testset "NedParam" begin
    p = NedParam("delay"; type=:double, value="1ms")
    @test p.name == "delay"
    @test p.type == :double
    @test p.value == "1ms"
    @test p.is_volatile == false
    @test p.is_default == false

    p2 = NedParam("iaTime"; type=:double, is_volatile=true, value="exponential(2s)", is_default=true)
    @test p2.is_volatile == true
    @test p2.is_default == true
end

@testset "NedGate" begin
    g = NedGate("in"; type=:input)
    @test g.name == "in"
    @test g.type == :input
    @test g.is_vector == false
    @test g.vector_size === nothing

    g2 = NedGate("port"; type=:inout, is_vector=true, vector_size="numPorts")
    @test g2.is_vector == true
    @test g2.vector_size == "numPorts"
end

# ── Compound types ───────────────────────────────────────────────────────

@testset "NedSubmodule" begin
    s = NedSubmodule("host"; type="Host", vector_size="numHosts")
    @test s.name == "host"
    @test s.type == "Host"
    @test s.vector_size == "numHosts"
    @test s.like_type === nothing
end

@testset "NedConnection" begin
    c = NedConnection(; src_module="a", src_gate="out", dest_module="b", dest_gate="in")
    @test c.src_module == "a"
    @test c.src_gate == "out"
    @test c.dest_module == "b"
    @test c.dest_gate == "in"
    @test c.is_forward_arrow == true
    @test c.is_bidirectional == false
end

@testset "NedConnectionGroup" begin
    g = NedConnectionGroup()
    @test length(g.loops) == 0
    @test length(g.connections) == 0
    push!(g.loops, Cell(NedLoop("i"; from="0", to="n-1")))
    push!(g.connections, Cell(NedConnection(; src_module="a", src_gate="out", dest_module="b", dest_gate="in")))
    @test length(g.loops) == 1
    @test length(g.connections) == 1
end

# ── Top-level definition types ───────────────────────────────────────────

@testset "NedSimpleModule" begin
    m = NedSimpleModule("Host")
    @test m.name == "Host"
    @test m.extends === nothing
    @test length(m.params) == 0
    @test length(m.gates) == 0

    m2 = NedSimpleModule("SpecialHost"; extends=NedExtends("Host"))
    @test m2.extends isa NedExtends
    @test m2.extends.name == "Host"
end

@testset "NedCompoundModule" begin
    m = NedCompoundModule("Network")
    @test m.name == "Network"
    @test length(m.types) == 0
    @test length(m.submodules) == 0
    @test length(m.connections) == 0
    @test m.connections_allow_unconnected == false
end

@testset "NedChannel" begin
    ch = NedChannel("DataChannel"; extends=NedExtends("ned.DatarateChannel"))
    @test ch.name == "DataChannel"
    @test ch.extends.name == "ned.DatarateChannel"
end

@testset "NedModuleInterface" begin
    mi = NedModuleInterface("ITransport")
    @test mi.name == "ITransport"
    @test length(mi.extends_list) == 0
end

@testset "NedChannelInterface" begin
    ci = NedChannelInterface("IBidirectional")
    @test ci.name == "IBidirectional"
end

# ── File-level types ─────────────────────────────────────────────────────

@testset "NedPackage" begin
    p = NedPackage("inet.node")
    @test p.name == "inet.node"
end

@testset "NedImport" begin
    i = NedImport("inet.node.*")
    @test i.import_spec == "inet.node.*"
end

@testset "NedFile" begin
    f = NedFile("test.ned")
    @test f.filename == "test.ned"
    @test f.version == "2"
    @test isempty(f)

    push!(f, NedPackage("aloha"))
    push!(f, NedSimpleModule("Host"))
    @test length(f) == 2
    @test f[1] isa NedPackage
    @test f[2] isa NedSimpleModule

    deleteat!(f, 1)
    @test length(f) == 1
    @test f[1] isa NedSimpleModule

    insert!(f, 1, NedImport("ned.IdealChannel"))
    @test length(f) == 2
    @test f[1] isa NedImport

    # iterate
    count = 0
    for _ in f
        count += 1
    end
    @test count == 2
end

end # @testset "ReactiveNED"
end # test_ned

function test_ned_parser()
@testset "NedParser" begin

# ── Package and imports ─────────────────────────────────────────────────

@testset "package and imports" begin
    text = """
    package networks;
    import node.Node;
    import ned.DatarateChannel;
    """
    f = nedparse(text; filename="test.ned")
    @test f isa NedFile
    @test f.filename == "test.ned"
    @test length(f) == 3
    @test f[1] isa NedPackage
    @test f[1].name == "networks"
    @test f[2] isa NedImport
    @test f[2].import_spec == "node.Node"
    @test f[3] isa NedImport
    @test f[3].import_spec == "ned.DatarateChannel"
end

# ── File-level properties ────────────────────────────────────────────────

@testset "file-level properties" begin
    text = """
    @namespace(aloha);
    @license(omnetpp);
    """
    f = nedparse(text)
    @test length(f) == 2
    @test f[1] isa NedProperty
    @test f[1].name == "namespace"
    @test f[2] isa NedProperty
    @test f[2].name == "license"
end

# ── Simple module ────────────────────────────────────────────────────────

@testset "simple module" begin
    text = """
    simple Host {
        parameters:
            double txRate @unit(bps);
            volatile int pkLenBits @unit(b);
            bool controlAnimationSpeed = default(true);
            @display("i=device/pc_s");
        gates:
            input in;
            output out;
    }
    """
    f = nedparse(text)
    @test length(f) == 1
    m = f[1]
    @test m isa NedSimpleModule
    @test m.name == "Host"
    @test m.extends === nothing

    # params
    @test length(m.params) >= 4
    txRate = m.params[1]
    @test txRate isa NedParam
    @test txRate.name == "txRate"
    @test txRate.type == :double
    @test length(txRate.properties) >= 1
    @test txRate.properties[1].name == "unit"

    pkLen = m.params[2]
    @test pkLen.is_volatile == true
    @test pkLen.type == :int

    ctrl = m.params[3]
    @test ctrl.is_default == true

    # @display is a property in the params list
    disp = m.params[4]
    @test disp isa NedProperty
    @test disp.name == "display"

    # gates
    @test length(m.gates) == 2
    @test m.gates[1].name == "in"
    @test m.gates[1].type == :input
    @test m.gates[2].name == "out"
    @test m.gates[2].type == :output
end

# ── Simple module with extends ──────────────────────────────────────────

@testset "simple module extends" begin
    text = """
    simple RandomGraphNode extends Node {
        gates:
            inout g[];
    }
    """
    f = nedparse(text)
    m = f[1]
    @test m isa NedSimpleModule
    @test m.name == "RandomGraphNode"
    @test m.extends isa NedExtends
    @test m.extends.name == "Node"
    @test length(m.gates) == 1
    @test m.gates[1].type == :inout
    @test m.gates[1].is_vector == true
end

# ── Compound module (network) ───────────────────────────────────────────

@testset "network (compound module)" begin
    text = """
    network Aloha {
        parameters:
            int numHosts;
            double txRate @unit(bps);
            @display("bgi=background/terrain,s");
        submodules:
            server: Server;
            host[numHosts]: Host {
                txRate = parent.txRate;
            }
    }
    """
    f = nedparse(text)
    @test length(f) == 1
    m = f[1]
    @test m isa NedCompoundModule
    @test m.name == "Aloha"

    # params
    @test length(m.params) >= 3
    @test m.params[1].name == "numHosts"
    @test m.params[1].type == :int

    # submodules
    @test length(m.submodules) >= 2
    server = m.submodules[1]
    @test server isa NedSubmodule
    @test server.name == "server"
    @test server.type == "Server"

    host = m.submodules[2]
    @test host.name == "host"
    @test host.vector_size == "numHosts"
    @test host.type == "Host"
end

# ── Channel with extends ────────────────────────────────────────────────

@testset "channel extends" begin
    text = """
    channel Arc extends ned.IdealChannel {
        @class(Arc);
        int multiplicity = default(1);
    }
    """
    f = nedparse(text)
    @test length(f) == 1
    ch = f[1]
    @test ch isa NedChannel
    @test ch.name == "Arc"
    @test ch.extends isa NedExtends
    @test ch.extends.name == "ned.IdealChannel"
    @test length(ch.params) >= 2
end

# ── Connections with for loops ──────────────────────────────────────────

@testset "connection groups with for" begin
    text = """
    network Net {
        submodules:
            node[5]: Node;
        connections:
            for i=0..3 {
                node[i].out --> node[i+1].in;
            }
    }
    """
    f = nedparse(text)
    m = f[1]
    @test m isa NedCompoundModule
    @test length(m.connections) >= 1
    group = m.connections[1]
    @test group isa NedConnectionGroup
    @test length(group.loops) == 1
    @test group.loops[1].param_name == "i"
    @test length(group.connections) >= 1
end

# ── Bidirectional connections with channel type ─────────────────────────

@testset "bidirectional connections" begin
    text = """
    network Net5 {
        types:
            channel C extends DatarateChannel {
                delay = uniform(0.01ms, 1s);
            }
        submodules:
            rte[5]: Node;
        connections:
            rte[1].port++ <--> C <--> rte[0].port++;
    }
    """
    f = nedparse(text)
    m = f[1]
    @test m isa NedCompoundModule
    @test length(m.types) == 1
    @test m.types[1] isa NedChannel
    @test m.types[1].name == "C"

    @test length(m.connections) >= 1
    conn = m.connections[1]
    @test conn isa NedConnection
    @test conn.is_bidirectional == true
    @test conn.src_module == "rte"
    @test conn.dest_module == "rte"
    @test conn.type == "C"
end

# ── Connections with if condition ───────────────────────────────────────

@testset "connection with if" begin
    text = """
    network RG {
        submodules:
            node[10]: Node;
        connections:
            for i=0..8, for j=i+1..9 {
                node[i].g++ <--> node[j].g++ if uniform(0,1)<0.15;
            }
    }
    """
    f = nedparse(text)
    m = f[1]
    group = m.connections[1]
    @test group isa NedConnectionGroup
    @test length(group.loops) == 2
    @test group.loops[1].param_name == "i"
    @test group.loops[2].param_name == "j"
    conn = group.connections[1]
    @test conn.is_bidirectional == true
    @test conn.src_gate_plusplus == true
    @test conn.dest_gate_plusplus == true
    @test length(conn.conditions) >= 1
end

# ── Parse real .ned files from omnetpp/samples ──────────────────────────

@testset "parse aloha/Aloha.ned" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "omnetpp", "samples", "aloha", "Aloha.ned")
    if isfile(path)
        f = nedparse_file(path)
        @test f isa NedFile
        @test length(f) >= 1
        m = f[1]
        @test m isa NedCompoundModule
        @test m.name == "Aloha"
        @test length(m.params) >= 3
        @test length(m.submodules) >= 2
    end
end

@testset "parse aloha/Host.ned" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "omnetpp", "samples", "aloha", "Host.ned")
    if isfile(path)
        f = nedparse_file(path)
        @test f isa NedFile
        @test length(f) >= 1
        m = f[1]
        @test m isa NedSimpleModule
        @test m.name == "Host"
        @test length(m.params) >= 9
    end
end

@testset "parse aloha/package.ned" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "omnetpp", "samples", "aloha", "package.ned")
    if isfile(path)
        f = nedparse_file(path)
        @test f isa NedFile
        # file-level @namespace and @license properties
        props = [f[i] for i in 1:length(f) if f[i] isa NedProperty]
        @test length(props) >= 2
    end
end

@testset "parse routing/networks/Net5.ned" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "omnetpp", "samples", "routing", "networks", "Net5.ned")
    if isfile(path)
        f = nedparse_file(path)
        @test f isa NedFile
        # package + 2 imports + 1 network
        pkgs = [f[i] for i in 1:length(f) if f[i] isa NedPackage]
        @test length(pkgs) == 1
        imports = [f[i] for i in 1:length(f) if f[i] isa NedImport]
        @test length(imports) == 2
        modules = [f[i] for i in 1:length(f) if f[i] isa NedCompoundModule]
        @test length(modules) >= 1
        m = modules[1]
        @test m.name == "Net5"
        @test length(m.types) >= 1  # inner channel C
        @test length(m.connections) >= 1
    end
end

@testset "parse cqn/ClosedQueueingNetA.ned" begin
    path = joinpath(@__DIR__, "..", "..", "..", "..", "omnetpp", "samples", "cqn", "ClosedQueueingNetA.ned")
    if isfile(path)
        f = nedparse_file(path)
        @test f isa NedFile
        m = f[1]
        @test m isa NedCompoundModule
        @test m.name == "ClosedQueueingNetA"
        @test length(m.submodules) >= 2
        # connections should have for-loop groups
        groups = [m.connections[i] for i in 1:length(m.connections) if m.connections[i] isa NedConnectionGroup]
        @test length(groups) >= 3
    end
end

end # @testset "NedParser"
end # test_ned_parser
