# Which Xcode every xcodebuild call below runs against. Not hardcoded to
# /Applications/Xcode.app because `xcodes` installs version-suffixed bundles
# (/Applications/Xcode-26.6.0.app) and a fixed path resolves to nothing on a
# machine set up that way — xcodebuild then dies with "unable to find utility",
# which reads like a broken toolchain rather than a wrong path.
#
# An active `xcode-select -p` wins, so switching toolchains needs no edit here.
# A bare Command Line Tools path does not count: it has no xcodebuild that can
# build a scheme. Failing that, the newest bundle in /Applications is picked,
# with the unsuffixed Xcode.app preferred as the one someone chose to install
# under the canonical name.
#
# The `(` opening each case pattern is load-bearing: make counts parentheses
# inside $(shell ...), and an unbalanced `)` ends the function mid-command.
DEVELOPER_DIR ?= $(shell \
	active=$$(xcode-select -p 2>/dev/null); \
	case "$$active" in (*.app/Contents/Developer) echo "$$active"; exit 0;; esac; \
	for app in /Applications/Xcode.app $$(ls -d /Applications/Xcode-*.app 2>/dev/null | sort -rV); do \
		[ -d "$$app/Contents/Developer" ] && { echo "$$app/Contents/Developer"; exit 0; }; \
	done)
# Skipped entirely when nothing was found: an empty DEVELOPER_DIR in the
# environment is worse than none, since /usr/bin/xcodebuild is an xcrun shim
# that refuses to start on an invalid path. The `:=` freezes the probe so it
# runs once per make, not once per recipe, and an environment or command-line
# DEVELOPER_DIR passes through untouched.
ifneq ($(DEVELOPER_DIR),)
export DEVELOPER_DIR := $(DEVELOPER_DIR)
endif

PROJECT := Codenotch.xcodeproj
SCHEME  := Codenotch
DEST    := platform=macOS,arch=arm64

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug test

run: build
	@APP=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Debug -showBuildSettings 2>/dev/null \
		| awk -F' = ' '/ BUILT_PRODUCTS_DIR/ {print $$2; exit}')/Codenotch.app; \
	pkill -x Codenotch || true; \
	open "$$APP"

clean:
	rm -rf build DerivedData $(PROJECT)

# --- Release -----------------------------------------------------------------
# The path to a notarized .dmg. Run `make release` for the whole thing, or the
# steps one at a time while something is going wrong.
#
# One-time setup, which you have to run yourself because it takes a password:
#
#   xcrun notarytool store-credentials UsageNotch \
#       --apple-id <your-apple-id> --team-id 6WFPL8B9FB --password <app-specific-password>
#
# The app-specific password comes from appleid.apple.com → Sign-In and Security
# → App-Specific Passwords. Not your Apple ID password.

RELEASE_DIR := build/release
APP_NAME    := Codenotch
# The label of the stored notarytool credential in the login keychain, not
# anything to do with the app's name — it was created before the rename and
# renaming the variable is what broke `make release` after it. Recreating it
# needs an app-specific password, so the label simply stays as it is.
NOTARY_PROFILE := UsageNotch
DMG := $(RELEASE_DIR)/$(APP_NAME).dmg

.PHONY: archive dmg notarize release verify-release

# Release configuration, exported with the Developer ID identity. `xcodebuild
# archive` + `-exportArchive` rather than a plain build: it re-signs the bundle
# as a distributable, which a Debug build is not.
archive: gen
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	@# Spotlight indexes build output as installed applications, so every
	@# release leaves extra "Codenotch" entries in app search next to the
	@# real one in /Applications. This stops the whole tree being indexed.
	@touch build/.metadata_never_index
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Release -archivePath $(RELEASE_DIR)/$(APP_NAME).xcarchive archive
	printf '%s\n' \
		'<?xml version="1.0" encoding="UTF-8"?>' \
		'<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
		'<plist version="1.0"><dict>' \
		'<key>method</key><string>developer-id</string>' \
		'<key>teamID</key><string>6WFPL8B9FB</string>' \
		'<key>signingStyle</key><string>manual</string>' \
		'<key>signingCertificate</key><string>Developer ID Application</string>' \
		'</dict></plist>' > $(RELEASE_DIR)/ExportOptions.plist
	xcodebuild -exportArchive \
		-archivePath $(RELEASE_DIR)/$(APP_NAME).xcarchive \
		-exportOptionsPlist $(RELEASE_DIR)/ExportOptions.plist \
		-exportPath $(RELEASE_DIR)

