## LOVE 12 canvas clip space (iOS)

Every 3D pass here builds its own projection and bypasses LOVE's
`transform_projection`, so the mod, not LOVE, owns the clip-space convention.
Those matrices are built **Y-down**: `Mat4.scale(1, -1, 1)` is folded into
`Voxel3D.viewProjection` and `ShadowMap.update` so that clip Y = -1 is the top
of the target. That is what lets every consumer read a canvas position straight
off the same matrix with `(y / w * 0.5 + 0.5)` -- the horizon, the sun/moon
disc, the battle pins, `ShadowMap.uvVP` and Water's screen-space march all do.

LOVE 11 stores a canvas that way, so the matrix goes to the GPU untouched.
LOVE 12 normalises clip space itself (`love_clipSpaceTransform`, applied to
whatever `position()` returns) so clip Y = +1 is the top on every backend and
target: OpenGL flips only while a render target is bound, Metal has nothing to
flip. The Y-down matrix is then one flip too many and the 3D pass composites
vertically mirrored.

`lib/ClipSpace.lua` resolves this in one place. It exports `CLIP_Y` as a
compile-time `#define` prepended to the three shaders that transform geometry
with one of these matrices (`Voxel3D`, `ShadowMap`, `Water`), and those shaders
multiply their clip Y by it. It is `1.0` on LOVE 11, a no-op the shader compiler
folds away, so desktop and Android are untouched. **Do not "fix" the mirror by
flipping the finished canvas instead:** the canvas is mixed, not uniform --
`Weather.paintOverlay` draws 2D into it inside `Voxel3D.endScene` -- so a
presentation flip would correct the world and invert the overlays.

Why it only ever showed on Gen 2: gen1recomp's `Renderer:setWorldOverride` blit
already compensates on iOS/LOVE 12, and the Gen 1 path goes through it. Gold's
pipeline seam (`src/world/gen2/World.lua`) blits the pipeline canvas straight,
so nothing compensated there.

**Do not port this patch to a Gen 1 sibling unchanged.** Every mod in this
family registers the same `voxel` pipeline id and carries the same
`Mat4.scale(1, -1, 1)` fold, so the code looks identical -- but a Gen 1 mod's
world canvas reaches the screen through `Renderer:setWorldOverride`, whose blit
ALREADY flips on iOS/LOVE 12. That path is compensated today. Adding `CLIP_Y`
there would correct the same mirror twice and invert Gen 1 instead. This mod is
`"games": ["gen2"]`, so its own Gen 1 `installWorldOverride` branch is
unreachable and is not affected either way. A Gen 1 port wants the engine's blit
and the mod's fold reconciled together, not this patch copied across.

## v0.2.81 Gold party-leader follower binding

- Trainer `follow` mode now treats the saved party slot as authoritative. Slot 1 remains the default, so Gold PARTY -> SWITCH naturally replaces the follower when the top-of-party Pokemon changes.
- `ControlEngine:_syncFollowLeaderBinding()` runs before player/trailer visual sync and rewrites the persistent follower fingerprint to the Pokemon currently occupying that slot. This fixes the old behavior where `Selection:getActiveFollowerMon()` deliberately chased the starter fingerprint to its new party position.
- Trailer composition also compares `spec.mon ~= trailer.pokepcMon`, not species alone, so same-species and shiny/non-shiny swaps trigger a correct rebind.
- Explicit FOLLOW selections still bind another party slot; the mod does not reorder the party itself.
- No Stadium DSM7 cache rebuild is required.

## v0.2.80 Gen-2 full-color follower recovery

- The mod is Gen-2-only, so its Pokemon follower/wild sprite providers no longer derive Gen-1 luminance sheets based on `PaletteFX.mode`. The original RGBA follower sheets are always served as `trueColor=true`.
- `lib/follower/control_engine.lua` uses colored normal/shiny submerged sheets directly during water-surface refreshes; entering/leaving water can no longer swap a colored follower for a grayscale one.
- Party follower icons use the resolved sprite definition's `trueColor` contract instead of `paletteFxRedpp()`.
- This release changes no DSM format and requires no Stadium 2 cache rebuild.

## v0.2.79 DSM7 render-tile origin/window parity

The RDP texture path is tile-relative: after the tile shift, SL/TL from `G_SETTILESIZE` are subtracted before clamp/wrap/mirror. SH/TH are the inclusive clamp bounds, and mask zero forces clamping even if MIRROR/WRAP bits are present. DSM6 recorded `G_SETTILE` but discarded `G_SETTILESIZE`, so it could not reproduce this after extraction. DSM7 scans both commands, bakes the origin into packed UVs, resolves the effective sampling span, and crops each decoded texture variant to that span so LOVE's native clamp/repeat/mirrored-repeat addresses the same texel range.

## v0.2.78 DSM6 material fidelity + National-number Pokédex

The Stadium fragment parser previously rebuilt textured primitives from texture-table pixels plus a CI4 palette selector, but discarded the render tile's S/T address fields and treated Vtx bytes 12..14 as normals unconditionally. DSM6 persists the per-primitive address/lighting/tint result. Material DL scanning is recursive with a hard budget, render-tile shifts/masks are folded into packed UVs, and LOVE's sampler is switched per primitive to repeat / mirrored-repeat / clamp. A negative Stadium texture index now resolves to a neutral 1x1 material for every species, with DSM6 tint supplying unlit/material colour.

The cache marker now accepts DSM6 rev1 only. This is deliberate: DSM4/DSM5 do not contain the missing material bits, so runtime heuristics cannot reconstruct them safely.

For the modern Pokédex, `GoldSubmenuBattleStyle` wraps the live `PokedexMenu:order()` only while custom UI is enabled and returns a stable sort of `dex.entries[*].dex`. This changes the backing list, not just rendering, so `current()`, cursor movement and 3D preview ownership all use the same National-number row.

## v0.2.77 independent player/Pokémon model ownership

`GoldVoxelBridge` now exports two model gates: `V.modelsEnabled()` remains the Stadium Pokémon gate backed by the existing `stadium3dSprites` option, while `V.playerModelsEnabled()` is backed by the new `player3dModel` option. `OverworldStadium` uses the player gate only for the `red_3d_player` renderer and its mesh-shadow/card-artifact suppression; Pokémon preparation/draw/cast continues to use the Pokémon gate. This means disabling the player model cannot release or flatten Stadium Pokémon, and disabling Stadium Pokémon cannot disable the selected Character Selector skin.

## v0.2.76 Stadium dialogue + extended OPEN WORLD zoom

- `TextBoxBattleStyle` patches presentation only. `src.render.TextBox:update`, substitution, pagination, CONT/page waits, auto/stay semantics and callbacks remain engine-owned. The custom draw reconstructs the currently typed visible prefix from `self.pages` + `Font.split()` and renders it in window space after cancelling Gold's centered 160x144 UI transform.
- `ChoiceBox` receives the same presentation-only treatment; its native up/down/A/B and 15-frame answer hold remain unchanged.
- `DioramaZoom` now reads `worldZoomRange`: STANDARD=2.20, FAR=4.00, WORLD=8.00, EXTREME=12.00. The initial value remains 1.0, so existing camera startup framing is unchanged.
- `OpenWorldZoom` wraps the official `zoom.range` hook. With OPEN WORLD active and a non-STANDARD range, its lower offset becomes `-S`, allowing `Zoom.scale()` to reach the engine's existing 0.25 hard floor. Integer stepping/persistence remain engine-owned.
- Current engine check: `dev` head `7804ef97938c25da4cf86257a161b9f5f32e2a3d`; the shared TextBox and Zoom seams used here are present on that snapshot.

## v0.2.75 battle overlay geometry + posed-model camera fit

- `BattleControllerUI.drawCommandDiamond` now reserves independent vertical lanes. The bottom PACK/DOWN command ends well above the footer, and icon/font size is bounded by panel height so wide/short windows cannot force command text into the stick hint.
- `StadiumRig:posedBounds()` exposes the already-calculated current pose AABB without duplicating skinning internals.
- `PartyModelPreview` builds the current pose before camera selection, transforms its live bounds into preview-world scale, centers the camera on the posed mesh, and computes distance from both vertical FOV and `tan(horizontalFov/2) = aspect * tan(verticalFov/2)`. Model depth is included in the eye distance.
- The Pokédex caller uses posed-bounds horizontal/vertical padding rather than the old bind-height `focusY` workaround.

## v0.2.74 Gold live-battle command startup

- v0.2.74 follower seams: connected outdoor Gold maps now apply the preserved Wilds trailer handoff synchronously inside `map.entered`, after destination people lists are rebuilt but before another render can occur. This removes the one-frame follower pop without recreating the trailer.

