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

# The checks no unit test can stand in for: that the isolated bundle launches,
# and that its menu and window lifecycle are readable through Accessibility.
check: test
	./Scripts/check-app.sh

clean:
	rm -rf .build
