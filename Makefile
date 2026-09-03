VERSION    ?= 1.1.0
TAG        := v$(VERSION)
REPO       := posalex/ClaudeUsage
CASK_PATH  := Casks/claude-usage.rb
TAP_DIR    ?= ../homebrew-tap
TAP_CASK   := $(TAP_DIR)/$(CASK_PATH)

.PHONY: build run clean release update-tap install reinstall

# ---------- Local development ----------

build:
	xcodegen generate
	xcodebuild -project ClaudeUsage.xcodeproj \
		-scheme ClaudeUsage \
		-configuration Release \
		-derivedDataPath build \
		ARCHS=arm64 \
		ONLY_ACTIVE_ARCH=YES \
		build

run:
	xcodegen generate
	xcodebuild -project ClaudeUsage.xcodeproj \
		-scheme ClaudeUsage \
		-configuration Debug \
		-derivedDataPath build \
		build
	open build/Build/Products/Debug/ClaudeUsage.app

clean:
	rm -rf build ClaudeUsage.xcodeproj

# ---------- Release ----------

release: clean
	@test "$$(git branch --show-current)" = "main" || (echo "Release must run from main"; exit 1)
	@test -z "$$(git status --porcelain)" || (echo "Working tree is not clean"; exit 1)
	@test -z "$$(git tag -l $(TAG))" || (echo "Tag $(TAG) already exists"; exit 1)
	@echo "==> Pushing main..."
	git push origin main
	@echo "==> Tagging $(TAG)..."
	git tag -a $(TAG) -m "Release $(VERSION)"
	git push origin $(TAG)
	@echo "==> Release build started on GitHub. Run 'make update-tap VERSION=$(VERSION)' after its asset is available."

update-tap:
	@test -f "$(TAP_CASK)" || (echo "Tap cask not found: $(TAP_CASK)"; exit 1)
	@TMP_DIR=$$(mktemp -d) && trap 'rm -rf "$$TMP_DIR"' EXIT && \
		curl --fail --location --output "$$TMP_DIR/ClaudeUsage.zip" "https://github.com/$(REPO)/releases/download/$(TAG)/ClaudeUsage.zip" && \
		NEW_SHA=$$(shasum -a 256 "$$TMP_DIR/ClaudeUsage.zip" | awk '{print $$1}') && \
		perl -0pi -e "s/version \"[^\"]+\"/version \"$(VERSION)\"/; s/sha256 \"[^\"]+\"/sha256 \"$$NEW_SHA\"/" "$(TAP_CASK)" && \
		brew audit --cask --strict "$(TAP_CASK)" && \
		git -C "$(TAP_DIR)" add "$(CASK_PATH)" && \
		git -C "$(TAP_DIR)" commit -m "Update claude-usage to $(TAG)" && \
		git -C "$(TAP_DIR)" push origin HEAD

# ---------- Homebrew install ----------

install:
	brew tap posalex/tap
	brew install --cask claude-usage
	xattr -d com.apple.quarantine /Applications/ClaudeUsage.app

reinstall:
	-brew untap posalex/tap
	brew tap posalex/tap
	brew reinstall --cask claude-usage
	xattr -d com.apple.quarantine /Applications/ClaudeUsage.app