- Current Gold `BattleState:update` holds `phase = intro/resolving` text at `messageTimer > 0` until A/B; it then changes to `phase = menu` during a fixed step before the next render. The custom direct controller wrapper previously treated that logical menu state as immediately clickable.
- `BattleControllerUI` now separates **visual readiness** from **input arming**. A normal command menu must complete one `drawCommandDiamond` pass before face-button / arrow / D-pad shortcuts are accepted. Warmup edges are swallowed instead of leaking into Gold's hidden native menu.
- Ordinary custom-UI battle intro prompts are auto-confirmed through Gold's own input queue after a short hold. This is restricted to `phase == intro`, excluding tutorial/contest and all later decision/message phases.
- A mapped face button that is forwarded during intro is marked held in the polling fallback until release, preventing the same physical A/Cross edge from being reinterpreted as PACK when the menu becomes ready.

## v0.2.73 Gold follower ownership correction

- Reverts v0.2.72's Gold-only `partyTrailMons()` reservation: Wilds again supplies follower slot #1 on Gold and owns its interpolation/trail state.
- Gold's native `src.world.gen2.Follower` remains a fallback only. When embedded Wilds is present, native `pikachuFollower` entities are purged while `pokepcTrailer` entities are explicitly preserved.
- This matches the shared Wilds control engine's existing `shouldSpawnStockFollower` behavior, which already suppresses the stock/native follower in ordinary FOLLOW mode when Wilds trailers are active.
- `LEAD PARTY FOLLOWER` now gates the Wilds trail list itself so OFF actually removes followers.

## v0.2.72 Gold follower transition ownership

- Gold's native `src.world.gen2.Follower` owns primary follower slot #1.
- Embedded Wilds `partyTrailMons()` reserves that slot on Gold and only creates trailers for configured followers #2+.
- Extra trailers anchor behind the native Gold follower when present.
- `GoldPartyFollower` de-duplicates orphan native followers on `map.entered` and keeps the current/newest engine entity.
- Native Gold follower species follows the embedded Wilds active FOLLOW selection when available, with party slot #1 as early-boot fallback.

## v0.2.71 Wilds sandbox recovery
- The current mod sandbox throws on `love.filesystem`. Wilds runtime-sheet probes were still dereferencing it during `registerContent()`, aborting the embedded Wilds factory before any map could initialize.
- Wilds asset existence/read paths now use `EngineCompat` (`mod:read` / `mod:info`, with engine-owned persistence FS fallback). Raw `io` fallbacks were removed from the active runtime-sheet/water paths.
- This is additive to v0.2.70: voxel terrain, Stadium models, Character Selector coexistence and compose/drawWorld compatibility remain intact.

## v0.2.70 current-sandbox renderer recovery
- Current Gen1Recomp blocks `love.system` inside mod-owned code. GoldVoxelBridge and GoldComposeBridge now use engine `src.core.Platform` first and guard the complete legacy `love.system` expression inside `pcall`.
- GoldPipelineBridge is active again on current engines through `render_pipelines.drawWorld`.
- If `red_3d_player` / Character Selector is installed, the Stadium pipeline deliberately remains OFF so Gen1Recomp does not zero the selector's `voxel` pipeline. The compose bridge remains the world owner and OverworldStadium still consumes `red3dPlayerRenderer:drawVoxel` for the selected skin.

## v0.2.69 desktop compose/canvas recovery

- Desktop uses the confirmed v0.2.45 `render.compose` ownership path again; `GoldPipelineBridge` is not registered.
- `Voxel3D.canvasRestorePolicy()`, `ShadowMap.canvasRestorePolicy()`, and `AntiAlias.canvasRestorePolicy()` report `physical-screen` on Windows/Linux/macOS/unknown desktop targets and `nested-caller` on Android/iOS.
- `Voxel3D` begin/end cleanup, the `ShadowMap` prepass, and `AntiAlias.resolve()` all follow that same platform policy. This preserves Android's v0.2.58 whole-frame fix without forcing desktop back into an intermediate canvas that can be overwritten by Gold's native 2D present. Because `red_3d_player` is delegated from inside the voxel scene, the same fix also restores the Skin Selector's 3D character path when the voxel world is active.
- The v0.2.68 pipeline file remains in source for reference but is inert in this release.

## v0.2.68 current Gold world-pipeline compatibility

- Current desktop Gen1Recomp now consumes `render_pipelines.drawWorld` on Gold. The old Gen-2 port assumption that Gold had to be replaced only at `render.compose` is no longer sufficient.
- `lib/GoldPipelineBridge.lua` registers `stadium2_gold_voxel` with `priority = 1100`, an OFF/ON ladder, a cheap option gate, and a `drawWorld(ctx)` callback that hands `ctx.state` (the live Gold World) to `GoldVoxelBridge.renderFrame`.
- `game.ready`, `map.entered`, and this mod's voxel/Open World option changes synchronize the engine pipeline level. The mod option remains authoritative; no user hotkey is required to activate the engine world pass.
- `GoldComposeBridge` remains installed. A one-frame handoff bit from `GoldPipelineBridge` tells it when current Gold already rendered voxels, preventing duplicate `VoxelScene` work. If an older host never calls `drawWorld`, the bit is never set and the original compose path runs unchanged.
- The drawWorld canvas uses `ctx.width`/`ctx.height`, matching the engine pipeline compositor. Legacy compose continues to use its existing physical/logical scaling path.

## v0.2.66

- Restored the known-working v0.2.45 live `ChunkMesher` implementation for current/neighbor voxel terrain.
- Removed `VoxelDiskCache` from the live mesher dependency path; persistent disk-cache I/O remains disabled.
- Keeps v0.2.65 Stadium ROM import compatibility and all later UI/follower/settings/Open World features.

## v0.2.66 Stadium ROM import compatibility notes

- Current Gen1Recomp mod sandboxes no longer expose raw `love.system`, `love.filesystem`, or `io` to mod chunks. v0.2.64 still dereferenced those APIs when the Stadium ROM action was pressed, which explains a picker-time crash even after boot recovery succeeded.
- `lib/EngineCompat.lua` now resolves engine-owned `src.core.Platform`, `src.core.SaveData`, `src.core.HostShell`, and `src.import.RomImporter` services behind guarded calls.
- Android/iOS uses the engine RomImporter mobile ROM-picker branch so the native bridge executes in engine scope. `picked_rom.gb` is treated only as a temporary transport filename; the mod validates N64 magic before calling `StadiumInstall.beginFrom`.
- Desktop dialog output is staged into the save directory through HostShell and then read through `SaveData.persistenceFs`; no raw mod `io.open` remains in the Stadium import path.
- StadiumInstall, StadiumPack, and Lugia diagnostic output use the same engine persistence filesystem.

## v0.2.64 recovery notes

- Regression boundary confirmed by device testing: v0.2.45 boots while later builds crash at Play on the same install.
- Startup now guards all optional post-v0.2.45 presentation/settings installers.
- `ModSettingsPersistence` no longer overrides `ManagerState:persistOptions`, rebinds `game.options`, or calls `Game2:persistOptions`; it persists only this mod's changed key.
- `AndroidFullFrameFlip` does not patch `Game2:draw` unless the engine reports Android.
- Persistent `VoxelDiskCache` I/O is recovery-disabled; in-memory meshing/cache remains active.

## v0.2.62 runtime notes
- `PartyModelPreview` builds/skinned the current Stadium pose before selecting the preview camera, scans the posed vertex rows through the actor model matrix, and computes a camera distance from both horizontal and vertical FOV.
- If posed bounds cannot be measured, the previous height/radius estimate remains as a safe fallback.
- UI panel dimensions are unchanged in this release; the fix is entirely the internal model-view camera.

## v0.2.61 runtime notes
- Gen2 `src.world.gen2.Follower` still owns movement/trailing. The mod now changes only that NPC's local `spriteDef` after spawn, keyed by the live party lead's National Dex number; the global `SPRITE_PIKACHU` placeholder remains untouched.
- Pokédex viewer geometry is UI-only; preview camera/model scale is unchanged from v0.2.59.
- Categorized settings keep ManagerState as the value/persistence owner and only restore root cursor/scroll state on category return.

## v0.2.60 runtime notes

- `customUI=false` bypasses PauseMenuBattleStyle, GoldSubmenuBattleStyle, ModMenuBattleStyle, categorized settings presentation and BattleControllerUI ownership.
- GoldComposeBridge ignores pause-backdrop flags while native UI is selected so original opaque/full-screen pages behave normally.
- Pokédex preview panel height is increased without widening the panel or reducing the v0.2.59 model scale.

## v0.2.59 runtime notes
- Stadium UI previews retain high-resolution overscan but use tighter camera distance and a higher focus target. This specifically fixes the v0.2.58 tradeoff where clipping was reduced by making the Pokémon too small.
- No UI panel dimensions changed.
- v0.2.58 cache safety and Android flip rendering remain unchanged.

## v0.2.58 runtime notes
- Current-map correctness now wins over persistent-cache speed: only non-urgent/far FULL maps may be restored from disk. If a disk-restored far map becomes urgent/current, its terrain/water mesh is released and rebuilt before becoming authoritative.
- Offscreen render passes must restore their caller canvas. This is required by Android whole-frame rotation and also makes Voxel3D/ShadowMap/AA composable with future final-frame effects.
- PartyModelPreview's fifth argument is an optional framing table (`renderScale`, `heightExtent`, `radiusExtent`, `cameraMargin`, `focusY`, `fovDeg`). Existing four-argument callers continue to use safer defaults.

