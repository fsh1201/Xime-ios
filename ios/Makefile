.PHONY: generate open clean rime enable-rime verify-rime-linux

generate:
	xcodegen generate

open: generate
	open Xime.xcodeproj

rime:
	./scripts/build-rime-ios.sh

enable-rime:
	./scripts/enable-rime.sh

verify-rime-linux:
	./scripts/verify-rime-linux.sh

clean:
	rm -rf Xime.xcodeproj DerivedData .build Config/*.plist Config/*.entitlements
