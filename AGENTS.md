# Agent Instructions

Consult BLUEPRINT.md for development blueprint, or SPEC.md!

## Commenting in MATLAB Files
- keep comments in lowercase, with uppercase allowed only for abbreviations (e.g., `ACC`).
- structure every function into clear sections, each preceded by a section comment (multiple sentences if necessary) that walks the reader through the next block of logic. most functions will have several sections; very small helpers may only need one.
- it is quite alright if a section comment requires multiple lines. really make sure you tell the user about why you're writing a section if it's not totally clear. this usually requires multiple lines of a comment (in sentence form) to get right. this will not be more than 1/3 of all comments though.
- add concise in-section comments when a line or two needs extra context, but avoid restating the code.
- do not over-comment and skip obvious remarks; focus on intent, preconditions, and tricky details.
- keep comments informal yet helpful.

## Testing
Use this exact command to run the test suite:
./scripts/run_matlab_tests.sh