## v0.2.55 — Persistent Cache / Settings / Pokédex Preview
- `lib/VoxelDiskCache.lua` persists the unindexed six-float vertex stream produced by ChunkMesher's FFI sink for FULL terrain + water meshes. Cache signatures include map body tiles, dimensions/tileset identity and canonicalized seam masks; cached geometry is uploaded directly to LOVE meshes before auxiliary scenery warms.
- `lib/ModSettingsPersistence.lua` patches the Gen2 ManagerState persistence seam to call `Game2:persistOptions()` after ManagerState updates `save.options.modOptions` / `loader.modOptions`.
- `GoldSubmenuBattleStyle` reuses `PartyModelPreview` for POKéDEX list/entry model showcases and releases the preview actor on PokedexMenu exit.

## v0.2.54 — Native Tilt + Live Pause Backdrops
Gold/Recomp's built-in OPTIONS `TILT` setting now directly changes the voxel diorama camera pitch; the separate mod DIORAMA TILT row is removed. Pause-launched OPTIONS, POKéDEX, POKéMON, PACK, POKéGEAR, AJ/Trainer Card and SAVE keep the live voxel overworld visible behind their custom glass UI, matching MOD SETTINGS.

## v0.2.52 pause settings shortcut
- Uses the official `ui.start_menu.items` hook; no engine StartMenu item table is replaced.
- Injects after the native `option` row, then pushes `ManagerState`, selects this mod by id, and calls its native `openOptions` method.
- Clears ManagerState's intermediate back stack so B returns to START directly.

## v0.2.51
- Added **3D POKéMON / SPRITES** in Mod Options.
- ON (default): current Stadium/3D model presentation.
- OFF: keeps the voxel renderer, OPEN WORLD, 3D terrain, trees, buildings, grass, props, weather and cameras, but restores Gold-style 2D sprite/card characters and Pokemon.
- OFF also disables Stadium model previews in the custom party/battle PKMN menus and releases live-battle Stadium combatants so Gold's normal 2D battle pics can render over the voxel battlefield.
- The lead party follower and visible Wilds Pokemon remain functional using their 2D sprite providers.

## v0.2.50
- Live battle trainer grounding fix: the battle-only trainer stand can still move horizontally for composition, but its vertical height is now anchored to the real player/encounter ground instead of whatever raised tree/cliff voxel happens to sit under the displaced stand point.
- Clears stale step/ledge lift and disables the free-roam visual walking/bobbing bridge while battle mode owns the trainer pose, preventing the trainer from drifting or floating above the ground during camera movement.
- OPEN WORLD full-3D rendering and v0.2.49 tree void filling are otherwise unchanged.

## v0.2.49
- OPEN WORLD tree void-fill refinement: remaining stitched white gaps are now filled by side-aware edge tree sampling, reducing missed holes and making the synthetic forest apron follow the nearby map edge more closely.
- Keeps the open-world + voxel/3D combination intact; this update only refines how remaining outdoor void patches are forest-filled.

v0.2.48 note: OPEN WORLD now backfills remaining outdoor stitched voids with matching tree/forest filler instead of leaving white rectangular holes.


## v0.2.47 OPEN WORLD 3D integration

- OPEN WORLD now implies an active Gold voxel provider; it cannot silently become the engine's flat survey renderer.
- Open-world neighbours use full ChunkMesher meshes with per-map cardinal seam masks. The outside ring/apron remains on boundary maps, closing the visible world perimeter at very large zoom.
- VoxelScene records a per-frame ready-neighbour set and gates neighbour terrain auxiliaries (figures/grass/flowers/shadows) to it. This preserves the current/ready 3D world while farther meshes build.
- TerrainAtlas calls are guarded per map and fall back to the atlas attached by GoldVoxelBridge, preventing a single distant atlas failure from aborting the composed voxel frame.
- OFF retains the original body-only direct-neighbour streaming behavior.

## v0.2.46 — OPEN WORLD now extends, never replaces, the 3D scene

The v0.2.45 graph refactor accidentally deleted `neighborUrgent()` while `adaptedNeighbors()` still invoked it for every depth-1 connected map. That error occurred while constructing the Gold voxel state, so `GoldComposeBridge` correctly failed open to the already-rendered flat Gold frame. The visible symptom was severe: the new map-residency work appeared present, but all of this mod's VoxelScene-only presentation — voxel terrain, 3D scenery/grass and Stadium-model entities — vanished.

v0.2.46 restores the helper and adds a regression test that reaches the actual `adaptedNeighbors()` path rather than testing the graph math in isolation. OPEN WORLD is now treated strictly as a residency-set choice: `makeState()` always carries the same current map, merged Gold entities/visible Wilds Pokemon, ghosts and camera state; ON only expands `state.neighbors` to the connected graph. Consequently every existing VoxelScene pass (terrain/structures, water, figures, actors/Stadium replacements, grass and flowers, shadows) keeps executing.

The option transition is also explicit. `mod.options_changed` invalidates `neighborMapCache` and `openWorldGraphCache` immediately, while the render frame independently re-reads `mod.options:get("openWorld")`. On the first OFF frame, VoxelScene's `open|...` -> `stream|...` live-key transition calls `ChunkMesher.setLive(..., true)`, dropping the far meshes instead of retaining the previous open-world generation.

## v0.2.45 — optional full connected-map OPEN WORLD

`GoldVoxelBridge` now has two residency modes selected by the `openWorld` mod option. The default streaming path is unchanged: adapt the current map's direct cardinal connections, request those neighbour body meshes, and let `VoxelScene.prefetch` / `ChunkMesher.setLive` bound residency to the current neighbourhood.

With OPEN WORLD enabled, the bridge breadth-first walks `map.def.connections` through `world.maps`. Connection offsets are accumulated from each source map so every reachable connected map is expressed in current-map coordinates. Root direct neighbours still prefer Gold's own `world.neighbors` offsets; deeper maps use the same `offset * 32` / source-width / destination-width placement math as the proven direct adapter. The graph excludes warp-only destinations.

The full graph is passed to `VoxelScene` as render neighbours and therefore joins the live mesh/animated-atlas set. Far maps request body-only meshes as normal-priority cooperative jobs; only first-ring destinations near an approached edge become urgent. Current-map border masks are explicitly restricted to `depth <= 1`, and `V.goldNeighbors` remains first-ring-only for third-person camera collision, avoiding world-size scans in those hot paths.

Switching OPEN WORLD off clears the adapted-map graph cache. The smaller `VoxelScene` live key makes `ChunkMesher.setLive` cancel/release far jobs/meshes and `TerrainAtlas.setLive` release far per-map animated atlases. If graph traversal itself fails, the bridge logs it and falls back to direct-neighbour streaming instead of disabling the voxel renderer.

## v0.2.44 — BATTLE COMMANDS is a native/custom UI switch

`BattleControllerUI.owns()` and its input-ownership gate now both return false when the mod option `battleCommands` is OFF. That is intentionally broader than v0.2.43: the scene renderer no longer bakes the replacement HUD into the 3D battle shot, controller/keyboard events are no longer intercepted by the custom command layer, and `GoldComposeBridge` therefore takes its existing fail-open/native path and composites Gold's own Gen-2 battle UI. Turning the option back ON restores the custom Stadium battle presentation without changing battle rules.

## v0.2.38 — actual Gold START menu + exact custom battle-selector styling

## v0.2.40 Mod Manager / third-party pause-menu scope

- `lib/ModMenuBattleStyle.lua` owns the standard Mod Manager presentation for every mod, including per-mod `options_schema` pages.
- A Mod Manager instance created while Gold's START menu is on top becomes transparent so the voxel world remains behind the glass submenu; managers opened elsewhere retain an opaque dark surround.
- The `screen.pushed` listener only replaces drawing for recognizable list-like third-party states in the pause chain. It does not replace their update methods or guess at bespoke custom renderers.
- Built-in Gold pause screens remain owned by `GoldSubmenuBattleStyle.lua`; the bridge detects those tags and does not double-wrap them.


## v0.2.39 pause/submenu presentation scope

The custom START skin now shows the normal full pause list in one tall panel. `GoldSubmenuBattleStyle` tags submenu instances only when their constructor is reached while `src.ui.gen2.StartMenu` is the current stack top. Tagged built-in screens become transparent presentation overlays and receive custom renderers; their original update/action methods are untouched. This prevents field/battle/script users of the same Gen-2 menu classes from being globally reskinned. Pokedex graphics-heavy AREA/search utility views intentionally retain their native renderer rather than discarding gameplay information. Externally injected pause rows remain owned by their injecting mod.

v0.2.37 patched the wrong class (`src.ui.StartMenu`, the Gen-1 path). Gold's visible gameplay menu is `src.ui.gen2.StartMenu`; its rows include PACK and PokéGEAR and every row carries the two-line MENU ACCOUNT description seen in the Gold UI. v0.2.38 patches `src.ui.gen2.StartMenu.draw` directly and leaves `update`, `choose`, `close`, `Chrome.List`, unlock rules and `ui.start_menu.items` hook results untouched.

