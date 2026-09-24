# The forms that a video types into the evaluator each become a Julia document, so
# that each is drawn with the colours of the Julia notation. A script checks its
# forms before its take.

"""
    check_julia_forms(forms)

Stop with the list of the forms that would stay strings in the evaluator.
"""
function check_julia_forms(forms)
    plain = filter(form -> find_form_document(form) === nothing, forms)
    isempty(plain) || error("these forms would stay strings in the evaluator:\n  " * join(plain, "\n  "))
    nothing
end
