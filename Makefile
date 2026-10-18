CONFIG ?= debug
APP := build/Clementine.app

.PHONY: build app run clean ffmpeg

build:
	swift build -c $(CONFIG)

# SwiftPM only produces a bare executable; the .app bundle is assembled here.
app: build
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp Support/Info.plist $(APP)/Contents/
	cp "$$(swift build -c $(CONFIG) --show-bin-path)/Clementine" $(APP)/Contents/MacOS/
	codesign --force --sign - $(APP)

run: app
	open $(APP)

# Leaves build/ffmpeg alone: rebuilding it downloads sources and takes minutes.
clean:
	rm -rf .build $(APP)

ffmpeg:
	scripts/build-ffmpeg.sh
