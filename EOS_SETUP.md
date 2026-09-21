# EOS multiplayer setup

Double Take now uses Epic Online Services (EOS) Lobbies plus P2P transport for private internet games. No lobby URL, public IP, router forwarding, VPS, or domain is needed.

## One-time Epic setup

1. Create a free product and use its default sandbox/deployment in the Epic Developer Portal.
2. In **Product Settings > Clients**, create a client named `Double Take P2P`, then attach a **Peer2Peer** client policy. Do not enable Epic Account Services, Store, Analytics, or any payment feature.
3. Copy the Product ID, Sandbox ID, Deployment ID, Client ID, and Client Secret. The example file already supplies the documented default 64-character encryption key because this game does not use Player or Title File Storage.
4. Copy `eos_credentials.cfg.example` to `eos_credentials.cfg` and fill the values. This file is ignored by Git and is included in the APK when exported.

The build deliberately has no fallback to `localhost`: a blank EOS configuration displays an in-game setup error rather than pretending that remote play is available.

## Android build

The Android export uses the custom Gradle build at `android/build`. It needs the EOS Android AAR plus the Android bootstrap changes described in the EOSG addon documentation. The repository bundles EOSG 2.3.1 for Windows x64 and Android arm64/x86_64 under `addons/epic-online-services-godot`.

After the one-time Android template setup, export the **Android** preset again. The APK will use device-ID/anonymous EOS Connect login, so players do not need to configure a router or enter a server address.

## Product behaviour

- Create Private Lobby generates a six-character room code in EOS.
- Join Lobby finds that code through EOS and connects to the room owner over P2P.
- The owner is the authoritative simulation host for that match.
- If the active host leaves, the room should be recreated before another match. Seamless live match-state migration is intentionally not faked; it requires a separate mesh/state-handoff implementation.
