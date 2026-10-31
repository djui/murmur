.PHONY: help icons generate test cli build run install dmg release clean

help:
	@echo "make icons           Render the app icon into Murmur/Assets.xcassets"
	@echo "make generate        Generate Murmur.xcodeproj (XcodeGen)"
	@echo "make test            Run MurmurCore and MurmurEngine unit tests"
	@echo "make cli             Build the murmur command (the Windows sidecar) for this Mac"
	@echo "make build           Release build -> build/Murmur.app"
	@echo "make run             Debug build and launch"
	@echo "make install         Build, install to /Applications and restart"
	@echo "make dmg             Build build/Murmur-<version>.dmg"
	@echo "make release [PART=patch|minor|major] [NOTES='...']"

icons:
	swift scripts/make_icons.swift

generate:
	xcodegen generate

test:
	swift test --package-path Packages/MurmurCore
	swift test --package-path Packages/MurmurEngine

cli:
	swift build --package-path Packages/MurmurEngine -c release --product murmur

build:
	scripts/build_release.sh

run:
	scripts/run_debug.sh

install:
	scripts/install_local.sh

dmg:
	scripts/make_dmg.sh

PART ?= patch
NOTES ?=
release:
	scripts/release.sh $(PART) "$(NOTES)"

clean:
	rm -rf build dist Murmur.xcodeproj Packages/MurmurCore/.build Packages/MurmurEngine/.build
