# T3 Code macOS native app

This directory is the dedicated home for the native macOS app.

## Goal

Keep macOS on a native Swift/SwiftUI host while leaving the existing Electron app in `apps/desktop` for Windows/Linux and any cross-platform fallback work that still depends on it.

## Current scope

- native macOS app entry point
- native window lifecycle owned by SwiftUI
- room to move desktop shell responsibilities out of Electron incrementally without disrupting the current Windows/Linux app
- native runtime bootstrap for backend launch configuration, login-shell PATH resolution, rotating logs, and process supervision

The shared product/backend surface remains the existing T3 Code server and contracts layers elsewhere in the monorepo.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain / Xcode 16+ for local native builds

## Run locally

```bash
cd apps/macos-native
swift run
```

On macOS this launches the native app window. On unsupported platforms it builds and exits with a short message instead of failing during compilation.
