VERSION    ?= 1.0.0
TAG        := v$(VERSION)
REPO       := posalex/ClaudeUsage
TAP_REPO   := posalex/homebrew-tap
CASK_PATH  := Casks/claude-usage.rb

.PHONY: build run clean release update-tap install reinstall

# ---------- Local development ----------

build:
	xcodegen generate
	xcodebuild -project ClaudeUsage.xcodeproj \
		-scheme ClaudeUsage \
		-configuration Release \
		-derivedDataPath build \
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
	@echo "==> Pushing commits..."
	git push origin main
	@echo "==> Deleting old tag/release $(TAG)..."
	-git tag -d $(TAG) 2>/dev/null
	-git push --delete origin $(TAG) 2>/dev/null
	-gh release delete $(TAG) --repo $(REPO) --yes 2>/dev/null
	@echo "==> Tagging $(TAG)..."
	git tag $(TAG)
	git push origin $(TAG)
	@echo "==> Waiting for release build..."
	@RUN_ID=$$(sleep 2 && gh run list --repo $(REPO) --limit 1 --json databaseId --jq '.[0].databaseId') && \
		echo "==> Watching run $$RUN_ID..." && \
		gh run watch $$RUN_ID --repo $(REPO) && \
		echo "==> Release build complete."
	@$(MAKE) update-tap

define CASK_TEMPLATE
cask "claude-usage" do
  version "CASK_VERSION"
  sha256 "CASK_SHA"

  url "https://github.com/CASK_REPO/releases/download/vCASK_URL_VERSION/ClaudeUsage.zip"
  name "Claude Usage"
  desc "macOS menu bar widget showing claude.ai subscription usage and rate limits"
  homepage "https://github.com/CASK_REPO"

  depends_on macos: ">= :ventura"

  app "ClaudeUsage.app"

  caveats <<~EOS
    The app is not notarized. macOS will block it on first launch.
    Run this to allow it:
      xattr -d com.apple.quarantine /Applications/ClaudeUsage.app
  EOS

  zap trash: [
    "~/Library/Preferences/com.github.posalex.claudeusage.plist",
    "~/Library/Application Support/ClaudeUsage",
  ]
end
endef
export CASK_TEMPLATE

update-tap:
	@echo "==> Fetching SHA256 from release..."
	@NEW_SHA=$$(gh release view $(TAG) --repo $(REPO) --json assets --jq '.assets[0].digest' | sed 's/sha256://') && \
	FILE_SHA=$$(gh api repos/$(TAP_REPO)/contents/$(CASK_PATH) --jq '.sha') && \
	CONTENT=$$(echo "$$CASK_TEMPLATE" | sed "s/CASK_VERSION/$(VERSION)/;s/CASK_SHA/$$NEW_SHA/;s|CASK_REPO|$(REPO)|g;s/CASK_URL_VERSION/#{version}/" | base64) && \
	gh api repos/$(TAP_REPO)/contents/$(CASK_PATH) \
		-X PUT \
		-f message="Update cask to $(TAG)" \
		-f content="$$CONTENT" \
		-f sha="$$FILE_SHA" \
		--jq '.commit.sha' && \
	echo "==> Tap updated with SHA $$NEW_SHA"

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
