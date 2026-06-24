PRODUCT_NAME=xctidy

PREFIX?=/usr/local

CP=/bin/cp -f
MKDIR=/bin/mkdir -p
RM=/bin/rm -f
SWIFT?=swift

SWIFT_BUILD_FLAGS=--configuration release

.PHONY: all
all: build

.PHONY: build
build:
	$(SWIFT) build $(SWIFT_BUILD_FLAGS)

.PHONY: test
test:
	$(SWIFT) test

.PHONY: install
install: build
	$(eval BINARY_DIRECTORY := $(PREFIX)/bin)
	$(eval BUILD_DIRECTORY := $(shell $(SWIFT) build --show-bin-path $(SWIFT_BUILD_FLAGS)))
	$(MKDIR) $(BINARY_DIRECTORY)
	$(CP) "$(BUILD_DIRECTORY)/$(PRODUCT_NAME)" "$(BINARY_DIRECTORY)"

.PHONY: uninstall
uninstall:
	$(RM) "$(PREFIX)/bin/$(PRODUCT_NAME)"

.PHONY: clean
clean:
	$(SWIFT) package clean

.PHONY: xcode
xcode:
	open Package.swift
