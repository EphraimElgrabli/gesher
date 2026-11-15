.DEFAULT_GOAL := help
APPS := reminders calendar contacts notes maps weather freeform
.PHONY: help build release test lint format check dist install connect install-plugins uninstall $(APPS:%=run-%)

help:
	@printf 'Usage: make <target> [ARGS="..."]\n\n'
	@printf '  %-16s %s\n' \
	  build           'debug build' \
	  release         'release build' \
	  test            'run all tests' \
	  lint            'swift-format lint --strict; shell syntax; connect.sh tests' \
	  format          'swift-format in place' \
	  check           'lint + test + release (run before every commit)' \
	  dist            'package dist/gesher-<version>-macos-arm64.tar.gz + .sha256' \
	  install         'build and install into ~/.local (scripts/install.sh $$ARGS)' \
	  connect         'connect AI apps to the installed CLIs (scripts/connect.sh $$ARGS)' \
	  install-plugins 'install the Codex plugins (scripts/install-plugins.sh $$ARGS)' \
	  uninstall       'remove the installation (scripts/install.sh --uninstall)' \
	  'run-<app>'     'run a built CLI: make run-weather ARGS="current Haifa"'

build:
	swift build --force-resolved-versions
release:
	swift build -c release --force-resolved-versions
test:
	swift test --force-resolved-versions
lint:
	xcrun swift-format lint --strict --recursive Package.swift core apps
	@for f in install.sh scripts/*.sh scripts/gesher; do bash -n "$$f" || exit 1; done
	@./scripts/test-connect.sh
format:
	xcrun swift-format format --in-place --recursive Package.swift core apps
check: lint test release
dist:
	./scripts/package-release.sh $(ARGS)
install:
	./scripts/install.sh $(ARGS)
connect:
	./scripts/connect.sh $(ARGS)
install-plugins:
	./scripts/install-plugins.sh $(ARGS)
uninstall:
	./scripts/install.sh --uninstall $(ARGS)
$(APPS:%=run-%): run-%:
	swift run --skip-build $*-cli $(ARGS)
