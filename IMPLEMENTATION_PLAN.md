# Double Take implementation plan

Double Take is a private 4-10 player social-deduction game for Windows and Android. The first release uses one map, Pinewood Camp, and supports cross-network play through Epic Online Services (EOS).

## Locked technical decisions

- Godot 4.7.2, GDScript, 2D Compatibility renderer.
- Windows x64 and Android 9+ ARM64; landscape on Android.
- Six-character private EOS lobby codes with anonymous device login.
- EOS P2P transport; no dedicated server, lobby web service, VPS, domain, port-forwarding, or player Epic login.
- The room owner is the authoritative gameplay host. Clients send requests and receive authoritative state snapshots.
- If the active match host leaves, the current release ends that session and players create a new room. Seamless match-state host migration is deferred until there is a tested state-transfer design.

## Match rules

- Exactly one Killer; all other players are Campers.
- Each Camper receives five tasks. Shared completion reaches the Camper task victory.
- The Killer receives two required sabotage objectives and must complete both before a parity victory is possible.
- Campers also win by ejecting the Killer.
- The host validates movement, task proximity, kills, cooldowns, reports, votes, sabotage, and victory conditions.
- Joining after a match starts is closed. Reconnection should retain the same player slot and private role for a bounded grace period.

## Current state

### Complete

- Pinewood Camp map, collision, camera, character movement, minimap, exploration HUD, desktop controls, and Android touch controls.
- EOSG runtime bundled for Windows and Android.
- EOS anonymous authentication, private lobby create/join by code, and P2P multiplayer peer integration.
- Lobby roster, player colour/name, ready flow, host settings, match start, private role reveal, and synchronized host-authoritative movement.
- Ten playable keyboard/touch Camper tasks, five private assignments per Camper, shared progress, host proximity/completion validation, ghost continuation, reconnect-safe task state, and the 100% Camper task victory.
- Host-authoritative close-range and four contextual Killer eliminations, non-graphic reportable bodies, kill cooldowns, two private sabotage objectives, four timed/capped sabotage effects, and living-Camper repairs.
- Android custom Gradle export with the EOS Android runtime.
- Offline map preview and local automated regression harness.

### Required before an internet playtest

- Create the free EOS developer product and credentials described in `EOS_SETUP.md`.
- Export a fresh APK containing those credentials.
- Test two physical devices on different networks, followed by a four-player mixed Windows/Android session.
- Verify Wi-Fi to mobile-data changes, background/foreground behavior, reconnect behavior, latency, and host departure.

## Remaining phases

1. **Meetings:** turn the existing host-validated body report into a meeting, then add emergency meetings, discussion/voting timers, skip/tie/ejection rules, chat separation, and victory/result screens.
2. **Presentation:** layered map art, occlusion, finished character reactions, particles, sound, UI polish, accessibility, and low-end Android optimization.
3. **Release testing:** repeated 4/6/10-player mixed-network sessions, exploit/desync fixes, signed Android build, Windows build, and private distribution instructions.

## Verification

- Keep the Phase 1 map/input check and local multiplayer regression tests passing.
- Test authoritative action validation and private-role disclosure for every new gameplay system.
- Exercise 100-250 ms latency and packet loss during physical playtests.
- Verify 16:9 through 20:9 landscape layouts and large touch targets.
- Do not introduce a paid hosting dependency. Re-evaluate EOS terms before public release; if they become unsuitable, choose another no-billing architecture before shipping.
