[**Website & downloads ↗**](https://silviuk.github.io/lapdroid/) · [Latest release](https://github.com/silviuk/lapdroid/releases/latest)

[![Support on Ko-fi](docs/assets/ko-fi.svg)](https://ko-fi.com/silviuvlasceanu)

# Lapdroid

Use your Windows keyboard and touchpad to control an Android phone over Bluetooth. Type, tap, drag, and scroll without a Wi-Fi connection.

**Windows + Android · Bluetooth**

## Why Lapdroid?

- **Use the input you already have.** Type with your physical keyboard and use your touchpad to move the floating Android pointer.
- **Tap, drag, and navigate.** Left click taps, right click goes Back, middle click goes Home, and touchpad scrolling moves through pages.
- **Keep it over Bluetooth.** The Windows and Android apps communicate through Bluetooth RFCOMM. The Android app does not request Internet permission.

## See it in action

![Windows laptop → Bluetooth RFCOMM → Android phone](docs/assets/connection.svg)

Two companion apps. One paired Bluetooth connection. Press F12 to switch control.

## Get started

1. Download the Windows app and Android APK from the latest release, then pair the devices in Windows Bluetooth settings.
2. Open the Android app and grant Bluetooth, overlay, and Accessibility permissions. These let it draw a pointer and perform your input actions.
3. Start the Windows Bluetooth server and connect the paired devices. Press F12 to capture input; press it again to return to Windows.

### Install with WinGet

```powershell
winget install --id silviuk.Lapdroid -e
```

Install the Android APK from the same [release page](https://github.com/silviuk/lapdroid/releases/latest).

## Requirements & limits

Windows 10 or 11, Android 8.0 or later, Bluetooth on both devices, and both Lapdroid companion apps. Android overlay and Accessibility permissions are required for pointer display and input control.

Android permissions must be enabled before input can work. Install the APK on Android; the AAB is a publishing bundle, not a direct-install package. Bluetooth behavior can vary by device.

## Documentation & contributing

See [build and distribution notes](docs/DEVELOPMENT.md) and the [store submission guides](docs/store-submissions/).

Found a problem or have an idea? [Open an issue](https://github.com/silviuk/lapdroid/issues). If the app helps you, [support its development on Ko-fi](https://ko-fi.com/silviuvlasceanu).

© 2026 Silviu Vlasceanu. [License](LICENSE).
