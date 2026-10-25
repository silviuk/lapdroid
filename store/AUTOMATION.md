# Microsoft Store publication

Product **9N1L1QZJNT6Z**, identity `SilviuVlasceanu.Lapdroid`, publisher
`CN=FCAD1026-DA23-45D7-835A-3FF4ADD435D4`.

Run **Publish to Microsoft Store** on `main` with the exact stable release tag.
`v0.3` becomes MSIX version `0.3.0.0`; three-component tags also work. The workflow
downloads the release's `Lapdroid.exe`, checks GitHub's SHA256 digest and x64 PE
architecture, then packages those same bytes. It records the resolved tag commit
and binary digest; it does not claim to rebuild the binary from that commit.

Leave `submit=false` to validate and download the candidate artifact without
contacting Partner Center. Set `submit=true` to submit for certification. Configure
Actions secrets `MS_STORE_TENANT_ID`, `MS_STORE_CLIENT_ID`, `MS_STORE_CLIENT_SECRET`
from the existing publisher registration. Never put plaintext secrets in files.

Complete the initial submission and age ratings manually once. API updates need a
published baseline. Existing web drafts are preserved. Resume only an API-created
draft using its exact `resume_submission_id`, never one edited on the web.
Committed submissions are verified rather than committed twice. Only `Published`
means live. Pricing, markets, age ratings and privacy settings are inherited.

Refresh screenshots for each release, recording the exact version and hashes in
`store/Screenshots/screenshots.json`. Current captures show the actual v0.3 UI.
Paired-device details are redacted and the test diagnostic buffer was cleared.
`tools/build-store-screenshots.cjs` assembles local captures using development
dependency `sharp`. The app itself has no Node dependency.

The MSIX contains only the Windows companion. Android users install the separate
APK. `runFullTrust` supports native Bluetooth sockets, input hooks and pen injection.
Minimum platform is Windows 10 1903 x64. No elevation or custom driver is required.
The Store signs the package after certification; local unsigned MSIX files are
Store uploads, not independently installable signed downloads.

Run `./tools/Test-StorePublishing.ps1` to check identity, digest, path, endpoint,
bootstrap, upload-failure, explicit-resume and idempotency guards with mock HTTP
and no real credentials. Helpers adapt DualSlide/Luminark automation.
