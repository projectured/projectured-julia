# The pane projection with a row for a text view: each place prints its view as the
# text that the view shows, with the caret of the view, and draws it.
make_text_view_projection_example(; measure = FontFileMeasure()) =
    make_pane_projection_example(; measure,
        rows = Pair{Type,Any}[TextView => ChainingProjection(TextViewToText(), TextToGraphics(; measure))])
