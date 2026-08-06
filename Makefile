# Standfast — SwiftPM only, no .xcodeproj. Recipes are indented with tabs.
.PHONY: build test app run check clean

build:
	swift build

test:
	swift test

app:
	./Scripts/build-app.sh

run: app
	open .build/Standfast.app

# The one check no unit test can stand in for: that the assembled bundle is
# still an app after the build directory it was compiled in is gone.
check: test
	./Scripts/check-app.sh

clean:
	rm -rf .build
