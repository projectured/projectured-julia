function make_ned_document_example()
    nedparse("""
        package aloha;

        simple Host {
            parameters:
                double txRate @unit(bps);
                volatile double iaTime @unit(s);
                double slotTime @unit(s);
                bool controlAnimationSpeed = default(true);
                @display("i=device/pc_s");
            gates:
                input in;
                output out;
        }

        simple Server {
            parameters:
                @display("i=device/antennatower");
            gates:
                input in[];
        }

        network Aloha {
            parameters:
                int numHosts;
                double txRate @unit(bps);
                double slotTime @unit(ms);
                @display("bgi=background/terrain,s;bgb=1000,1000");
            submodules:
                server: Server;
                host[numHosts]: Host {
                    txRate = parent.txRate;
                    slotTime = parent.slotTime;
                }
        }
    """; filename="aloha.ned")
end