# A plain drag-to-Applications disk image. `hdiutil` writes it read-only and
# compressed, which is what notarization expects.
dmg: archive
	rm -f $(DMG)
	rm -rf $(RELEASE_DIR)/stage
	mkdir -p $(RELEASE_DIR)/stage
	cp -R $(RELEASE_DIR)/$(APP_NAME).app $(RELEASE_DIR)/stage/
	ln -s /Applications $(RELEASE_DIR)/stage/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(RELEASE_DIR)/stage \
		-ov -format UDZO $(DMG)
	codesign --force --sign "Developer ID Application" --timestamp $(DMG)
	@# The app is inside the dmg now. Leaving the loose copies around is how
	@# three spare "Codenotch" entries end up in Spotlight; everything
	@# downstream (notarize, verify, appcast) works from the dmg alone.
	rm -rf $(RELEASE_DIR)/stage $(RELEASE_DIR)/$(APP_NAME).app

# Submits and waits. `--wait` blocks until Apple answers, which is usually a
# couple of minutes; on rejection, the log says which binary failed and why.
notarize: dmg
	xcrun notarytool submit $(DMG) --keychain-profile $(NOTARY_PROFILE) --wait
	xcrun stapler staple $(DMG)

# Sparkle ships its tools inside the resolved package artifacts.
SPARKLE_BIN = $(shell dirname $$(find $$HOME/Library/Developer/Xcode/DerivedData/Codenotch-*/SourcePackages/artifacts/sparkle -name generate_appcast 2>/dev/null | head -1))

# The feed customers' copies poll. Signs each update with the EdDSA private key
# in the login keychain — Sparkle installs nothing that key did not sign, so a
# compromised host cannot push code.
#
# Writes into docs/, which GitHub Pages serves. The dmg goes there too, so the
# URL the appcast advertises is the one the file actually sits at — a mismatch
# is the usual reason an update downloads and then fails to verify.
# NOT docs/ — that holds the design frames and specs, and GitHub Pages serves
# whatever it is pointed at. Publishing from there would put the whole design
# history on the public web alongside the download.
PAGES_DIR := site
# Where the dmg actually sits. The enclosure URL the appcast advertises has to
# match it exactly, or an update downloads and then fails to verify.
DOWNLOAD_PREFIX := https://hivinz.com/

appcast: $(DMG)
	@test -n "$(SPARKLE_BIN)" || (echo "Sparkle tools not found — run make build first" && exit 1)
	mkdir -p $(PAGES_DIR)
	@# Rebuilt from what is actually in the folder, never merged into the old
	@# one. The dmg keeps a constant name, so only one build can exist at a
	@# time — but generate_appcast preserves entries it already knows, and left
	@# the previous version advertised at a URL now serving a different file,
	@# with a signature that could never verify.
	rm -f $(PAGES_DIR)/appcast.xml
	cp $(DMG) $(PAGES_DIR)/
	$(SPARKLE_BIN)/generate_appcast $(PAGES_DIR) --download-url-prefix $(DOWNLOAD_PREFIX)
	@echo "Publish by committing $(PAGES_DIR)/ and pushing."

release: notarize verify-release appcast
	@echo "Notarized: $(DMG)"

