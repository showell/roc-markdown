## This app is the root of the specs. It imports MdSpec, so
## `roc test package/Specs.roc` (`zig build test`) runs MdSpec's expects and
## every module's own, which MdSpec reaches through Md.
##
## It is an app, on the test-only package/specs_platform.roc, so that shale's
## typed recipes (`rewrite_method_calls`) can read the specs: Roc's checker
## reads an app, and a type module only through one. roc-chat's app/Specs.roc
## is the same root.
app [main] { pf: platform "specs_platform.roc" }

import MdSpec

## Nothing: `roc test` runs the specs, and no host runs this app.
main : Str
main = ""
