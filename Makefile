.PHONY: test build icon app dmg notarize release run clean

test:
	./scripts/run-tests.sh

build:
	swift build -c release

icon:
	./scripts/build-icon.sh

app:
	./scripts/build-app.sh

dmg:
	./scripts/build-dmg.sh

notarize:
	./scripts/notarize-dmg.sh

release: test dmg

run: app
	open "dist/Ping-Pong.app"

clean:
	swift package clean
	rm -rf dist