The renderer intentionally mirrors `BattleControllerUI`'s custom PACK/PKMN selector values rather than merely using a vaguely modern theme: panel fill `0.018, 0.026, 0.045`, 0.82 selector alpha, 0.20 white border, the same 42%-width right-side selector geometry, four visible rows, 0.07/0.17 row fills and 0.72 selected outline. The selected MENU ACCOUNT description is drawn as the same left-side battle-message panel language. Quit YES/NO is also custom-rendered.

`GoldComposeBridge` redraws Gold's visible stack after painting the voxel world. The pause renderer calls `love.graphics.origin()` inside that draw, so on the voxel compose path it escapes the centered 160x144 transform and draws at the same whole-window resolution as the custom battle HUD. A small-target scale fallback keeps the renderer usable on direct native-canvas paths. Any rendering error calls Gold's original `StartMenu:draw()` so the menu cannot become invisible or unusable.

## v0.2.35 — custom in-battle PKMN / PACK overlays

Normal live 3D battles no longer push `Gen2PartyMenu` or `Gen2PackMenu` for the two face-button commands. `BattleControllerUI` holds a lightweight selector state while the underlying Gold `BattleState` remains in `phase == "menu"`, consumes only selector D-pad/A/B events, and draws four Stadium-style rows over the existing world. A valid switch is submitted through Gold's battle action API. Battle items call Gold's `useItem`; party-target item effects call Gold's `applyPartyItem`, with a custom party target and custom move target for single-slot PP items. Tutorial/contest and non-normal submenu flows remain native.

## v0.2.34 — let Gold open its own battle submenus

The controller diamond no longer calls `openPack()` / `openParty()` itself. It writes Gold's own battle-menu cursor (`FIGHT=1`, `PKMN=2`, `PACK=3`, `RUN=4`) and queues a synthetic GB `A` edge on the live `Input` object. On the next fixed step Gold's existing `BattleState:update()` performs the exact cartridge-style branch, including its current `Screens.push` calls, stack ownership, item rules, switch rules and callbacks. The custom HUD also stops owning presentation while the battle state is `submenu`, so the native Pack/Party screen remains visible and receives ordinary input.

## v0.2.32 — guaranteed HUD draw ownership

The v0.2.31 compositor-based HUD could still disappear because Gold's live 3D battle shot and the later UI compositor do not always agree on which stack object owns presentation. v0.2.32 removes that dependency: `VoxelScene.render()` asks `OverworldBattle.battle()` for the exact live Gen-2 `BattleState` and draws `BattleControllerUI` while the world scene canvas is still bound. `GoldComposeBridge` sees the scene-owned HUD flag and skips duplicate overlay composition. If the scene draw fails, the existing compositor/native UI fallback remains available.

The battle occlusion shader now excludes geometry through `groundY + 8.5`, preserving jump ledges and other low map borders while continuing to clear taller trees/bushes/walls from combat sightlines.

## v0.2.32 - controller HUD visibility hardening

The 0.2.30 full battle replacement could hide Gold's native command canvas successfully while failing to surface the replacement command panel on hosts where the live Gold BattleState was not the exact object returned by the simple stack-top lookup. The compositor now asks `GoldVoxelBridge.battleScreen()`, which forwards the BattleState stored by `OverworldBattle.battle()`. It only owns the frame when that BattleState (or a wrapper sharing the same logic battle) is the visible top state, so PACK/PARTY screens still fall back to Gold. The command panel also uses a presentation-only command-ready gate that spans the one-step `resolving -> menu` seam.

# v0.2.29 controller input boundary

The core issue in v0.2.28 was hook placement. `src.core.Input:gamepadaxis` converts `leftx/lefty` into held GB directions using its own hysteresis before `BattleState:update` reads them. Wrapping `Game2:gamepadpressed` could not stop that conversion. `BattleControllerUI.install` now wraps the live `game.input` methods themselves: analog `leftx/lefty` are swallowed only while the normal BattleState owns the screen, and any pre-existing `source="stick"` direction is released/cleared. D-pad input still uses the native path for move/item/party submenus.

Physical face buttons are intercepted at `Input:gamepadpressed` while `phase == "menu"`, before `GamepadMap` maps them to GB A/B. A per-controller release latch prevents the release event from leaking into the newly opened submenu. A frame poll of `isGamepadDown` provides a fallback for platform/controller stacks that miss mapped button events. Keyboard WASD is similarly withheld from native GB directions in the live battle state, while arrow keys activate the four command positions directly.

The camera bug had a separate unreachable seam: Gold's `OverworldBattle.update` intentionally calls `CamControl.tick` only on the non-Gold legacy path. v0.2.29 therefore polls `FirstPerson.pollMappedRightStick` from `BattleCinematic.frameImpl` itself and applies `manualLook` there. This guarantees that the exact camera returned to `VoxelScene` sees right-stick input.

# v0.2.28 battle visibility / controller UI

### Occlusion handling

Gold route geometry is packed into one depth-tested `ChunkMesher` mesh, so fading a named tree/wall object after meshing is not available without rebuilding the map into many draw calls. v0.2.28 handles battle visibility in `Voxel3D` instead. The vertex shader carries uncurved world position; while `BattleScene` draws terrain it enables two camera-to-combatant XZ capsules plus a softer midpoint bubble. Fragments more than five world pixels above encounter ground are dither-discarded inside those regions. Because discarded fragments never write depth, the Pokemon/effects behind them become genuinely visible; ground stays opaque and the uniform is disabled before Pokemon/FX draws.

### Command UI and inputs

`BattleControllerUI.lua` only claims Gold `BattleState.phase == "menu"`. SDL face-button names map spatially to the requested PlayStation layout (`x`/west Fight, `b`/east Run, `a`/south Pack, `y`/north Pokemon). PC arrows mirror those positions. The module calls the same BattleState public methods (`submit`, `openPack`, `openParty`) and reproduces the native Fight entry/Struggle gate, then hands every submenu back to Gold.

`GoldComposeBridge` redraws the 3D battle canvas over the lower native command region before the custom dock, so the old opaque white menu is removed rather than merely tinted. This restoration happens only during `phase == "menu"`; move lists, messages, item screens and party screens remain native.

### Camera/control

Direct Pokemon movement accepts WASD in addition to left stick. `CamControl.tick` now branches live-world battles to `BattleCinematic.manualLook`; the previous code updated `BattleCam` even though `BattleCinematic` owned the rendered camera.

# v0.2.27

- Added direct control of the player's active Stadium 2 Pokemon during Gold live-world battles.
- Left stick moves the 3D Pokemon camera-relative inside a bounded battle arena.
- PlayStation Square / Xbox X (SDL gamepad `x`) triggers real imported Stadium 2 skeletal attack performances. Repeated presses cycle safe non-idle clips for the current species.
- The battle camera treats direct-control mode as player-active and follows the controlled Pokemon.
- Direct movement is presentation-only: Gold remains authoritative for HP, turns, moves, switching, items, catches and battle outcomes.
- Control waits until the player's 3D Pokemon has completed its entrance and is actually visible; trainer intro/tutorial/faint states are not hijacked.
- Lugia retains the v0.2.22 untextured-body material fix and v0.2.26 attack-root pinning/safe-clip exclusions.

## v0.2.26 Lugia attack-stage travel removal

The imported Stadium 2 Lugia attack clips contain camera-stage translation that is valid when Stadium follows one Pokemon with its own shot, but looks like teleporting/flying when replayed as a world-space actor under Gen1Recomp's fixed live-battle camera. Clip filtering alone was insufficient because even visually usable clips can carry the common torso/root through a large stage arc.

`StadiumRig:measureBind()` now retains per-bone bind translations as runtime-only metadata. `StadiumRig:pinBoneToBind()` subtracts the current-to-bind translation of a selected posed bone from every pivot/draw matrix. `StadiumMon:build()` applies this only to Dex 249 while `state == "attack"`, using runtime bone #3 (the uploaded Lugia diagnostic's `bone[2]`, the common torso/root for wings/neck/tail). This preserves local skeletal animation and removes only bulk actor travel. No DSM bytes or shared species routing are changed.

## v0.2.25 Gold attack presentation fail-open bridge

The v0.2.23 OBJ suppression was too optimistic: `BattleState:animForMove` could start Gold's native animation, then Gold could replace that runner with its after-hit animation before `OverworldBattle.update` rendered the voxel shot. The 3D adapter therefore saw no matching runner while the UI wrapper had already hidden `BattleAnimView:drawObjects`.

v0.2.25 latches `{move, side, resolved def, token, elapsed}` at `animForMove` and advances the world-space effect on its own short clock. The skeletal bridge resolves symbolic Gold move keys through `Battle:moveDef` to the move definition's numeric `index` before calling `StadiumMon:attackGen2`. Native OBJ suppression is now fail-open and requires two successful world-space draw frames for the same token before hiding Gold's sprite layer.

## v0.2.16 Lugia root-cause pass: preserve geo joint flags

