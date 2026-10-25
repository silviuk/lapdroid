# Lapdroid development

From the repository root, build both apps with `./build_all.sh`, Windows alone with `make -C windows`, or Android with `./android/build.sh`. See the build scripts for their toolchain requirements.

The Android manifest defines the minimum supported Android version and required Bluetooth, overlay, and Accessibility permissions.

For packaging and distribution, see the [store submission guides](store-submissions/). Publishing bundles and submission recipes do not imply a live store listing.
