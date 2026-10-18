CONFIG ?= debug
APP := build/Clementine.app
FFMPEG := build/ffmpeg/bin/ffmpeg

.PHONY: build app run clean ffmpeg

build:
	swift build -c $(CONFIG)

# SwiftPM only produces a bare executable; the .app bundle is assembled here.
app: build $(FFMPEG)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Support/Info.plist $(APP)/Contents/
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/Clementine" $(APP)/Contents/MacOS/
	cp $(FFMPEG) $(APP)/Contents/MacOS/
	# Nested code is signed before the bundle that contains it.
	codesign --force --sign - $(APP)/Contents/MacOS/ffmpeg
	codesign --force --sign - $(APP)

run: app
	open $(APP)

# Leaves build/ffmpeg alone: rebuilding it downloads sources and takes minutes.
clean:
	rm -rf .build $(APP)

# Rebuilt only when missing or when the pinned versions in the script change.
$(FFMPEG): scripts/build-ffmpeg.sh
	scripts/build-ffmpeg.sh

ffmpeg:
	scripts/build-ffmpeg.sh