The previous Lugia recovery passes were working with incomplete packed data. `StadiumFragment` had always decoded command `0x1D`'s `flags` byte, but `StadiumBuild` dropped it when writing DSM4. Stadium's own renderer does not treat all joints the same: `geo_layout.c::func_80018490` converts those bits into a transform mode, and `func_800143C0` selects different matrix/scale behavior from that mode. Lugia's Stadium 2 tree mixes those semantics enough for the lost byte to become visible as detached rigid pieces.

DSM5 adds one raw flag byte to every bone record. Both `StadiumBuild.bindMatrices` and `StadiumRig:pose` now reproduce the two non-camera source paths instead of trying normal/absolute/flat hierarchy guesses. A DSM4 cache cannot be repaired perfectly at runtime because the flag byte was never stored, so the format marker is bumped and a one-time Stadium 2 ROM re-import is intentional.

## v0.2.15 Lugia hierarchy probe / capture skill pass

Dex 249 is no longer rejected before `StadiumPack.load`. `StadiumRig.new` probes the bind pose before `measureBind`, selecting a hierarchy interpretation only for Lugia. The preferred repair keeps parent rotation while treating translations as model-space; the flat mode is used only when it is dramatically more compact. Repaired stance metrics overwrite the stale DSM4 measurements in memory, so existing caches are usable without deletion. Lugia remains `staticPose=true` because Stadium 2 move/context routing still maps all contexts to animation 0; this prevents a provisional clip from tearing the repaired mesh apart.

Capture difficulty now affects both retention and player skill. `strengthResistance` is computed when aim begins, its normalized strength shrinks the on-screen hit radius and speeds the ring, and `throwQuality` has stricter grade cutoffs. `startThrow` stores screen aim error as a lateral/vertical world-space endpoint; `drawWorld` follows that endpoint so a MISS is physically visible.

## v0.2.14 first-map free-camera animation lifecycle fix

The v0.2.13 walking bridge correctly spoofed `Player.moving` only during the external Character Selector draw, but it discovered whether free movement was active through `Game.overworld` / `StateStack`. On the initial Gold map that compatibility facade can lag the live `Game2.world`; crossing a map connection refreshes it, which explains why the trainer animation only began working after a transition.

`GoldVoxelBridge.makeState()` now copies `_stadiumFreeMoveActive`, `_stadiumFreeVisualMoving`, and the animation distance from the exact world being rendered. `VoxelScene.posesOf()` carries the visual-moving bit on the player's captured pose. `OverworldStadium.withFreeVisualWalk()` consumes that pose-local state first, with the old world lookup only as an older-call-site fallback.

## v0.2.13 Lugia fallback and free-camera character animation

Dex 249 remains rejected by `StadiumMon` because the current local Stadium 2 hierarchy decode is known to explode the body into separated parts. The fallback no longer delegates to the roaming entity's generic sprite. `OverworldStadium` retains the resolved Dex id even after rig preparation fails and draws `follower_249_normal.png` / shiny directly through the voxel billboard pipeline with a fixed presentation scale and explicit solid alpha/depth state.

Gold true free-camera movement deliberately advances continuous `px/py` without setting the engine's grid-step `Player.moving` flag. That is correct for gameplay but left external character skins idle because their walk pose can key from the engine flag. `GoldCameraControls` now records `_stadiumFreeVisualMoving` from actual displacement. `OverworldStadium` consumes that bit only around the 3D Character Selector's `drawVoxel` / `drawVoxelShadow` calls: it temporarily exposes moving + walk phase, calls the renderer, and restores the real fields immediately. No collision/script state observes the spoof.

## v0.2.11 manual capture input, Ball material and Lugia safety

The capture trigger now wraps the documented `input.step` mod hook. Gold raises this once per fixed logic tick before `Input:step`, so raw R3/right-mouse edges are visible even if the player has not crossed a cell. `world.stepped` remains useful for spawn updates, but it cannot be the activation clock for a stationary aiming mechanic. The contact handler is intentionally left unset, so Wilds' `_startBattleNative` remains authoritative when the player physically touches a roaming Pokémon.

The supplied Poké Ball COLLADA mesh uses an atlas-oriented material/UV layout that did not map consistently through this renderer's single diffuse texture path. v0.2.11 therefore uses a tiny generated UV sphere at runtime and a dedicated equirectangular Poké Ball texture. The sphere's V coordinate is inverted relative to its latitude so LOVE's image-top V=0 maps red to the north/top hemisphere rather than the bottom.

Lugia's failure is not treated as a mere scale or idle-animation problem anymore. The user's local Stadium 2 decode is visibly separated at the model/bind level, so Dex 249 is a species-specific 3D rejection for now: `StadiumMon:setSpecies(249)` returns false and the existing voxel entity path draws Gold's ordinary sprite billboard. This is intentionally preferable to claiming the 3D mesh is repaired when the local ROM-derived hierarchy cannot be validated in this environment.

## v0.2.07 live-battle trainer presentation

`lib/OverworldBattle.lua` already filters Gold's native `BattleState:drawPic` whenever the corresponding Stadium subject is visible. Earlier builds deliberately exempted `playerSide + showPlayerTrainer`, allowing Gold's 2D trainer back-pic through during the opening. In the live voxel presentation that is now redundant because `VoxelScenePatch` keeps and repositions the actual 3D player trainer beside the player's combatant.

v0.2.07 removes that exemption. During `goldShotFor(self)` live-world battles, a covered player pic is suppressed even while `showPlayerTrainer` is true. The battle state itself is untouched, so Gold still performs the normal trainer-to-Pokémon send-out sequence logically; only the duplicate 2D render is skipped. Non-live/fallback Gold battles still call the native draw path unchanged.

## v0.2.06 overworld capture integration

The visible-Wilds contact seam is wrapped rather than replaced. `OverworldCapture.begin()` only claims ordinary battleable visible encounters when a regular POKé BALL, voxel renderer, empty stack and party/current-box capacity are available; all other cases execute the original `_startBattle` function.

A transparent `_stadiumCaptureOverlay` state freezes `Game2` overworld logic through the engine's existing StateStack update priority while `render.compose` continues to render the live world. `FirstPerson.onTop()` treats only this tagged state as camera-driving, so the existing relative mouse and polled mapped right-stick inputs keep steering aim without making normal menus camera-active.

The user-supplied COLLADA ball was converted to the renderer's Position/TexCoord/Shade mesh format at packaging time. Its diffuse V coordinate is flipped to match the supplied atlas. The runtime ball is transformed directly in Voxel3D and therefore participates in normal world depth/occlusion.

Catch success uses `src.battle.gen2.Catching.attempt`; the caught record is built with `src.battle.gen2.Mon.new`, then stored in the same party/box/Pokédex table shapes used by Gold. The minigame consumes a regular Poké Ball with `Bag.remove` at throw time. Quality modifies the synthetic overworld HP/catch-rate inputs, but the species catch rate remains authoritative.

## v0.2.05 camera input reliability

`lib/GoldVoxelBridge.lua` now treats desktop F6 as an edge-triggered state as well as an event. `Game2:keypressed` still handles the normal low-latency path, but `renderFrame()` calls `pollCameraHotkey()` before resolving `cameraMode`; this protects camera cycling from later callback replacement while a shared `f6Down` latch prevents duplicate cycles.

`lib/FirstPerson.lua` keeps the existing `Game2:gamepadaxis` / raw joystick wrappers and adds `pollMappedRightStick()`. Each update samples connected mapped gamepads' `rightx/righty` axes and chooses the strongest active right-stick vector. That state is processed by the existing squared stick response in `FirstPerson.update`, alongside the existing mouse-delta accumulator, so both devices continue to control one yaw/pitch pair.

## v0.2.04 connected-map voxel streaming

The important Gold compatibility change is in `lib/GoldVoxelBridge.lua`. Upstream Gold already computes connected-map image records (`id/ox/oy/image`) and can look multiple hops outward, but earlier Stadium2 builds intentionally converted that list to `neighbors = {}` because `VoxelScene` requires real Map objects. v0.2.04 adapts the current map's direct cardinal connections back into `src.world.gen2.Map` instances, attaches the same Gold atlas/color renderer used by the current map, and passes those maps to `VoxelScene`.

Only direct connections are rendered as voxel neighbours in this release. That guarantees at least one whole map of look-ahead in every available direction while bounding mobile GPU/memory cost. Gold remains authoritative for actual connection crossing, NPC scripts, collision and warps. Neighbor bodies are async-preloaded; an edge-proximity flag promotes the approached destination to the urgent build slice. A warm body mesh is accepted as the new current-map bootstrap after a seam, while a cold boot still synchronously primes the full map with connected-neighbour masks.

The adapter also adds `map` to matching native Gold neighbour records. This activates existing third-person/follower compatibility code that already expected `nb.map` but previously received only image records.

## v0.2.03 forest apron and battle-camera safety

`ChunkMesher.RING` is now eight Gen-2 blocks, and `Structures.RING/ROUND_RING` match it at 32 tiles. The synthetic outdoor border therefore remains real meshed round-tree geometry for twice the previous distance on all four sides; connected-neighbour masking remains unchanged.