# What Gatekeeper on a customer's Mac will check. `spctl` accepting the app is
# the actual proof that the download will open without a right-click.
verify-release:
	xcrun stapler validate $(DMG)
	hdiutil attach $(DMG) -nobrowse -mountpoint $(RELEASE_DIR)/mnt
	codesign --verify --deep --strict --verbose=2 $(RELEASE_DIR)/mnt/$(APP_NAME).app
	spctl --assess --type execute --verbose=4 $(RELEASE_DIR)/mnt/$(APP_NAME).app
	hdiutil detach $(RELEASE_DIR)/mnt

# --- Local install -----------------------------------------------------------
# `make install-local` puts a build in /Applications on this machine. It is not
# the release path and produces nothing shippable: no Developer ID, no Apple
# notarization, so the result is an app only this Mac will open without a
# fight. Everything above stays the route for anyone else's machine.
#
# One-time setup, which you have to run yourself because it touches the
# keychain: Keychain Access → Certificate Assistant → Create a Certificate,
# name it exactly "Codenotch Local Signing", identity type Self Signed Root,
# certificate type Code Signing, and leave it in the login keychain.

LOCAL_DIR     := build/local
# A derived data tree of its own, under build/ rather than in the shared one.
# It keeps the products next to .metadata_never_index, and it keeps the
# Sparkle artifacts that `appcast` searches for in the shared DerivedData
# pointing at a release build instead of a self-signed one.
LOCAL_DERIVED := $(LOCAL_DIR)/DerivedData
LOCAL_APP     := $(LOCAL_DERIVED)/Build/Products/Release/$(APP_NAME).app
LOCAL_DMG     := $(LOCAL_DIR)/$(APP_NAME).dmg
INSTALLED_APP := /Applications/$(APP_NAME).app

# Self-signed and sitting in the login keychain, so `security find-identity`
# marks it CSSMERR_TP_NOT_TRUSTED — expected, and no obstacle: codesign signs
# with it and the result satisfies its own designated requirement. The reason
# to hold a certificate at all rather than sign ad-hoc is the keychain ACL:
# it remembers which signed binary was allowed to read Claude Code's OAuth
# token, and ad-hoc signing mints a new identity per build, so "Always Allow"
# is forgotten on every rebuild. Should a second certificate ever end up with
# the same common name, put the SHA-1 here instead —
# 806A2ECF36C1641C351CF15508EFB36187D4C1AF — which resolves to exactly one.
LOCAL_IDENTITY := Codenotch Local Signing

# project.yml pins the Developer ID identity and team 6WFPL8B9FB because that
# is what a public release needs, and those are correct there — a machine
# without that certificate simply cannot build against them, and the build
# fails outright rather than degrading. Overriding on the command line is what
# keeps project.yml honest for release.
#
# Hardened runtime is off here, and putting it back is how the app stops
# launching. It turns on library validation, and dyld then demands that the
# process and every non-platform library it loads carry the *same* Team ID. A
# self-signed certificate has no Team ID at all, so the app and the copy of
# Sparkle.framework embedded next to it both report "not set" — and absent is
# not equal, so the load is refused. The failure is invisible until launch:
# the build reports ** BUILD SUCCEEDED **, `codesign --verify --strict` passes
# on both the app and the framework, and then the process takes SIGABRT before
# main with `Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle`
# and "mapping process and mapped file (non-platform) have different Team IDs".
# `archive` is unaffected: a Developer ID certificate carries a Team ID, so the
# comparison has something to match, which is why the shipped build keeps the
# flag — notarization requires it, per the note in project.yml.
#
# The flag could also be kept by granting the com.apple.security.cs.disable-
# library-validation entitlement, but that means carrying an entitlements file
# that exists only for local builds. Turning the flag off reaches the same
# place with one fewer file to keep in sync.
LOCAL_SIGNING := CODE_SIGN_IDENTITY="$(LOCAL_IDENTITY)" DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=NO

.PHONY: build-local dmg-local install-local uninstall-local

