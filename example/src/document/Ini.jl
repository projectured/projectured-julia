function make_ini_document_example()
    IniFile([
        IniComment(" OMNeT++ Aloha simulation configuration"),
        IniInclude("common-defaults.ini"),
        IniSection("General", [
            IniConfigOption("network", "Aloha"),
            IniConfigOption("sim-time-limit", "90min"),
            IniConfigOption("repeat", "2"),
            IniComment(" Logging"),
            IniConfigOption("cmdenv-express-mode", "true"),
            IniParamAssignment("**.vector-recording", "false"; comment=" reduce output"),
        ]),
        IniSection("PureAloha1", [
            IniConfigOption("description", "\"low traffic, 10 hosts\""),
            IniConfigOption("extends", "General"),
            IniParamAssignment("Aloha.numHosts", "10"),
            IniParamAssignment("**.host[*].iaTime", "exponential(4s)"),
            IniParamAssignment("**.slotTime", "0"; comment=" pure Aloha"),
        ]),
        IniSection("SlottedAloha1", [
            IniConfigOption("description", "\"slotted variant, 20 hosts\""),
            IniConfigOption("extends", "General"),
            IniParamAssignment("Aloha.numHosts", "20"),
            IniParamAssignment("**.host[*].iaTime", "exponential(3s)"),
            IniParamAssignment("**.slotTime", "40ms"),
        ]),
        IniSection("ParameterStudy", [
            IniConfigOption("description", "\"sweep hosts and inter-arrival mean\""),
            IniConfigOption("extends", "General"),
            IniParamAssignment("Aloha.numHosts", "\${numHosts=10,15,20,30}"),
            IniParamAssignment("**.host[*].iaTime", "exponential(\${iaMean=1,2,4,8}s)"),
            IniComment(" constraint: keep offered load below 2"),
            IniConfigOption("constraint", "\$numHosts / \$iaMean < 2"),
            IniInsertion(),
        ]),
    ])
end
