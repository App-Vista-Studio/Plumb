fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios build

```sh
[bundle exec] fastlane ios build
```

Compile a Release simulator build to check the project builds (no signing, no upload)

### ios bump

```sh
[bundle exec] fastlane ios bump
```

Increment the build number

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Archive, sign and upload to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Archive, sign and upload a build to App Store Connect (does not submit for review)

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture every screen on the iPhone 17 Pro simulator (dark and light) into fastlane/screenshots

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
