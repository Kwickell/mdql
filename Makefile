.PHONY: all build test check-rendering install uninstall render probe vendor clean

all: test build

build:
	./tools/build.sh

test: check-rendering
	swift test

# The markdown pipeline is JavaScript, so the Swift tests cannot reach it.
check-rendering:
	swift build --product mdql-probe
	python3 tools/check_rendering.py

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
