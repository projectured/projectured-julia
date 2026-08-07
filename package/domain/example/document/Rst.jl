# Atomic RST leaves — one meaningful instance each, for the catalog.
function make_rst_text_document_example()
    RstText("Frame replication")
end

make_rst_literal_document_example()     = RstLiteral("inet.queueing")
make_rst_transition_document_example()  = RstTransition()
make_rst_comment_document_example()     = RstComment("not part of the output")
make_rst_target_document_example()      = RstTarget("ug:cha:queueing")
make_rst_insertion_document_example()   = RstInsertion()
make_rst_math_block_document_example()  = RstMathBlock("E = mc^2")

# Minimal non-empty compound (node) documents — one child each, for the catalog.
make_rst_role_document_example()        = RstRole("ned", "ActivePacketSource")
make_rst_reference_document_example()   = RstReference("INET", "https://inet.omnetpp.org")
make_rst_substitution_reference_document_example() = RstSubstitutionReference("version")
make_rst_footnote_reference_document_example()     = RstFootnoteReference("1")
make_rst_emphasis_document_example()    = RstEmphasis([RstText("x")])
make_rst_strong_document_example()      = RstStrong([RstText("x")])
make_rst_paragraph_document_example()   = RstParagraph([RstText("x")])
make_rst_literal_block_document_example() = RstLiteralBlock("a = 1")
make_rst_line_block_document_example()  = RstLineBlock([RstParagraph([RstText("x")])])
make_rst_list_item_document_example()   = RstListItem([RstParagraph([RstText("x")])])
make_rst_bullet_list_document_example() = RstBulletList("-", [RstListItem([RstParagraph([RstText("x")])])])
make_rst_enumerated_list_document_example() = RstEnumeratedList("1.", [RstListItem([RstParagraph([RstText("x")])])])
make_rst_definition_item_document_example() = RstDefinitionItem([RstText("term")]; elements = [RstParagraph([RstText("x")])])
make_rst_definition_list_document_example() = RstDefinitionList([make_rst_definition_item_document_example()])
make_rst_field_document_example()       = RstField("author", [RstParagraph([RstText("x")])])
make_rst_field_list_document_example()  = RstFieldList([make_rst_field_document_example()])
make_rst_block_quote_document_example() = RstBlockQuote([RstParagraph([RstText("x")])])
make_rst_footnote_document_example()    = RstFootnote("1", [RstParagraph([RstText("x")])])
make_rst_substitution_definition_document_example() = RstSubstitutionDefinition("logo", RstImage("logo.png"))
make_rst_table_cell_document_example()  = RstTableCell([RstParagraph([RstText("x")])])
make_rst_table_row_document_example()   = RstTableRow([make_rst_table_cell_document_example()])
make_rst_grid_table_document_example()  = RstGridTable(0, [make_rst_table_row_document_example()])
make_rst_directive_option_document_example() = RstDirectiveOption("language", "ini")
make_rst_literal_include_document_example()  = RstLiteralInclude("../omnetpp.ini", "ini")
make_rst_figure_document_example()      = RstFigure("media/Network.png"; align = "center")
make_rst_code_block_document_example()  = RstCodeBlock("ini", "*.host.numApps = 1")
make_rst_image_document_example()       = RstImage("media/Network.png")
make_rst_video_document_example()       = RstVideo("media/step14.mp4")
make_rst_audio_document_example()       = RstAudio("media/beep.wav")
make_rst_admonition_document_example()  = RstAdmonition("note", [RstParagraph([RstText("x")])])
make_rst_toctree_document_example()     = RstToctree([RstText("tsn/index")]; maxdepth = 1)
make_rst_raw_block_document_example()   = RstRawBlock("latex", "\\newpage")
make_rst_role_definition_document_example() = RstRoleDefinition("par", "code")
make_rst_directive_document_example()   = RstDirective("only", "html"; elements = [RstParagraph([RstText("x")])])
make_rst_section_document_example()     = RstSection(1, "=", [RstText("Title")]; elements = [RstParagraph([RstText("x")])])
make_rst_root_document_example()        = RstRoot([RstParagraph([RstText("x")])])

# A whole page, built after the INET showcase pages: a section tree, prose with
# roles and inline literals, a bullet and an enumerated list, a figure, a code
# block, a literalinclude, a note, and a toctree.
function make_rst_document_example()
    RstRoot([
        RstSection(1, "=", [RstText("Manual Stream Configuration")]; elements = [
            RstParagraph([
                RstText("This showcase demonstrates the "),
                RstStrong([RstText("Frame Replication and Elimination for Reliability")]),
                RstText(" mechanism of "),
                RstReference("IEEE 802.1CB", "https://standards.ieee.org/standard/802_1CB-2017.html"),
                RstText("."),
            ]),
            RstSection(2, "-", [RstText("Goals")]; elements = [
                RstParagraph([
                    RstText("The network sends a stream through the "),
                    RstRole("ned", "StreamSplitter"),
                    RstText(" module and merges it again with "),
                    RstRole("ned", "StreamMerger"),
                    RstText(". The relevant setting is "),
                    RstLiteral("*.hasStreamRedundancy = true"),
                    RstText("."),
                ]),
                RstBulletList("-", [
                    RstListItem([RstParagraph([
                        RstStrong([RstText("source")]),
                        RstText(": generates a UDP data stream"),
                    ])]),
                    RstListItem([RstParagraph([
                        RstStrong([RstText("destination")]),
                        RstText(": eliminates the duplicate frames"),
                    ])]),
                ]),
                RstEnumeratedList("1.", [
                    RstListItem([RstParagraph([RstText("Replicate the frames at the source.")])]),
                    RstListItem([RstParagraph([RstText("Eliminate the duplicates at the merge point.")])]),
                ]),
            ]),
            RstSection(2, "-", [RstText("The Model")]; elements = [
                # A path that exists relative to the repository root, so the
                # rendered example draws a real picture when the editor is
                # started there. A path that does not resolve degrades to the
                # path as text, which is what a figure in a real showcase
                # (`media/Network.png`) does until the loader seam lands.
                RstFigure("asset/image/projectured.png"; align = "center",
                          caption = [RstParagraph([RstText("The network of the showcase")])]),
                RstCodeBlock("ini", "*.source.numApps = 1\n*.source.app[0].typename = \"UdpSourceApp\""),
                RstLiteralInclude("../omnetpp.ini", "ini",
                                  "*.scenarioManager.script", "</script>"),
                RstAdmonition("note", [RstParagraph([
                    RstText("The simulation needs the "),
                    RstRole("par", "hasStreamRedundancy"),
                    RstText(" parameter."),
                ])]),
                RstTransition(),
                RstToctree([RstText("manualconfiguration/doc/index"),
                            RstText("automaticconfiguration/doc/index")]; maxdepth = 1),
            ]),
        ]),
    ])
end
