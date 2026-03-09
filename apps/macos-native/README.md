# T3 Code macOS native app

This directory is the dedicated home for the native macOS app.

## Goal

Keep macOS on a native Swift/SwiftUI host while leaving the existing Electron app in `apps/desktop` for Windows/Linux and any cross-platform fallback work that still depends on it.

## Current scope

- native macOS app entry point
- native window lifecycle owned by SwiftUI
- room to move desktop shell responsibilities out of Electron incrementally without disrupting the current Windows/Linux app

The shared product/backend surface remains the existing T3 Code server and contracts layers elsewhere in the monorepo.

## Run locally

```bash
cd apps/macos-native
swift run
```

On macOS this launches the native app window. On unsupported platforms it builds and exits with a short message instead of failing during compilation.
