# Double Take

Godot 4.7.2 multiplayer game using Epic Online Services (EOS) lobbies and peer-to-peer networking. Players join private rooms with a six-character code and do not need an Epic account or an in-game Epic login.

## Internet multiplayer

Complete the one-time developer setup in [EOS_SETUP.md](EOS_SETUP.md), then export the Android or Windows client. In the game, choose **Create Private Lobby**, share the generated code, and have the other players choose **Join Lobby**. The room creator hosts the match and must keep the game open.

The Android preset produces a landscape ARM64 APK with the required EOS native runtime. The Windows preset creates a standalone desktop client. No dedicated server, public IP, domain, port-forwarding, or lobby-service process is required.

## Development

Open `project.godot` in Godot and press Play. **Offline Map Preview** opens the gameplay sandbox without an EOS connection.

Run the map/input check with:

```powershell
godot --headless --path . --script res://tools/test_phase1.gd
```

The self-contained multiplayer regression tests retain the local ENet test harness so core lobby, roles, reconnection, host-transfer, and movement logic can be checked without production EOS credentials:

```powershell
python tools/test_phase2.py
python tools/test_phase2_resilience.py
godot --headless --path . --script res://tools/test_phase3.gd
godot --headless --path . --script res://tools/test_phase4.gd
```

The Phase 3 check covers all ten minigames, five-task assignment uniqueness, private checklist restoration, host proximity/role validation, ghost completion, shared progress, and the 100% Camper victory condition. The Phase 4 check covers host-side role/proximity/cooldown validation for kills, contextual body records and reporting, private two-sabotage objectives, repair access, and timed sabotage expiry.

Export an Android development APK with:

```powershell
godot --headless --path . --export-debug Android builds/DoubleTake_EOS_debug.apk
```

Generated builds, logs, Android intermediates, and Godot import caches are not source files and may be deleted at any time.
