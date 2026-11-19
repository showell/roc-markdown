## **THE SPECS' PLATFORM**: what package/Specs.roc names, so the specs are
## an app of their own. Roc's checker (roc-types, behind shale's typed
## recipes) reads an app, and a type module only through one. It asks for a
## `Str` and hands it to no host: the specs are run by `roc test`, never
## built. (roc-chat's platform/specs.roc's shape.)
##
## The judge's platform is judge/platform/main.roc, the playground's
## playground/platform/main.roc.
platform ""
	requires {
		main : Str
	}
	exposes []
	packages {}
	provides { "specs_main": main_for_host }

main_for_host : Str
main_for_host = main
