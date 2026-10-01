# An `Appearance` with the widget theme, at a font scale of 1.25: the natural
# renderer draws it as the appearance tab.
function make_appearance_document_example()
    appearance = Appearance(font_scale = 1.25)
    set_theme!(appearance, WidgetTheme())
    appearance
end
