CONFIG ?= debug
APP := build/Clementine.app
FFMPEG := build/ffmpeg/bin/ffmpeg
DOCXIDE := build/docxide/bin/docxide-pdf
SPARKLE := $(APP)/Contents/Frameworks/Sparkle.framework
# "-" signs ad hoc for local builds; scripts/release.sh passes a Developer ID identity.
SIGN_IDENTITY ?= -
# Notarization needs the hardened runtime and a secure timestamp, which ad hoc signing can't provide.
CODESIGN := codesign --force --sign "$(SIGN_IDENTITY)" $(if $(filter -,$(SIGN_IDENTITY)),,--options runtime --timestamp)

.PHONY: build app run clean ffmpeg docxide release

build:
	swift build -c $(CONFIG)

# SwiftPM only produces a bare executable; the .app bundle is assembled here.
app: build $(FFMPEG) $(DOCXIDE)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources/Licenses $(APP)/Contents/Resources/Fonts $(APP)/Contents/Frameworks
	cp Support/Info.plist $(APP)/Contents/
	cp assets/clementine-icon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp assets/clementine-menubar.svg $(APP)/Contents/Resources/
	cp LICENSE $(APP)/Contents/Resources/Licenses/Clementine-LICENSE
	cp build/ffmpeg/licenses/* $(APP)/Contents/Resources/Licenses/
	cp -R build/docxide/licenses/ $(APP)/Contents/Resources/Licenses/
	cp build/docxide/fonts/* $(APP)/Contents/Resources/Fonts/
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/Clementine" $(APP)/Contents/MacOS/
	cp $(FFMPEG) $(DOCXIDE) $(APP)/Contents/MacOS/
	ditto "$$(swift build -c $(CONFIG) --show-bin-path)/Sparkle.framework" $(SPARKLE)
	# Sparkle only uses its XPC services in sandboxed apps; removed so they needn't be signed.
	rm -rf $(SPARKLE)/XPCServices $(SPARKLE)/Versions/B/XPCServices
	# Nested code is signed before the bundle that contains it.
	$(CODESIGN) $(APP)/Contents/MacOS/ffmpeg
	$(CODESIGN) $(APP)/Contents/MacOS/docxide-pdf
	$(CODESIGN) $(SPARKLE)/Versions/B/Autoupdate
	$(CODESIGN) $(SPARKLE)/Versions/B/Updater.app
	$(CODESIGN) $(SPARKLE)
	$(CODESIGN) $(APP)

run: app
	open $(APP)

# Leaves build/ffmpeg and build/docxide alone: rebuilding them downloads sources and takes minutes.
clean:
	rm -rf .build $(APP) build/release

# Rebuilt only when missing or when the pinned versions in the script change.
$(FFMPEG): scripts/build-ffmpeg.sh
	scripts/build-ffmpeg.sh

ffmpeg:
	scripts/build-ffmpeg.sh

$(DOCXIDE): scripts/build-docxide.sh
	scripts/build-docxide.sh

docxide:
	scripts/build-docxide.sh

release:
	scripts/release.sh
