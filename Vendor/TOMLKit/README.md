# Local TOMLKit ownership patch

Vendored from LebJe/TOMLKit 0.5.5, revision
`404c4dd011743461bff12d00a5118d0ed59d630c`. The original MIT license and
toml++ license in `Sources/CTOML/Sources/toml.hpp` are retained. The parser
and serialization format are unchanged; this is not an upstream version upgrade.

The original wrapper never destroyed native roots or freed C result buffers.
Local changes add a shared native-root owner, retain it in nested table/array/value
views, and release copied getter/formatting/key/value/error buffers. Date-time
offsets use scoped input storage and matching native cleanup. An unused invalid
date-time cast in `nodeType` was removed. The package manifest excludes upstream
documentation/test-only dependencies.

Nested views retain their document without copying subtrees. Replacing/removing
a node invalidates existing views of that node; concurrent mutation is unsupported.
The result returned by `remove` is an independent owned copy.

Ownership regressions run in the root `make check`. For isolated native leak checks:

```sh
swift build --package-path Vendor/TOMLKit -c release --product TOMLLeakProbe
leaks --atExit -- Vendor/TOMLKit/.build/release/TOMLLeakProbe
# Optional longer stress run (default is 1,000 cycles):
leaks --atExit -- Vendor/TOMLKit/.build/release/TOMLLeakProbe 100000
```

The fixture only uses synthetic TOML and does not open native windows or read/write
user configuration. Its repeated parse/read/encode/error cycles exercise C buffers
that Swift weak-reference tests alone cannot check.
