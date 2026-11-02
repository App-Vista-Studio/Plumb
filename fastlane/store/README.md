# App Store screenshots (US)

Composes the 10 screenshots in `fastlane/screenshots/en-US` (1320 x 2868, 6.9" display) from raw
simulator captures, using the app's own icon set.

1. Capture raw screens on the iPhone 17 Pro Max simulator with a 9:41 status bar
   (`xcrun simctl status_bar <udid> override --time 9:41 --batteryState discharging --batteryLevel 100 ...`)
   and the app's debug flags (`-screen <name>`, `-appearance light`). See `main.swift` for the file names used.
2. Build and run:
   ```
   swiftc -O main.swift ../../Plumb/DesignSystem/SVGPath.swift PMIcon.swift -o compose
   ./compose <rawDir> ../screenshots/en-US
   ```
   `PMIcon.swift` here is a copy of `Plumb/DesignSystem/PMIcon.swift` with the `#Preview` block removed.
3. Upload with `fastlane ios store_screenshots`.
