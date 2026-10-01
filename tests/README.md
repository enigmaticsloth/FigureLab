# WebKit regressions

These tests use the same WebKit engine as the macOS application, including its
native TIFF decoder. Each run uses an isolated, nonpersistent website data store;
it does not read or modify the running application's autosave.

Compile the runner (adjust the SDK path if needed):

```sh
swiftc -module-cache-path /tmp/figurelab-swift-cache tests/webkit-runner.swift -o /tmp/figurelab-webkit-runner
mkdir -p artifacts
```

Run the supplied Fig.1 project regression with absolute paths:

```sh
/tmp/figurelab-webkit-runner /path/to/figure-editor.html /path/to/Fig.1.json /path/to/tests/editor-regression.js /path/to/artifacts
```

This exercises the reported 1024-pixel canvas fixture: text spaces and IME,
undo, retained SVG nodes during movement, multi-selection resize, exact and
detail-preserving export dimensions, original TIFF decoding, and autosave/restore
of the large project. It writes high-resolution PNG and TIFF examples to the
output directory. Generated scientific data is ignored by Git.

Use `render-regression.js` in place of `editor-regression.js` for generated shape
fixtures covering rotation, opacity, line and arrow styling, paths, text, layer
order, transparency, and preservation of imports larger than 5000 pixels. The
project argument can be `-` for suites that generate their own fixtures.

Use `project-regression.js` with project argument `-` to test editable PNG
save/reopen, original images, groups and hidden layers, multiple tabs, snapshot
consistency during an asynchronous save, old JSON compatibility, PNG corruption
checks, and the uncompressed fallback. This suite also performs full page reloads
with IndexedDB and legacy backups present: startup stays blank, the backup is
preserved, and explicit recovery still works. It writes a generated sample
`editable-project.sloth` suitable for testing Finder Quick Look after registering
the updated macOS app. It also tests `.sloth` saves, drop events without a MIME
type, the native Finder-open bridge, and compatibility with `.figurelab.png`.

The tests need a macOS graphical session. All test windows and data stores are
owned by the runner, which exits after reporting success or failure.
