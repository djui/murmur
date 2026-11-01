.PHONY: help icons generate test build run install dmg release testflight clean

help:
	@echo "make icons           Render the app icon into Murmur/Assets.xcassets"
	@echo "make generate        Generate Murmur.xcodeproj (XcodeGen)"
	@echo "make test            Run MurmurCore unit tests"
	@echo "make build           Release build -> build/Murmur.app"
	@echo "make run             Debug build and launch"
	@echo "make install         Build, install to /Applications and restart"
	@echo "make dmg             Build build/Murmur-<version>.dmg"
	@echo "make release [PART=patch|minor|major] [NOTES='...']"
	@echo "make testflight      Archive the iOS app and upload it to TestFlight"

icons:
	swift scripts/make_icons.swift

generate:
	xcodegen generate

test:
	swift test --package-path Packages/MurmurCore

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

testflight:
	scripts/testflight.sh

clean:
	rm -rf build dist Murmur.xcodeproj Packages/MurmurCore/.build
