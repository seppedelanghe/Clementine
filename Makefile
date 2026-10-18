CONFIG ?= debug
APP := build/Clementine.app
FFMPEG := build/ffmpeg/bin/ffmpeg
# "-" signs ad hoc for local builds; scripts/release.sh passes a Developer ID identity.
SIGN_IDENTITY ?= -
# Notarization needs the hardened runtime and a secure timestamp, which ad hoc signing can't provide.
CODESIGN := codesign --force --sign "$(SIGN_IDENTITY)" $(if $(filter -,$(SIGN_IDENTITY)),,--options runtime --timestamp)

.PHONY: build app run clean ffmpeg release

build:
	swift build -c $(CONFIG)

# SwiftPM only produces a bare executable; the .app bundle is assembled here.
app: build $(FFMPEG)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources/Licenses
	cp Support/Info.plist $(APP)/Contents/
	cp assets/clementine-icon.icns $(APP)/Contents/Resources/AppIcon.icns
	cp assets/clementine-menubar.svg $(APP)/Contents/Resources/
	cp LICENSE $(APP)/Contents/Resources/Licenses/Clementine-LICENSE
	cp build/ffmpeg/licenses/* $(APP)/Contents/Resources/Licenses/
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/Clementine" $(APP)/Contents/MacOS/
	cp $(FFMPEG) $(APP)/Contents/MacOS/
	# Nested code is signed before the bundle that contains it.
	$(CODESIGN) $(APP)/Contents/MacOS/ffmpeg
	$(CODESIGN) $(APP)

run: app
	open $(APP)

# Leaves build/ffmpeg alone: rebuilding it downloads sources and takes minutes.
clean:
	rm -rf .build $(APP) build/release

# Rebuilt only when missing or when the pinned versions in the script change.
$(FFMPEG): scripts/build-ffmpeg.sh
	scripts/build-ffmpeg.sh

ffmpeg:
	scripts/build-ffmpeg.sh

release:
	scripts/release.sh