`BattleCinematic.frame` is now an error boundary around the optional camera. It validates battle animation/arena values and returns no placed camera on an unexpected engine shape, allowing the normal overworld camera to render the battle. `OverworldBattle` also uses `(table.unpack or unpack)` with explicit result counts for the `advanceQueue` observer, fixing LuaJIT/LÖVE hosts that do not expose `table.unpack`.

## v0.2.02 active-turn battle framing and trainer sideline

Gold's Gen-2 `BattleState` exposes the real move attacker through `anim.hudSide`, and each queued `move` event also carries its acting `side`. The live battle shim now observes (without consuming or changing) `advanceQueue()` and stores `_stadiumActiveSide` for the current resolving turn. `BattleCinematic` uses the animation's `hudSide` first, then that resolving-turn latch, and clears back to a two-subject frame once the menu/move-selection phase returns. This avoids the v0.2.01 sine-wave guess about which Pokemon should lead the shot.

The cinematic camera now solves an eased shoulder angle behind the acting Pokemon and uses an active-subject-weighted focus point (strongest during a move animation). Between turns it returns to midpoint and resumes the slow orbit.

`exactGoldArena()` now also computes `trainerStand`, offset outward and backward from the player's combatant. The VoxelScene Stadium patch applies that stand point only to the captured **visual pose** of the player when `_stadiumLiveBattle` is set; the engine Player object, collision cell, scripts, post-battle location, and save coordinates are untouched.

DIORAMA's continuous distance clamp is widened from 0.55–2.20 to **0.24–2.20**.

## v0.2.01 continuous diorama lens and live battle orbit

`DioramaZoom.lua` owns a continuous distance multiplier (0.55x–2.20x). `Voxel3D` applies it only to the classic orbit camera distance, so 1ST/3RD placed cameras are unaffected. `CamControl` routes desktop wheel/trackpad events directly to that value on the FULL/DIORAMA rung. `GoldVoxelBridge` also polls `love.touch` directly for two free Android contacts and applies the pinch ratio to the same value, avoiding the late Game2 callback seam that previously made Android pinch unreliable.

`BattleCinematic.lua` builds a placed camera from `OverworldBattle.cameraContext()`: midpoint of the live arena pair, encounter ground height, and current Gen2 BattleState. `VoxelScene` gives that camera final authority only while a live-world battle exists. The orbit radius/height ease rather than cut; `screen.anim ~= nil` tightens the shot during attack animation. Manual right-thumb/mouse deltas are routed to `BattleCinematic.manualLook`, which holds automatic orbit for 2.5 seconds and then resumes smoothly. No battle logic, damage, menus, or world coordinates are altered.

## v0.2.00 Android touch and perimeter runtime paths

The v0.1.99 right-thumb path still lived exclusively inside `Game2:touchpressed/touchmoved` wrappers. On Android builds where the overlay/input chain bypasses a late instance wrapper, those methods never see the free finger; the already-working camera slider had solved the same class of failure by polling `love.touch` each render frame. `GoldVoxelBridge.updateRightLookTouches` now does the same for camera look, rejects overlay/slider contacts, suspends itself when two free right-side contacts indicate pinch, and writes directly through `FirstPerson.lookBy`. It is serviced from both free-roam `renderFrame` and battle `updateBattle`.

For live-world Gold battles, `CamControl.battleLive` now treats `shot.liveWorld` as steerable without consulting `BattleCam.steerable`; that flag belongs to the legacy staged arena and is not initialised by the normal voxel camera used by Gold live-world fights.

The perimeter fix now changes the generated geometry rather than only its class cutoff: `ChunkMesher.RING` is four blocks and `Structures.RING/ROUND_RING` are 16 tiles, so the new outer block is physically present and carved with the same cylinder/canopy tree shapes.

## v0.1.99 Android right-thumb look and perimeter forest depth

`FirstPerson.install(game)` now treats only the right 55% of open Android screen as a free-look touchpad; `TouchControls:hitTest()` still wins for the virtual D-pad/buttons. `CamControl` uses the same right-side gate during battles. For Gold live-world battles, `OverworldBattle.shot().liveWorld` routes drag deltas into `FirstPerson.lookBy()` because that battle background is rendered by `VoxelScene` with the normal placed first/third-person rig; the legacy staged `BattleCam` is retained only for non-live-world battle scenes.

`Structures.ROUND_RING` increases from 4 to 8 tiles while `ChunkMesher`'s full 12-tile ring is unchanged. The extra near belt is still carved through the established profile-driven cylinder/canopy path, so the Johto tree normalization and anti-rectangular-wall safeguards remain authoritative.

## v0.1.98 true-directional Gold walk

`lib/GoldCameraControls.lua` now consumes the unquantised camera-space vector only during ordinary on-foot free roam in the 1ST/3RD voxel rungs. It rotates that vector through `FirstPerson.moveWorld`, updates a continuous world-pixel body with axis-separated collision/wall sliding, and suppresses Gold's cardinal `heldDir` only for those normal walking frames.

The logical Gold cell changes when the body's centre crosses a 16px cell boundary. At that boundary the adapter runs the same gameplay-facing landing chain used by `World:stepBody` (trainer sight, `world.stepped`, warp, coord script, step count, encounter). Forced/special states are not reimplemented: bike/surf, currents, ice, forced doors, ledges, connections and boulder pushes transfer back to native Gold movement.

There is intentionally no `Player.moving` or `Player:walkPhase` spoof. `FirstPerson.bodyYaw` follows the actual travel bearing and external character renderers can infer animation from `player.px/player.py` displacement.

## v0.1.98 camera-mode latch and Gold movement ownership

The v0.1.96 slider could enter 1ST/3RD but AUTO camera ownership then re-read `red_3d_player`'s prior public `voxel` pipeline rung and overwrite a requested DIORAMA on the next frame. `GoldVoxelBridge` now treats direct slider/F6 input as an explicit local camera choice in AUTO/STADIUM control and keeps a runtime `cameraOverride` latch. The choice is mirrored to the selector pipeline when available, but the local Gold camera no longer depends on that mirror sticking. Explicit **CAMERA CONTROL = CHARACTER SELECTOR** ignores the latch and restores external ownership.

`GoldCameraControls` no longer stands down merely because `red_3d_player` is installed/owning camera presentation. The adapter only rotates the requested input vector by the live 1ST/3RD yaw and quantizes it to Gold's native four cardinals before writing `World.heldDir`; it never touches continuous position or animation flags. This restores view-relative walking without reviving the removed v0.1.84 free-movement controller.

## v0.1.96 Android slider input fallback

The slider remains drawn in LOVE window units. v0.1.96 adds a direct `love.touch.getTouches()` / `love.touch.getPosition()` poll inside the Gold voxel render path. It captures only contacts whose current press begins inside the slider and applies the selected camera mode before `Voxel.setLevel()` for that frame. The existing Game2 wrappers remain as a low-latency path, while polling guarantees Android delivery if another input layer bypasses those wrappers.

## v0.1.94 Gold touch-host correction

The standalone Gold bridge passes its live `Game2` owner to `FirstPerson.install(game)`, but v0.1.93 called `CamControl.install()` with no host. `CamControl` therefore required `src.core.Game` and wrapped Gen-1 touch callbacks that never run during a Gold boot. The gesture recognizer itself was correct but unreachable.

`CamControl.install(game)` now follows the same host-injection contract as `FirstPerson.install(game)`. `GoldVoxelBridge.bindGame(game)` passes the current Gold owner into it. `surveyStep()` also detects `game.world:zoomStep()` and uses that for Gold, falling back to Gen-1 only when no Gold world exists.

## v0.1.93 Gold pinch-zoom activation

The embedded `lib/CamControl.lua` already implemented the intended shared zoom input layer, including a two-finger touch recognizer, pinch slack, ThirdPerson continuous boom scaling, survey-zoom accumulation, and coordination with `FirstPerson.dropLook/reseatLook`. The standalone Gold bridge previously loaded `FirstPerson` and `GoldCameraControls` but never loaded/installed `CamControl`, so none of those pinch paths were reachable in Gold/Silver.

`lib/GoldVoxelBridge.lua` now loads `CamControl` and installs it immediately after `FirstPerson.install()`. That ordering is intentional: CamControl becomes the outer touch wrapper, recognizes two open-screen fingers, claims pinch movement before it reaches the look-drag wrapper, and forwards unrelated touches to the normal engine/Character Selector handlers. The bridge exposes `pinchZoomInstalled` / `pinchZoomError` in its diagnostics status.

## v0.1.92 seamless live-world battle start

Current Gold always enters a wild battle through `World:pushBattleTransition()`, which pushes `Gen2BattleTransition` and draws the native expanding black-circle wipe before the battle state appears. In this mod's **LIVE OVERWORLD BATTLES** mode, that wipe no longer matches the presentation because the player is not actually leaving the encounter-site world.

`lib/OverworldBattle.lua` now short-circuits the wrapped `src.world.gen2.World:pushBattleTransition()` path for ordinary wild encounters when `battle3dWorld` is enabled. The mod still snapshots/begins the live-world battle session first, but then returns `false` instead of pushing `Gen2BattleTransition`. Gold's own `World:startBattle()` already interprets a falsey transition result as "push `Gen2BattleState` immediately", so the battle UI/logic stays native while the transition screen is skipped cleanly.

