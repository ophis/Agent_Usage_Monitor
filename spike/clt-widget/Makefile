# CLT-only build of the TASK-573 widget spike: swiftc + codesign (ad-hoc) + ditto.
SHELL := /bin/bash
.SHELLFLAGS := -eo pipefail -c

APP := build/QuotaboardSpike.app
APPEX := $(APP)/Contents/PlugIns/QuotaboardSpikeWidget.appex
DEST = $${HOME:?}/Applications/QuotaboardSpike.app
STATE = $${HOME:?}/.local/state/quotaboard
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: build install uninstall check clean

build:
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APPEX)/Contents/MacOS
	cp Host/Info.plist $(APP)/Contents/Info.plist
	cp Widget/Info.plist $(APPEX)/Contents/Info.plist
	xcrun swiftc -O Host/main.swift -o $(APP)/Contents/MacOS/QuotaboardSpike
	xcrun swiftc -O -parse-as-library -application-extension Widget/SpikeWidget.swift \
		-Xlinker -e -Xlinker _NSExtensionMain -o $(APPEX)/Contents/MacOS/QuotaboardSpikeWidget
	codesign --force -s - --entitlements Widget/widget.entitlements $(APPEX)
	codesign --force -s - $(APP)

install: build
	rm -rf "$(DEST)"
	ditto $(APP) "$(DEST)"
	$(LSREGISTER) -f "$(DEST)"
	pluginkit -a "$(DEST)/Contents/PlugIns/QuotaboardSpikeWidget.appex"
	mkdir -p -m 700 "$(STATE)"
	[ -f "$(STATE)/spike.txt" ] || echo "installed $$(date -u +%FT%TZ)" > "$(STATE)/spike.txt"

uninstall:
	-pluginkit -r "$(DEST)/Contents/PlugIns/QuotaboardSpikeWidget.appex"
	-$(LSREGISTER) -u "$(DEST)"
	rm -rf "$(DEST)"
	rm -f "$(STATE)/spike.txt"
	-rmdir "$(STATE)" 2>/dev/null

check: build
	plutil -lint Host/Info.plist Widget/Info.plist Widget/widget.entitlements
	codesign --verify --deep --strict --verbose=2 $(APP)
	diff <(codesign -d --entitlements - --xml $(APPEX) 2>/dev/null | plutil -convert json -o - -) \
		<(plutil -convert json -o - Widget/widget.entitlements)
	@echo "check ok: appex entitlements match Widget/widget.entitlements"

clean:
	rm -rf build
