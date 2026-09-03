VERSION    ?= 1.1.4
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
		CODE_SIGN_IDENTITY=- \
		CODE_SIGN_STYLE=Manual \
		build

run:
	xcodegen generate
	xcodebuild -project ClaudeUsage.xcodeproj \
		-scheme ClaudeUsage \
		-configuration Debug \
		-derivedDataPath build \
		CODE_SIGN_IDENTITY=- \
		CODE_SIGN_STYLE=Manual \
		build
	open build/Build/Products/Debug/ClaudeUsage.app

clean:
	rm -rf build ClaudeUsage.xcodeproj

# ---------- Release ----------

release:
	./scripts/release.sh $(VERSION)

update-tap:
	"$(TAP_DIR)/scripts/publish-claude-usage-cask.sh" $(VERSION)

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
