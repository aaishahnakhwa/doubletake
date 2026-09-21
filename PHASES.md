# Double Take - Development Phases

## Phase 1 - Camp Map Preview (Complete)

- Pinewood Camp map integration
- Player movement, camera, idle/walk/run animation
- Keyboard, mouse, and Android touch controls
- Enterable rooms and exploration areas
- World collision, walkable docks, and bridges
- Minimap and area-discovery HUD
- Inspection markers and local dummy campers

Inspection markers now launch the Phase 3 tasks assigned to the local Camper.

## Phase 2 - Private Multiplayer (Implemented)

- Private lobby create/join with a six-character code
- EOS anonymous device authentication; players do not need Epic accounts
- EOS lobby discovery and P2P transport across different networks
- 4-10 player roster with name, colour, and ready state
- Host-controlled lobby settings and match start
- Private Camper/Killer role reveal
- Host-authoritative synchronized movement
- Local regression harness for lobby, roles, reconnect, host transfer, and movement
- Android EOS runtime and custom Gradle export

No dedicated server, VPS, domain, public IP, port-forwarding, or external lobby-service process is required. Before physical testing, the developer must complete the free EOS configuration in `EOS_SETUP.md` and export a fresh APK.

## Phase 3 - Camper Tasks and Task Victory (Implemented)

### Playable tasks

1. Collect firewood
2. Fix the generator
3. Prepare dinner
4. Tidy the cabins
5. Sort workshop tools
6. Refill lanterns
7. Repair dock boards
8. Clear lake debris
9. Tune the camp radio
10. Find missing supplies

### Systems

- Five assigned objectives per Camper
- Shared progress bar and task checklist
- Keyboard and touch-friendly minigames
- Host validation of proximity and completion
- Ghost task continuation
- Camper victory at 100% shared progress

## Phase 4 - Killer Kills and Sabotage (Implemented)

- Normal close-range elimination
- Campfire, weak-tree, dock, and workshop contextual eliminations
- Reportable bodies, cooldowns, and host validation
- Generator blackout, radio jam, hidden supplies, and lantern sabotage
- Two required sabotage objectives for the Killer
- Camper repairs and capped effect durations

Animations remain non-graphic and cartoon-like.

## Phase 5 - Meetings and Complete Game Loop

- Body reports and emergency meetings
- Campfire meeting scene
- Living-player and ghost chat separation
- Discussion and voting timers
- Vote, Skip, tie, and ejection rules
- Camper/Killer victory checks
- Win/lose screens and rematch flow

After Phase 5, a complete match can run from private lobby to result.

## Phase 6 - Art, Sound, UI, and Performance

- Layered map art with separate floors, walls, roofs, canopy, and props
- Finished character and interaction animations
- Task panels, icons, particles, and sound effects
- Responsive Windows/Android UI and accessibility settings
- Low-end Android performance and battery optimization

## Phase 7 - Friend Playtest and Release Candidate

- Repeated 4-, 6-, and 10-player mixed-device sessions
- Separate-network Wi-Fi/mobile-data testing
- Reconnect and app background/foreground testing
- Exploit, desync, and soft-lock fixes
- Balance and match-duration tuning
- Signed Android release APK and Windows build
- Private distribution and troubleshooting instructions

## Recommended Order

`Phase 1 complete -> Phase 2 implemented -> Phase 3 implemented -> Phase 4 implemented -> Phase 5 complete loop -> Phase 6 polish -> Phase 7 release testing`
