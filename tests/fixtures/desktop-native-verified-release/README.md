# Immutable Desktop release evidence

Files in each formal release directory are original published or release-run bytes. The deployment lock binds their raw hashes; JSON-equivalent text with different line endings is not equivalent evidence.

The scoped `.gitattributes` disables text conversion for this tree. Do not normalize, format, or regenerate old evidence files to accommodate a Windows checkout, and do not replace expected hashes with hashes of converted text. Add a new directory for a new independently verified formal release.

`tests/repository-content.test.mjs` exercises a real Git checkout with `core.autocrlf=true`: protected evidence must retain the locked hash, while an unprotected control must differ. The native release verifier remains unchanged and must reject altered bytes.

Rehearsal artifacts, synthetic test inputs, source builds and installed-machine observations have separate evidence scopes. None may be relabeled as formal published release evidence.
