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

## What is already native

- SwiftUI app entry point and window shell
- backend bootstrap configuration in Swift
- backend path/state resolution in Swift
- login-shell PATH resolution in Swift
- loopback port reservation and auth token generation in Swift
- backend process supervision in Swift
- rotating log handling in Swift
- packaged stdout/stderr capture in Swift
- app identity, commit metadata, and user-data path resolution in Swift
- secure static asset bundle resolution in Swift
- desktop update state machine and polling orchestration in Swift

## What is still missing before this is a fully functional app

- the real native session/conversation UI instead of the current status shell
- native client orchestration for the full app flow
- native menus, dialogs, folder picking, and context menus
- native updater transport/provider integration and install handoff
- native deep-link/protocol handling and full window lifecycle parity
- feature parity validation against the existing Electron desktop app

So: **SwiftUI has started**, but the native app is **not** feature-complete yet.

## Requirements

- macOS 14 or newer
- Swift 6 toolchain / Xcode 16+ for local native builds

## Run locally

```bash
cd apps/macos-native
swift run
```

On macOS this launches the native app window. On unsupported platforms it builds and exits with a short message instead of failing during compilation.