build-local: gen
	mkdir -p $(LOCAL_DIR)
	@# Spotlight indexes build output as installed applications, so a Release
	@# build under build/ leaves extra "Codenotch" entries in app search next
	@# to the real one in /Applications. This stops the whole tree being
	@# indexed.
	@touch build/.metadata_never_index
	@# Not wiped first, unlike the release tree in `archive`. A release has to
	@# be reproducible from nothing; this one only has to be current, and
	@# rebuilding Sparkle from scratch on every install is minutes of waiting
	@# for an identical result.
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DEST)' \
		-configuration Release -derivedDataPath $(LOCAL_DERIVED) \
		$(LOCAL_SIGNING) build

# The same read-only compressed image as the release one, minus the signature
# on the image itself — that exists to satisfy notarization, which this never
# goes through. Worth having anyway as the artifact you keep for a rollback or
# carry to another Mac of your own.
dmg-local: build-local
	rm -f $(LOCAL_DMG)
	rm -rf $(LOCAL_DIR)/stage
	mkdir -p $(LOCAL_DIR)/stage
	cp -R $(LOCAL_APP) $(LOCAL_DIR)/stage/
	ln -s /Applications $(LOCAL_DIR)/stage/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(LOCAL_DIR)/stage \
		-ov -format UDZO $(LOCAL_DMG)
	@# The app is inside the image now, and a loose copy left in staging is one
	@# more "Codenotch" for anything walking the tree to find.
	rm -rf $(LOCAL_DIR)/stage

# Everything in one command: generate, build, package, install.
install-local: dmg-local
	@# The running copy goes first. Replacing the bundle underneath a live
	@# process leaves the old build running, so the change looks like it never
	@# landed, and quitting later can write state back over the new install.
	pkill -x $(APP_NAME) || true
	rm -rf $(INSTALLED_APP)
	@# ditto, not cp -R: it is the copy that preserves a bundle's extended
	@# attributes and symlinks intact, and a mangled bundle is a signature that
	@# no longer verifies.
	ditto $(LOCAL_APP) $(INSTALLED_APP)
	@# Proof the identity took, and the check that matters for the keychain:
	@# a bundle that satisfies its designated requirement is one the ACL can
	@# keep recognising across rebuilds. `spctl` is deliberately absent — it
	@# answers whether Gatekeeper would admit a download, which a self-signed
	@# unnotarized app never is, and says nothing about a bundle built here
	@# that carries no quarantine flag.
	codesign --verify --strict --verbose=2 $(INSTALLED_APP)
	@# A signature that verifies is not the same as a binary that loads. Signing
	@# with a certificate that carries no Team ID is exactly the kind of thing
	@# dyld rejects at map time while every earlier step reports success — the
	@# build succeeds, codesign verifies the app and its embedded frameworks,
	@# and the process still takes SIGABRT before reaching main. The only check
	@# that catches that is starting the thing, so the target ends by doing it.
	open $(INSTALLED_APP)
	@# Long enough to matter and no longer: a library that fails to map takes
	@# the process down before main, so anything still alive here got past
	@# dyld. A bare pgrep is trustworthy because the pkill above clears the
	@# field first, leaving only the copy just launched to find.
	sleep 4
	@pgrep -x $(APP_NAME) >/dev/null || { printf '%s\n' \
		'$(APP_NAME) launched and died. The newest report in' \
		'~/Library/Logs/DiagnosticReports/$(APP_NAME)-*.ips says why: a library' \
		'that failed to load is logged there as "namespace: DYLD" with' \
		'"Library not loaded", which means the app and an embedded framework' \
		'disagree about their signatures — not that the build is broken.' >&2; \
		exit 1; }
	@echo "Installed: $(INSTALLED_APP)"
	@echo "Disk image: $(LOCAL_DMG)"

# Leaves the keychain alone. The "Always Allow" answer lives on Claude Code's
# own keychain item, not on anything this app owns, and dropping it would only
# mean answering the prompt again after the next install.
uninstall-local:
	pkill -x $(APP_NAME) || true
	rm -rf $(INSTALLED_APP)
