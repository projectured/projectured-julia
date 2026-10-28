"""
    ProjecturedBuild

The package of the binary `projectured`. It loads every package that the binary
holds, both backends included, and its workload runs what a person does in the
binary: the gestures of the application window and a file of each format, and
the window again on SDL. A build writes a small package with the values of that
one build, the build record, the log level and the usage text, which loads this
one. So the calls that the binary records have a folder under version control,
`precompile/`, as documentation/design/compile-ahead.md says.
"""
module ProjecturedBuild

using ProjecturedPlatform
import ProjecturedSDL
import ProjecturedWeb
import ProjecturedOllama
import ProjecturedAnthropic
import ProjecturedMCP
import ProjecturedACP
import ProjecturedLanguageServer
import ProjecturedConsole
import ProjecturedPDF
import ProjecturedJSON
import ProjecturedYAML
import ProjecturedXML
import ProjecturedMarkdown
import ProjecturedRST
import ProjecturedBook
import ProjecturedMath
import ProjecturedJulia
import ProjecturedSQL
import ProjecturedDatabase
import ProjecturedGraph
import ProjecturedChart
import ProjecturedSequenceChart
import ProjecturedDBCatalog
import ProjecturedFormula
import ProjecturedFSM
import ProjecturedProcess
import ProjecturedPivot
import ProjecturedWorkflow
import ProjecturedResearch

# The workload of the binary. It runs after every package of the binary loads,
# so the image holds again what a package loaded later made invalid below it.
using ProjecturedPrecompile: @compile_ahead
@compile_ahead begin
    ProjecturedPlatform.warm_application()
    ProjecturedSDL.run_sdl_window_workload()
end

end # module ProjecturedBuild
