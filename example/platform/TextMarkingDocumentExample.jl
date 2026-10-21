# A piece of C code whose names are marked in the colours of their kinds, as a
# language server gives them: `main` is a function, and `count` is a variable. A
# key, Enter and a paste edit the string; the marks stay where they are.
function make_text_marking_document_example()
    MarkedText(text = "int main() {\n    int count = 0;\n    return count;\n}",
               marks = [TextMark(4, 8; text = ColorRole(:function_name)),
                        TextMark(21, 26; text = ColorRole(:variable)),
                        TextMark(43, 48; text = ColorRole(:variable))])
end
