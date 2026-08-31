#!/usr/bin/env python3
"""Repair the sibling repositories after projectured-julia's package/ flattened.

`plan/pending/repository-tree.md` step 6. omnet-julia and inet-julia reach into
this repository by relative path, and every one of those paths named
`package/<slice>/<kind>`, which no longer exists. Run this the hour the branch
lands on `main`, and land all three together: between the two commits neither
sibling resolves.

    python3 tool/repair-sibling-sources.py            # say what would change
    python3 tool/repair-sibling-sources.py --apply

Delete this file once the siblings have landed. It describes a move, and a move
happens once.
"""
import os, re, sys

SIBLINGS = ("../omnet-julia", "../inet-julia")
DRY = "--apply" not in sys.argv

# Every package directory of this repository, before and after.
MOVED = {
    "bench": "package/ProjecturedBench",
    "package/adaptagrams/example": "package/ProjecturedAdaptagramsExample",
    "package/adaptagrams/main": "package/ProjecturedAdaptagrams",
    "package/assistant/main": "package/ProjecturedAssistant",
    "package/book/example": "package/ProjecturedBookExample",
    "package/book/main": "package/ProjecturedBook",
    "package/book/test": "package/ProjecturedBookTest",
    "package/chart/example": "package/ProjecturedChartExample",
    "package/chart/main": "package/ProjecturedChart",
    "package/chart/test": "package/ProjecturedChartTest",
    "package/clipboard/main": "package/ProjecturedClipboard",
    "package/collection/main": "package/ProjecturedCollection",
    "package/component/main": "package/ProjecturedComponent",
    "package/console/main": "package/ProjecturedConsole",
    "package/conversation/example": "package/ProjecturedConversationExample",
    "package/conversation/main": "package/ProjecturedConversation",
    "package/conversation/test": "package/ProjecturedConversationTest",
    "package/database/example": "package/ProjecturedDatabaseExample",
    "package/database/main": "package/ProjecturedDatabase",
    "package/database/test": "package/ProjecturedDatabaseTest",
    "package/dbcatalog/example": "package/ProjecturedDbCatalogExample",
    "package/dbcatalog/main": "package/ProjecturedDbCatalog",
    "package/dbcatalog/test": "package/ProjecturedDbCatalogTest",
    "package/domain/main": "package/ProjecturedDomain",
    "package/dragging/main": "package/ProjecturedDragging",
    "package/executable/builder": "package/ProjecturedBuilder",
    "package/executable/main": "package/ProjecturedExecutable",
    "package/fileformat/main": "package/ProjecturedFileFormat",
    "package/filesystem/example": "package/ProjecturedFileSystemExample",
    "package/filesystem/main": "package/ProjecturedFileSystem",
    "package/filesystem/test": "package/ProjecturedFileSystemTest",
    "package/focus/main": "package/ProjecturedFocus",
    "package/formula/example": "package/ProjecturedFormulaExample",
    "package/formula/main": "package/ProjecturedFormula",
    "package/formula/test": "package/ProjecturedFormulaTest",
    "package/fsm/example": "package/ProjecturedFsmExample",
    "package/fsm/main": "package/ProjecturedFsm",
    "package/fsm/test": "package/ProjecturedFsmTest",
    "package/gesturehelp/main": "package/ProjecturedGestureHelp",
    "package/gesturelog/main": "package/ProjecturedGestureLog",
    "package/graph/example": "package/ProjecturedGraphExample",
    "package/graph/main": "package/ProjecturedGraph",
    "package/graph/test": "package/ProjecturedGraphTest",
    "package/graphics/main": "package/ProjecturedGraphics",
    "package/inspector/main": "package/ProjecturedInspector",
    "package/json/example": "package/ProjecturedJsonExample",
    "package/json/main": "package/ProjecturedJson",
    "package/json/test": "package/ProjecturedJsonTest",
    "package/julia/example": "package/ProjecturedJuliaExample",
    "package/julia/main": "package/ProjecturedJulia",
    "package/julia/test": "package/ProjecturedJuliaTest",
    "package/kernel/example": "package/ProjecturedKernelExample",
    "package/kernel/main": "package/ProjecturedKernel",
    "package/kernel/test": "package/ProjecturedKernelTest",
    "package/layout/main": "package/ProjecturedLayout",
    "package/llm/main": "package/ProjecturedLlm",
    "package/markdown/example": "package/ProjecturedMarkdownExample",
    "package/markdown/main": "package/ProjecturedMarkdown",
    "package/markdown/test": "package/ProjecturedMarkdownTest",
    "package/math/example": "package/ProjecturedMathExample",
    "package/math/main": "package/ProjecturedMath",
    "package/math/test": "package/ProjecturedMathTest",
    "package/mcp/main": "package/ProjecturedMcp",
    "package/natural/main": "package/ProjecturedNatural",
    "package/odbc/example": "package/ProjecturedOdbcExample",
    "package/odbc/main": "package/ProjecturedOdbc",
    "package/odbc/test": "package/ProjecturedOdbcTest",
    "package/pane/main": "package/ProjecturedPane",
    "package/pdf/main": "package/ProjecturedPdf",
    "package/plot/main": "package/ProjecturedPlot",
    "package/primitive/main": "package/ProjecturedPrimitive",
    "package/process/example": "package/ProjecturedProcessExample",
    "package/process/main": "package/ProjecturedProcess",
    "package/process/test": "package/ProjecturedProcessTest",
    "package/projection/main": "package/ProjecturedProjection",
    "package/projectured/example": "package/ProjecturedExample",
    "package/projectured/main": "package/Projectured",
    "package/projectured/test": "package/ProjecturedTest",
    "package/reflection/main": "package/ProjecturedReflection",
    "package/repl": "package/ProjecturedRepl",
    "package/rst/example": "package/ProjecturedRstExample",
    "package/rst/main": "package/ProjecturedRst",
    "package/rst/test": "package/ProjecturedRstTest",
    "package/screen/main": "package/ProjecturedScreen",
    "package/sdl/example": "package/ProjecturedSdlExample",
    "package/sdl/main": "package/ProjecturedSdl",
    "package/sdl/test": "package/ProjecturedSdlTest",
    "package/sequencechart/example": "package/ProjecturedSequenceChartExample",
    "package/sequencechart/main": "package/ProjecturedSequenceChart",
    "package/sequencechart/test": "package/ProjecturedSequenceChartTest",
    "package/serialization/main": "package/ProjecturedSerialization",
    "package/sql/example": "package/ProjecturedSqlExample",
    "package/sql/main": "package/ProjecturedSql",
    "package/sql/test": "package/ProjecturedSqlTest",
    "package/style/main": "package/ProjecturedStyle",
    "package/substrate/example": "package/ProjecturedSubstrateExample",
    "package/substrate/test": "package/ProjecturedSubstrateTest",
    "package/syntax/main": "package/ProjecturedSyntax",
    "package/text/main": "package/ProjecturedText",
    "package/tooltip/main": "package/ProjecturedTooltip",
    "package/tulip/example": "package/ProjecturedTulipExample",
    "package/tulip/main": "package/ProjecturedTulip",
    "package/tulip/test": "package/ProjecturedTulipTest",
    "package/versioning/main": "package/ProjecturedVersioning",
    "package/video/main": "package/ProjecturedVideo",
    "package/video/test": "package/ProjecturedVideoTest",
    "package/web/main": "package/ProjecturedWeb",
    "package/widget/main": "package/ProjecturedWidget",
    "package/workbench/example": "package/ProjecturedWorkbenchExample",
    "package/workbench/main": "package/ProjecturedWorkbench",
    "package/workbench/test": "package/ProjecturedWorkbenchTest",
    "package/xml/example": "package/ProjecturedXmlExample",
    "package/xml/main": "package/ProjecturedXml",
    "package/xml/test": "package/ProjecturedXmlTest",
    "package/yaml/example": "package/ProjecturedYamlExample",
    "package/yaml/main": "package/ProjecturedYaml",
    "package/yaml/test": "package/ProjecturedYamlTest",
}


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pattern = re.compile(
        r"(projectured-julia/)(" + "|".join(re.escape(k) for k in sorted(MOVED, key=len, reverse=True)) + r")\b")
    total = 0
    for sibling in SIBLINGS:
        root = os.path.normpath(os.path.join(here, sibling))
        if not os.path.isdir(root):
            print(f"{sibling}: not a directory beside this one — skipped")
            continue
        touched = 0
        for d, dirs, files in os.walk(root):
            dirs[:] = [x for x in dirs if x != ".git"]
            for f in files:
                if f not in ("Project.toml", "Manifest.toml"):
                    continue
                p = os.path.join(d, f)
                text = open(p).read()
                new = pattern.sub(lambda m: m.group(1) + MOVED[m.group(2)], text)
                if new == text:
                    continue
                touched += 1
                total += len(pattern.findall(text))
                if not DRY:
                    open(p, "w").write(new)
                else:
                    print("   ", os.path.relpath(p, root))
        print(f"{sibling}: {touched} project files")
    print(f"{total} path entries {'would be' if DRY else ''} rewritten")
    if DRY:
        print("dry run — pass --apply to write")


main()