Trainer battles, Safari/contest/tutorial paths, and the classic presentation used when **LIVE OVERWORLD BATTLES** is OFF still use Gold's normal transition behavior.

## v0.1.91 red_3d_player camera bridge

The Character Selector changes Gen1Recomp's public `src.render.Pipelines` level for the `voxel` pipeline. This standalone Gen-2 renderer intentionally does not register a normal drawWorld pipeline, so its private `VoxelState` previously ignored that public level and reapplied `cameraMode` every frame. `GoldVoxelBridge` now reads `Pipelines.levelLabel("voxel")` while `red_3d_player` owns camera control and maps labels containing `1ST`/`FIRST` to the private first-person rung and `3RD`/`THIRD` to the private third-person rung; every ordinary orbit/ZOOM label maps to the diorama rung. Using labels rather than fixed rung integers keeps the bridge compatible with upstream voxel ladder changes.

`FirstPerson.install` still mirrors look input into the private renderer so its placed camera remains visually synchronized, but mouse/touch look events are forwarded to the previously installed handler while external camera ownership is active. `GoldCameraControls` also checks the same ownership function after calling its inner `World:pollInput`: when Character Selector owns the camera, the adapter returns without quantizing or rewriting `heldDir`, preserving whichever Gen-2 movement layer the selector installed regardless of mod load order.

## v0.1.90 battle toggle

Gold reads the `battle3dWorld` option lazily through `OverworldBattle.enabled()`. The option now appears as **LIVE OVERWORLD BATTLES**, defaults to `true`, and cleanly returns `false` before any live-world battle compositor/model staging when disabled, so Gold's normal `BattleState` presentation remains authoritative.

## v0.1.89 Gold-only cleanup and battle compositor

Gold's in-world battle path no longer uses `BattleScene.render` for its backdrop. `OverworldBattle.update` renders the captured Gold state through the same `VoxelScene.render` path used in free roam and marks that state as a live Stadium battle so `VoxelScene` draws/casts the two Stadium models in normal world space. The battle camera therefore stays identical to the encounter camera.

Current Gold `BattleAnimView.present` assumes an opaque battle BG and fills/blits blank scanlines while applying SCX/SCY/BGP effects. With a transparent battle panel that exposed the classic white rectangle (and black outside it) during moves. The Gold shim now bypasses only that background-transform pass while a live-world shot is active; the caller still executes `drawObjects`, so Gold's OBJ move effects continue to render.

The package is also generation-trimmed: only Dex 1–251 generated sprite runtime sheets remain. Raw build-source follow/water atlases and legacy Gen-1-only startup modules are intentionally not shipped.

## v0.1.87 Gold follower / battle / movement correction

### Movement ownership restored
`lib/GoldCameraControls.lua` is back to the v0.1.80-style adapter: camera-relative intent is quantized to Gold's native cardinal `heldDir`. The continuous free-walk position layer is no longer part of this project. `lib/OverworldStadium.lua` no longer overrides player facing from a continuous body yaw and no longer temporarily sets `Player.moving=true` around `red_3d_player` draws.

### Lead-party follower
`lib/GoldPartyFollower.lua` opts into current Gen1Recomp's `src.world.gen2.Follower.setShouldSpawn()` surface. Party slot #1 is authoritative; the engine owns trail movement/map seams, while renderer metadata points the follower entity at the live party mon for Stadium model selection.

### Why v0.1.85/0.1.86 in-world battles did not appear
Current Gold pushes `src.ui.gen2.BattleState`, not `src.battle.BattleState`, and that Gen-2 screen intentionally has no `isBattle=true` marker. The old hook patched the Gen-1 class and waited for `top.isBattle`, so it never owned current Gold's actual battle UI. There was a second Lua bug in `OverworldBattle.begin`: `isGoldGame() and nil or battle` evaluates to `battle` even when Gold is true, because Lua's `and/or` idiom cannot select nil. The session therefore held the Gen-2 battle logic object rather than waiting for its BattleState screen.

v0.1.87 matches the live screen by `top.battle == session.logicBattle`, updates Stadium models through a dedicated Gen-2 adapter, and patches only the Gen-2 presentation layer: the 160x144 white field becomes transparent after a valid voxel shot exists, and each flat Pokemon picture is skipped only when its corresponding Stadium model is healthy and visible. `GoldComposeBridge` alpha-composites that native UI over the window-resolution battle-world canvas.

## v0.1.83 weather fail-safe

The v0.1.82 package contained the intended `Weather.lua` integration in `Voxel3D.lua`, but also had an accidental `VoxelScene.lua -> V.require("WeatherFX")` duplicate. The standalone Gold module loader treats a missing local module as a hard require failure, which caused `GoldVoxelBridge.install()` to fail and the compose layer to fall back to vanilla 2D. v0.1.83 removes the duplicate require/calls. Every remaining `Weather.lua` invocation is guarded with `pcall`; weather is now strictly optional presentation and cannot retire the voxel renderer.

## v0.1.82 weather/sky implementation

`lib/WeatherFX.lua` adds a lightweight atmospheric pass to the standalone Gold/Game2 voxel renderer. `lib/VoxelScene.lua` now calls it twice per frame: once immediately after `Voxel3D.beginScene()` to paint drifting cloud shapes into the already-cleared sky background, and once after the world draw to apply optional fog and rain overlays. The existing `Sky.lua` / `DayNight.lua` path is still authoritative for the sun/moon disc and day-night colouring, so this release layers weather on top of the established sky rather than replacing it.

New options:
- `weatherMode` = `auto | clear | rain | fog | rain_fog | off`
- `skyClouds` = `true | false`

## v0.1.81 packaging change

The mod manifest now sets `experimental` to `false`. Runtime/gameplay code is otherwise the v0.1.80 camera-relative-controls build.

## v0.1.81 camera-relative Gold movement

Gold's native `World:pollInput(input)` stores a world-axis `heldDir`. The first/third-person camera had already rotated visually, but that input was never rotated, producing 2D-feeling movement. `lib/GoldCameraControls.lua` wraps only the Gen-2 poll seam: after vanilla polling (so forced/downhill rules remain available), an actual player movement vector is rotated through `FirstPerson.moveWorld()` and quantised to the nearest Gold cardinal. No continuous-position replacement is used, so `Player:tryMove`, collision, connections, warps, step events, and scripted states remain engine-owned.

# v0.1.79 camera implementation notes

## Gold camera host

The embedded Dramatic Shapes package already contained `FirstPerson.lua` and `ThirdPerson.lua`, but the standalone Gold provider intentionally skipped the old Gen-1 pipeline/input installer and forced `Voxel.setLevel(1)` every frame. v0.1.79 keeps the standalone compose architecture and activates only the camera pieces needed by Gold. `GoldComposeBridge` hands the live Game2 owner to `GoldVoxelBridge`, which publishes it as `V.game`; the camera modules use `game.world` for Gold and keep `Game.overworld` as a Gen-1 fallback.

Gold free roam is treated as `game.world.map` with an empty stack. Any pushed START/text/dialog state makes `FirstPerson.onTop()` false. Look input stops at that point and relative mouse capture is released, while the existing Gold compose bridge continues drawing the UI above the voxel canvas.

## Camera selection

The new `cameraMode` option maps directly to the already-authored VoxelState levels: DIORAMA -> FULL level 1, FIRST PERSON -> level 6, THIRD PERSON -> level 7. The provider ticks `Voxel.update()` and `FirstPerson.update()` with real frame time (clamped for long stalls) before `VoxelScene.render()`. F6 changes the same mode at runtime and attempts to persist it through `mod.options:set` when that API is present; a runtime override keeps the hotkey functional when persistence is unavailable.

Third-person camera collision continues to query the active Gold map's common `inBounds` / `isWalkableCell` surface and the voxel terrain height field. First-person local-player hiding and third-person selected-skin visibility remain owned by the existing VoxelScene/Skin Selector patch, so no duplicate player renderer was added.

## Input scope

This release intentionally leaves Gold's normal grid movement and special movement logic alone. The camera reads mouse/right-stick/touch look input only while its free-roam camera is active. Mouse buttons remain mapped through the existing camera input bridge while relative mode is captured, and unclaimed mouse releases now forward to the engine instead of being swallowed.

---

# v0.1.78 implementation notes

## Root cause: current Gold tileset IDs never reached the authored profile

The tree mesh itself was not the remaining failure. Current Gen1Recomp Gold indexes generated tilesets with constants such as `TILESET_JOHTO`; `World:atlasFor()` returns that tileset record to the mod. The embedded voxel profile, however, is keyed with extraction-style names such as `TilesetJohto`. `TileShape.forMap()` and `Structures` resolve their authored rows through `tileset.id`, so a runtime id left as `TILESET_JOHTO` makes the Johto profile miss and leaves blocked scenery on the generic wall fallback.

