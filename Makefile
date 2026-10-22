.PHONY: all build test install uninstall render probe vendor clean

all: test build

build:
	./tools/build.sh

test:
	swift test

install: build
	./tools/install.sh

uninstall:
	./tools/install.sh --uninstall

# Renders fixtures/kitchen-sink.md through the real web view and reports what
# ended up in the DOM.
probe:
	swift build
	.build/debug/mdql-probe fixtures/kitchen-sink.md --png build/preview.png

render:
	swift build
	.build/debug/mdql-render fixtures/kitchen-sink.md build/render

vendor:
	./tools/vendor.sh

clean:
	rm -rf build .build
