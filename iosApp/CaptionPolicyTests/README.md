# Caption policy checks

Run from the repository root in WSL Ubuntu (or macOS) with Swift installed:

```bash
mkdir -p build/validation
swiftc iosApp/iosApp/Player/CaptionSelectionPolicy.swift iosApp/CaptionPolicyTests/main.swift -o build/validation/caption-policy-tests
build/validation/caption-policy-tests
```

These executable checks cover English-only automatic selection, sign-marker precedence, missing tracks, explicit Off overrides, stable restoration when mpv renumbers tracks, external subtitle URL matching, separate movies/episodes, persistence read by a new process, and ten-second rewind restoration, including repeated rewinds and cancellation.

The checks exercise the actual Foundation-based policy and preference store. They do not compile the Kotlin/Compose app or establish on-device behavior. The full iOS app still requires its macOS Kotlin/Native and Xcode build. Build 154 is prepared locally; do not upload or publish it without the user's explicit go-ahead.