v0.1.78 normalizes only the voxel-facing tileset record id in `GoldVoxelBridge.attachRenderer`: `TILESET_FOO_BAR` becomes `TilesetFooBar`. `map.def.tileset` stays unchanged, so Gen1Recomp continues indexing `world.tilesets` with its own native key. The original record id is retained in `_stadiumEngineTilesetId` for diagnostics. This activates the pre-existing Johto `cylinder`/`planter` tree pins and the v0.1.77 stepped tree archetype before the generic volume mesher runs.

## Earlier tree fallback work retained

## Gold outdoor tree-border correction

The tree-block artefact had two related fallbacks. First, `Structures.forMap()` shortened the synthetic forest ring only for the Gen-1 literal `def.tileset == "OVERWORLD"`. Gold outdoor maps are identified through their Gen-2 environment instead, so the repeated Gold `borderBlock` could continue past the expensive round-hull belt and reach the generic rectangular mesher. v0.1.76 detects Gold outdoors with `Map.isOutdoor(def)` and enables the forest-ring treatment only when the actual border block contains multiple tiles the active voxel profile names as `cylinder`, `planter`, or `canopy`.

Second, a cache/blockset variation can leave a real Gold tree cell on the generic blocked-cell `upright` fallback. After normal `TileShape.at()` resolution, v0.1.76 inspects only unresolved 16x16 cells in the real outdoor map body. If at least two of the four source 8x8 tiles are explicit round-tree profile tiles, only the unauthored fallback shapes in that cell are promoted to `cylinder`. Existing authored `planter`, `canopy`, building, cliff, sign, fence, and other pins remain untouched.

The promotion happens before `Structures.buildCylinders()`, so the existing pixel-carved `roundTemplate()` path claims the tree graphics and synthesizes their ground rather than allowing the volume path to build a texture-covered box. Collision is unchanged.

## v0.1.75 red_3d_player / Skin Selector bridge


`red_3d_player` already supports Gold by replacing `src.world.gen2.Player:draw()` and publishing its live ActiveRenderer as `Player.red3dPlayerRenderer`. The standalone Stadium 2 voxel renderer does not call `Player:draw()`; it captures the player as a VoxelScene pose and renders that pose directly. That is why the selector UI and saved character could work while the voxel-world player stayed on the stock trainer card.

The Stadium VoxelScene patch now gives the human player pose to `OverworldStadium.safeDrawPlayerSkin()` before the Stadium-Pokémon and sprite-card fallbacks. The bridge resolves `Player.red3dPlayerRenderer` dynamically and delegates to the selector's own `drawVoxel()` method with this renderer's `Voxel3D`, `Mat4`, and `FirstPerson` modules. The same approach is used best-effort for `drawVoxelShadow()`. No selector models or textures are copied into this package.

The bridge deliberately declines player-as-Pokémon control and Gold's fishing/bike/surf states. Those continue through the existing Stadium/native special-card paths. Because the renderer pointer is read live, selector changes and imported skins do not require a Stadium reload.

# v0.1.71 implementation notes

Current Gold's `World:tryWildEncounter()` checks `Roamers.checkEncounter()` before it reaches `Runtime.call("encounter.roll", ...)`. The v0.1.70 Wilds hook could therefore suppress ordinary table rolls yet still allow a rare invisible roaming-beast step battle. v0.1.71 wraps only `World:tryWildEncounter` and returns false when visible-only mode is active. Explicit encounter systems use other methods and are left intact.

The saved-options migration marker is `_visible_only_v171`. It is intentionally one-shot: inherited v0.1.70 `random_encounters=true` becomes false, but a player who later turns Classic Step Enc back ON is not fought by the migration on every boot.

# v0.1.70 implementation notes

## Current Gold rendering seam

Gold now exposes `render.compose` after its finished scene has been drawn into `sceneCanvas`. v0.1.70 registers one high-priority compose wrapper and uses the payload's `generation == 2` and `worldActive` flags to restrict ownership to live Gold overworld frames.

`lib/GoldComposeBridge.lua` gives the voxel provider first chance. If a voxel canvas is returned, it owns the window for that free-roam frame. If voxel is pending or fails, the compose bridge re-blits `ctx.sceneCanvas` and calls the visible-Wilds fallback renderer. If neither path has work, it delegates to the next compose hook / normal Gold present.

Frames with an active non-opaque Gold stack overlay remain voxel-owned; the bridge redraws only the stack above the voxel frame using Gold's native UI transform.

## Gold encounter adaptation

Current Gold's generated encounter data is grouped under `game.data.gen2Encounters` and is also available from the live world as `world.encounters`:

- `encounters.grass[mapId].slots.MORN|DAY|NITE`
- `encounters.grass[mapId].rates.MORN|DAY|NITE`
- `encounters.water[mapId]`

`lib/spawn_logic.lua` normalizes that structure into the Wilds per-map format before surface selection and weighted spawning. The current live Gold `daytime/tod` chooses the grass slot list.

## Why world.entities was insufficient

Gold rebuilds both `npcs` and `entities`, but its normal `World:drawPeople()` constructs the visible list from the player, `npcs`, and connection ghosts. A Wilds entity living only in `world.entities` can participate in collision/update helpers yet never be drawn by the native people pass.

`lib/GoldWildsBridge.lua` therefore owns visibility separately. It reads the embedded Wilds logic entity table, filters current-map visible wild Pokemon, and exposes the same list to:

1. the compose-time 2D fallback renderer; and
2. the voxel/Stadium entity merger.

The bridge does not permanently add roaming Pokemon to Gold's script-NPC list, avoiding trainer/talk-script semantics.

## Compose-time self-heal

`GoldWildsBridge.visibleEntities()` checks whether the Wilds logic is initialized for the current map. If not, it retries `onMapEntered` through a once-per-second self-heal path. This supplements the normal `map.entered`, `save.loaded`, and `game.ready` bootstrap listeners without running expensive initialization every frame.

## Voxel provider

`lib/GoldVoxelBridge.lua` is a provider rather than an engine patch. It prepares the embedded voxel modules, adapts the current Gold map/tileset atlas, merges player + native NPCs + Wilds roaming entities, and returns a rendered canvas to the compose bridge. A nil canvas is treated as a normal mesh-pending state and falls back to flat Gold + visible Wilds for that frame.


## 0.1.74 Gold overlay-stack correction

Current `src/core/Game2.lua` intentionally gives `render.compose` a single finished Gold scene: `worldCanvas`, `uiCanvas`, and `sceneCanvas` all reference that same texture. The v0.1.73 Gen-1-style `worldOverride` approach therefore could not preserve the Gold UI as a separate pass.

For a live overworld frame (`ctx.generation == 2` and `ctx.worldActive == true`), the bridge now owns the frame, draws the voxel canvas, and then redraws only `host.stack`. The stack is transformed exactly like Game2's live-overworld branch: `world:fitScale()` with a centered 160x144 UI. This keeps START/textbox/non-opaque overlay screens above the 3D world without reintroducing the vanilla 2D map. Game2 excludes opaque/widescreen pages before setting `worldActive`, so those screens continue through the stock full-screen renderer.

## 0.1.73 compose/UI changes

- Removed the deliberate overlay-stack 2D passthrough that made START/pause switch the overworld out of voxel mode.
- On current Gen1Recomp, successful voxel frames are installed with `Renderer:setWorldOverride()` and the hook returns to the stock compositor.
- The engine therefore keeps ownership of the UI pass, including START menus, dialogs, dynamic anchors, fades, wipes, and post-processing, while the world underneath remains voxel.
- Kept a legacy direct-draw fallback only for older experimental compose hosts that do not expose a world override seam.

## 0.1.72 voxel-only changes

- Gold door cells: use `isDoorTileCell(cx, cy)` when available; retain the Gen-1 `doorTiles` table only as fallback.
- Gold warp cells: treat `warpAt` as a method when it is one; never index a function.
- Current-map terrain is primed synchronously once per map through `ChunkMesher.get()`.
- `ChunkMesher.lastError(mapId)` distinguishes failed builds from legitimate pending async work.
- `GoldVoxelBridge` targets FULL level 1 and reports sync-build counters/errors in `voxelStatus()`.
- Wild encounter/spawn behavior was deliberately not changed in this release.



### v0.1.82 weather renderer
`Weather.paintSky` renders clouds after the day/night sky but before world depth. `Weather.paintOverlay` renders rain/fog before the 3D canvas is returned to Gold compose, so START/text UI remains clean above the weather.

## v0.2.21 - Dex 249 diagnostic isolation

The Lugia investigation is now completely side-band. `lib/LugiaGeoDump.lua` reparses only the original Dex-249 FRAGMENT for logging and never feeds values back to `StadiumFragment`, `StadiumBuild.pack`, `StadiumRig`, or `StadiumPack`. This is specifically designed to prevent another all-Pokemon regression while capturing the static transform and display-list nodes the simplified extractor currently discards.


### v0.2.67 desktop voxel recovery
A fresh Gold options block defaults native `TILT` to OFF/0. While `3D VOXEL WORLD` is enabled, that OFF value now selects the voxel renderer's normal 35-degree diorama camera rather than a literal 0-degree/flat camera. Gold TILT 15/35/50 continue to map directly to those voxel pitches; disable `3D VOXEL WORLD` for the native 2D overworld.
