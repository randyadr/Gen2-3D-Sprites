-- Pokemon Stadium 2 Overworld Models - Gold/Silver (Generation 2)
--
-- Standalone Gen1Recomp Gold/Gen-2 graphics/gameplay mod. It embeds the Gen2 Dramatic Shapes
-- voxel renderer and the Wilds of Kanto roaming-Pokemon runtime, but contains no
-- Pokemon Stadium 2 ROM or ROM-derived model data. Models are built locally
-- from the player's own compatible Stadium 2 ROM.
local mod = ...

-- This package has its own Gen2-only mod id. Keep a runtime generation guard
-- anyway so accidentally enabling it on Red/Blue/Yellow fails closed.
local function gameGeneration()
  local ok, GameVersion = pcall(require, "src.core.GameVersion")
  if ok and type(GameVersion) == "table" then
    if type(GameVersion.generation) == "function" then
      local okGen, generation = pcall(GameVersion.generation)
      if okGen and tonumber(generation) then return tonumber(generation) end
    end
    if type(GameVersion.isGen2) == "function" then
      local okGen2, yes = pcall(GameVersion.isGen2)
      if okGen2 and yes then return 2 end
    end
  end
  return 1
end

local function isGen2()
  return gameGeneration() == 2
end

local detectedGeneration = gameGeneration()
if detectedGeneration == 2 then
  mod.log:info("Gold/Silver standalone build: Pokemon Generation 2 detected; Stadium 2 importer targets National Dex 1-251")
else
  mod.log:warn("STADIUM2_OVERWORLD_MODELS requires Pokemon Gold or Silver. Active game reports Pokemon Generation %s; this Gen 2 port will stay inactive.", tostring(detectedGeneration))
  mod.exports.version = "0.2.81"
  mod.exports.targetGeneration = 2
  mod.exports.generation = detectedGeneration
  mod.exports.gen2Compatible = true
  mod.exports.stadium2Importer = true
  mod.exports.standaloneRenderer = true
  mod.exports.maxDex = 251
  mod.exports.active = false
  mod.exports.rendererInstalled = false
  mod.exports.rendererError = "Pokemon Gold/Silver (Generation 2) must be the active game"
  return
end

-- Wilds of Kanto's embedded entry returns an installer factory instead of
-- executing directly.  Run it against THIS mod object, capture the child's
-- public surface, then restore this package's Stadium exports.  v0.1.74 keeps
-- this definition in the top-level entry: an earlier direct-world refactor
-- accidentally deleted it while leaving the call site behind, which made the
-- mod abort late in main.lua after its Options UI had already been registered.
local function bootEmbeddedWilds()
  local source, readErr = mod:read("lib/EmbeddedWildsMain.lua")
  if not source then return nil, tostring(readErr or "embedded Wilds runtime is missing") end
  local loadcode = loadstring or load
  local chunk, compileErr = loadcode(source, "@" .. mod.path .. "/lib/EmbeddedWildsMain.lua")
  if not chunk then return nil, tostring(compileErr) end

  local okFactory, factory = pcall(chunk)
  if not okFactory then return nil, tostring(factory) end
  if type(factory) ~= "function" then
    return nil, "embedded Wilds entry did not return its installer function"
  end

  mod.exports = mod.exports or {}
  local before = {}
  for k, v in pairs(mod.exports) do before[k] = v end

  local okRun, runErr = pcall(factory, mod)
  if not okRun then
    for k in pairs(mod.exports) do mod.exports[k] = nil end
    for k, v in pairs(before) do mod.exports[k] = v end
    return nil, tostring(runErr)
  end

  local wilds = {}
  for k, v in pairs(mod.exports) do
    if before[k] ~= v then wilds[k] = v end
  end

  for k in pairs(mod.exports) do mod.exports[k] = nil end
  for k, v in pairs(before) do mod.exports[k] = v end

  if type(wilds.logic) ~= "table" or type(wilds.render) ~= "table" then
    return nil, "embedded Wilds runtime did not expose spawn logic/render services"
  end
  return wilds
end

-- Gold/Silver renderer bootstrap (v0.2.70: current drawWorld + compose coexistence)
--
-- GoldVoxelBridge is the renderer provider only: it prepares the embedded voxel
-- scene and exposes renderFrame(world, ctx). GoldPipelineBridge connects it to
-- current Gen1Recomp's engine-owned drawWorld seam, while GoldComposeBridge
-- remains the older-host and Character Selector coexistence path.
local function bootGoldVoxelBridge()
  local source, readErr = mod:read("lib/GoldVoxelBridge.lua")
  if not source then return nil, nil, tostring(readErr or "Gold voxel bridge is missing") end
  local chunk, compileErr = load(source, "@" .. mod.path .. "/lib/GoldVoxelBridge.lua")
  if not chunk then return nil, nil, tostring(compileErr) end
  local okLoad, Bridge = pcall(chunk, mod)
  if not okLoad then return nil, nil, tostring(Bridge) end
  if type(Bridge) ~= "table" or type(Bridge.install) ~= "function" then
    return nil, nil, "Gold voxel bridge did not expose install()"
  end
  local okInstall, installed, libOrErr = pcall(Bridge.install)
  if not okInstall then return nil, nil, tostring(installed) end
  if not installed then return nil, nil, tostring(libOrErr or "Gold voxel bridge install failed") end
  local lib = libOrErr or Bridge.lib
  if type(lib) ~= "table" or type(lib.require) ~= "function" then
    return nil, nil, "Gold voxel bridge did not expose its renderer module loader"
  end
  return Bridge, lib
end

local GoldVoxelBridge, BaseV, bridgeErr = bootGoldVoxelBridge()
local ds, dramaticShapeId
if GoldVoxelBridge and BaseV then
  ds = mod
  dramaticShapeId = "STADIUM2_GOLD_COMPOSE"
  mod.log:info("Gold/Silver voxel renderer provider loaded; current Gold drawWorld pipeline will own world frames when available, with render.compose retained as fallback")
else
  mod.log:error("Gold/Silver voxel renderer provider failed: %s", tostring(bridgeErr))
  mod.exports.version = "0.2.81"
  mod.exports.rendererInstalled = false
  mod.exports.rendererError = "Gold/Silver voxel renderer provider failed: " .. tostring(bridgeErr)
  mod.exports.hostDetected = false
  mod.exports.generation = gameGeneration()
  mod.exports.gen2Compatible = true
  mod.exports.targetGeneration = 2
  mod.exports.stadium2Importer = true
  mod.exports.standaloneRenderer = true
  mod.exports.maxDex = 251
  return
end

-- v0.1.89 is a Gen-2-only runtime. Legacy Yellow/Followers-EX glue was
-- intentionally removed. The embedded Wilds trailer mover owns the visible
-- Gold follower; the native Gen-2 follower bridge below is cleanup/fallback only.

local function loadLocal(rel, arg)
  local source, readErr = mod:read(rel)
  assert(source, ("STADIUM2_OVERWORLD_MODELS: missing %s: %s")
    :format(rel, tostring(readErr)))
  local chunk, err = load(source, "@" .. mod.path .. "/" .. rel)
  assert(chunk, ("STADIUM2_OVERWORLD_MODELS: %s did not compile: %s")
    :format(rel, tostring(err)))
  return chunk(arg)
end

-- v0.2.64 recovery guard: optional post-v0.2.45 helpers must never be able to
-- abort Gold's boot. Their installers patch presentation/settings seams only;
-- if one is incompatible with a particular Gen1Recomp build, log it and keep
-- the proven core voxel/world renderer alive.
local function safeInstall(label, module)
  if not (module and type(module.install) == "function") then
    return false, label .. " has no install()"
  end
  local ok, installed, err = pcall(module.install)
  if not ok then
    local message = tostring(installed)
    mod.log:warn("%s disabled after install error: %s", label, message)
    return false, message
  end
  if installed == false then
    local message = tostring(err or "installer returned false")
    mod.log:warn("%s not installed: %s", label, message)
    return false, message
  end
  return true, err
end

local function safeLoadLocal(label, rel, arg)
  local ok, module = pcall(loadLocal, rel, arg)
  if ok and type(module) == "table" then return module end
  local message = tostring(ok and "module did not return a table" or module)
  mod.log:warn("%s disabled after load error: %s", label, message)
  return {
    install = function() return false, message end,
    status = function() return { installed = false, lastError = message } end,
  }
end

-- Load our configuration first, then make a tiny namespace that delegates all
-- Dramatic Shape modules to Dramatic Shape while intercepting our own config.
local Config = loadLocal("lib/OverworldStadiumConfig.lua", BaseV)
local PokemonHeights = loadLocal("lib/PokemonHeights.lua", BaseV)
local PokemonLocomotion = loadLocal("lib/PokemonLocomotion.lua", BaseV)

-- Gold exposes an engine-owned party-follower surface, but embedded Wilds
-- already owns a map-safe trailer mover and follower selection. v0.2.73 keeps
-- Wilds as the single visible follower owner (including slot #1); this bridge
-- disables/cleans native Gold copies and retains the engine follower only as a
-- fallback if the embedded Wilds follower runtime ever fails to boot.
local GoldPartyFollower = safeLoadLocal("Gold party follower bridge", "lib/GoldPartyFollower.lua", { mod = mod })
local goldPartyFollowerInstalled, goldPartyFollowerErr =
  safeInstall("Gold party follower bridge", GoldPartyFollower)
if goldPartyFollowerInstalled then
  mod.log:info("Gold follower ownership bridge installed; embedded Wilds owns slot #1 with native Gen-2 fallback only")
end

-- Put Stadium ROM selection inside THIS MOD'S Mod Manager -> Options screen.
-- The manifest also ships options.lua so the recomp mod manager exposes an OPTIONS button
-- for this mod.  StadiumRomMenu converts the STADIUM ROM FILE row into a real
-- Android file-picker action (A/Confirm, Left, or Right all open the system Files picker).
local RomMenuV = { require = BaseV.require }
local StadiumRomMenu = loadLocal("lib/StadiumRomMenu.lua", RomMenuV)
local managerOptionsInstalled = StadiumRomMenu.installModManagerOptions(mod)

-- v0.2.38: patch Gold's REAL Gen-2 START / pause screen (src.ui.gen2.StartMenu),
-- the PACK / PokéGEAR / player / SAVE menu visible during gameplay.  Its
-- engine-owned update/choose/close logic stays intact; only draw() is replaced
-- with the exact custom PACK/PKMN battle-selector visual language.
local PauseMenuBattleStyle = safeLoadLocal("Battle-style pause menu UI", "lib/PauseMenuBattleStyle.lua", { mod = mod })
local pauseStyleInstalled, pauseStyleErr =
  safeInstall("Battle-style pause menu UI", PauseMenuBattleStyle)

-- v0.2.39: the pause menu now grows tall enough to expose its normal complete
-- row set, and every built-in Gold screen launched from it receives the same
-- custom battle-selector presentation.  The constructors are tagged only when
-- StartMenu is the caller, so Party/Pack/Pokedex/Pokegear screens used by
-- battles, scripts and other engine flows keep their native presentation.
-- v0.2.41 introduced PartyModelPreview. v0.2.42 makes Party/Summary skinning
-- deterministic on Gen1Recomp v0.1.83 (not dependent on StartMenu constructor
-- timing) and BattleControllerUI now uses the same preview in its live 3D PKMN
-- selector. Pass the renderer namespace so both paths share StadiumMon/Voxel3D.
local GoldSubmenuBattleStyle = safeLoadLocal("Battle-style Gold pause submenus", "lib/GoldSubmenuBattleStyle.lua", BaseV)
local submenuStyleInstalled, submenuStyleErr =
  safeInstall("Battle-style Gold pause submenus", GoldSubmenuBattleStyle)

-- v0.2.77: split character presentation into independent Pokemon-model and
-- human-player-model switches. Stadium Pokemon geometry remains controlled by
-- stadium3dSprites; red_3d_player's selected Gold skin is controlled separately
-- by player3dModel so either layer can fall back to its 2D Gold card alone.
-- v0.2.76: extend the same Stadium glass language to ordinary Gold dialogue
-- and YES/NO prompts. TextBox/ChoiceBox keep all engine timing, paging and
-- input; only their draw methods are replaced while CUSTOM UI / MENUS is ON.
local TextBoxBattleStyle = safeLoadLocal(
  "Battle-style dialogue boxes", "lib/TextBoxBattleStyle.lua", { mod = mod })
local textBoxStyleInstalled, textBoxStyleErr =
  safeInstall("Battle-style dialogue boxes", TextBoxBattleStyle)

-- v0.2.76: widen both this renderer's continuous diorama range and the
-- engine-native survey ladder used by Character Selector/native ZOOM. The
-- official zoom.range hook adds one 0.25-scale whole-region rung in OPEN WORLD.
local OpenWorldZoom = safeLoadLocal(
  "OPEN WORLD extended zoom", "lib/OpenWorldZoom.lua", { mod = mod })
local openWorldZoomInstalled, openWorldZoomErr =
  safeInstall("OPEN WORLD extended zoom", OpenWorldZoom)

-- v0.2.40: MODS now opens a fully matching glass submenu.  The Mod Manager's
-- installed-mod list, per-mod detail menu, OPTIONS submenu, permissions,
-- errors, profiles, apply/restart prompts and confirmation overlays all use
-- the same battle-selector visual language.  Any mod using options_schema is
-- covered automatically.  A screen.pushed watcher also skins conventional
-- list-like menus opened by hook-injected START-menu rows while leaving custom
-- renderers it cannot safely understand untouched.
local ModMenuBattleStyle = safeLoadLocal("Battle-style mod menus", "lib/ModMenuBattleStyle.lua", { mod = mod })
local modMenuStyleInstalled, modMenuStyleErr =
  safeInstall("Battle-style mod menus", ModMenuBattleStyle)

-- v0.2.55: Gen-2 ManagerState writes live option values correctly but the
-- v0.1.83 Gold path persists through Game2:persistOptions rather than the
-- writeOptions name ManagerState probes. Bridge that seam so every toggle and
-- choice on this mod's MOD SETTINGS page survives a restart.
local ModSettingsPersistence = safeLoadLocal("Gold mod-settings persistence bridge", "lib/ModSettingsPersistence.lua", { mod = mod })
local persistenceInstalled, persistenceErr =
  safeInstall("Gold mod-settings persistence bridge", ModSettingsPersistence)

-- v0.2.56: this mod now has enough controls that one flat ManagerState list is
-- awkward on phones. Keep ManagerState as the value/persistence owner, but
-- present this mod through category submenus (world/performance, camera/display,
-- battle, 3D models, wild Pokemon, followers/behavior, developer).
local CategorizedModSettings = safeLoadLocal("Categorized mod settings", "lib/CategorizedModSettings.lua", { mod = mod })
local categorizedInstalled, categorizedErr =
  safeInstall("Categorized mod settings", CategorizedModSettings)

-- v0.2.56: screenFlip is no longer a render.compose-only transform. Gold draws
-- HUD/touch controls after compose, so the compatibility flip now wraps the
-- entire Game2:draw frame and inversely remaps Android touch coordinates.
local AndroidFullFrameFlip = safeLoadLocal("Android whole-frame flip", "lib/AndroidFullFrameFlip.lua", { mod = mod })
local fullFrameFlipInstalled, fullFrameFlipErr =
  safeInstall("Android whole-frame flip", AndroidFullFrameFlip)

-- v0.2.52: put THIS mod's settings directly on Gold's START menu immediately
-- below OPTION.  It uses the official ui.start_menu.items hook and opens the
-- existing ManagerState options page, so option persistence/events remain
-- engine-owned.  B from that direct page returns straight to the pause menu.
local DirectModSettingsMenu = safeLoadLocal("Direct pause-menu MOD SETTINGS shortcut", "lib/DirectModSettingsMenu.lua", { mod = mod })
local directSettingsInstalled, directSettingsErr =
  safeInstall("Direct pause-menu MOD SETTINGS shortcut", DirectModSettingsMenu)

-- Compatibility fallback only for much older builds without per-mod options.
-- On current builds this never runs, so the ROM row lives only under this
-- mod's own Options screen rather than the game's general OPTIONS menu.
if not managerOptionsInstalled then
  StadiumRomMenu.installOptionsHook(mod)
end

-- Gold voxel renderer status. v0.2.73 targets current Gen1Recomp's official
-- render_pipelines.drawWorld seam again, while preserving render.compose as a
-- real compatibility/coexistence fallback. In particular, red_3d_player owns
-- the engine's public `voxel` pipeline ladder; when that selector is installed
-- GoldPipelineBridge intentionally stays OFF so the selector is not disabled by
-- Gen1Recomp's one-world-pipeline rule. GoldComposeBridge then owns the window
-- and OverworldStadium draws the selector's chosen skin into the voxel scene.
local GoldPipelineBridge = safeLoadLocal(
  "Gold drawWorld voxel pipeline", "lib/GoldPipelineBridge.lua",
  { mod = mod, VoxelBridge = GoldVoxelBridge })
local goldPipelineInstalled, goldPipelineErr =
  safeInstall("Gold drawWorld voxel pipeline", GoldPipelineBridge)
local voxelPipelineState = goldPipelineInstalled and GoldPipelineBridge or GoldVoxelBridge
if goldPipelineInstalled then
  mod.log:info("Gold drawWorld voxel pipeline registered; render.compose remains fallback/Character Selector coexistence path")
else
  mod.log:warn("Gold drawWorld voxel pipeline unavailable; using render.compose: %s",
    tostring(goldPipelineErr))
end

-- Android may recreate the app while the native document picker is open.
-- Finish a pending Stadium selection as soon as the live Gold service owner is
-- ready.  Rendering itself is installed later through mod.hooks:wrap.
mod.events:on("game.ready", function(game)
  pcall(StadiumRomMenu.poll, game)
end)

mod.events:on("map.entered", function()
  if GoldVoxelBridge then GoldVoxelBridge.mapId = nil end
end)

-- Legacy Pokemon Yellow follower and Dramatic Sky Ride compatibility code
-- used Gen-1 `src.world.*` controllers and is not loaded in this Gold/Silver
-- package. Keeping it here only increased startup work and made the package
-- look less generation-specific, so v0.1.89 removes it.

local V = {
  mod = mod,
  path = mod.path,
  voxelHostId = dramaticShapeId,
}
setmetatable(V, { __index = BaseV })
function V.require(name)
  if name == "OverworldStadiumConfig" then return Config end
  if name == "PokemonHeights" then return PokemonHeights end
  if name == "PokemonLocomotion" then return PokemonLocomotion end
  if name == "BattleControllerUI" and V.BattleControllerUI then return V.BattleControllerUI end
  return BaseV.require(name)
end

local Stadium = loadLocal("lib/OverworldStadium.lua", V)
V.OverworldStadium = Stadium

-- Stage 1 battle performances: exact Stadium move animations when available,
-- entrance/faint animation, and a short victim recoil without touching damage
-- calculations or the engine's own move-effect graphics.
-- v0.2.29: direct control of the player's active Stadium 2 model during
-- Gold live-world battles. Left stick translates the presentation actor;
-- PlayStation Square / Xbox X plays an imported Stadium 2 attack clip.
local BattlePokemonControl = loadLocal("lib/BattlePokemonControl.lua", V)
-- v0.2.31 full controller-native live battle HUD. Gold still owns logic and
-- submenus, but its old 160x144 battle canvas is no longer composited during
-- the normal live 3D fight; this module draws HP/messages/commands/moves itself.
local BattleControllerUI = loadLocal("lib/BattleControllerUI.lua", V)
V.BattleControllerUI = BattleControllerUI
-- GoldVoxelBridge/VoxelScene were loaded before the Stadium namespace above and
-- retain BaseV as their module environment. Publish the UI on that shared table
-- too so the live renderer can resolve it without depending on the later
-- compositor or on a second module-loader namespace.
BaseV.BattleControllerUI = BattleControllerUI
mod.exports.battleControllerUI = BattleControllerUI
mod.events:on("game.ready", function(game)
  local ok, installed, err = pcall(BattleControllerUI.install, game)
  if not (ok and installed) then
    mod.log:warn("Battle controller UI input shortcuts not installed: %s",
                 tostring(ok and err or installed))
  end
end)

do
  local okS, StadiumControlHost = pcall(V.require, "Stadium")
  if okS and StadiumControlHost and type(StadiumControlHost.updateGen2) == "function"
      and not StadiumControlHost._directPokemonControlInstalled then
    local innerUpdateGen2 = StadiumControlHost.updateGen2
    StadiumControlHost.updateGen2 = function(dt, screen, groundY, ...)
      -- Keep battle input ownership refreshed every frame. This clears any
      -- stale native left-stick direction and provides a polled face-button
      -- fallback before the Stadium actor/camera are updated.
      pcall(BattleControllerUI.update)
      -- Apply stick motion before Stadium builds this frame's model matrix, so
      -- the actor and follow camera agree on the same position with no frame lag.
      pcall(BattlePokemonControl.update, dt, screen)
      return innerUpdateGen2(dt, screen, groundY, ...)
    end
    StadiumControlHost._directPokemonControlInstalled = true
  end
end

local BattleStadiumAnimations = safeLoadLocal("Pokemon Stadium Stage 1 battle performances", "lib/BattleStadiumAnimations.lua", V)
local battleAnimationsInstalled, battleAnimationsErr =
  safeInstall("Pokemon Stadium Stage 1 battle performances", BattleStadiumAnimations)
if battleAnimationsInstalled then
  mod.log:info("Pokemon Stadium Stage 1 battle performances enabled")
end

-- Phase 2 + Phase 3 + Phase 4 battle effects: common elemental families, dedicated
-- signature-move renderers, and safe visual hit-stop/shake/impact polish
-- drawn on the recomp engine's own move-animation layer. Dramatic Shape already maps
-- that layer onto the 3D arena, so this does not touch battle model lifecycle.
local BattleStadiumEffects = safeLoadLocal("Pokemon Stadium Phase 2 + Phase 3 + Phase 4 battle presentation", "lib/BattleStadiumEffects.lua", V)
local battleEffectsInstalled, battleEffectsErr =
  safeInstall("Pokemon Stadium Phase 2 + Phase 3 + Phase 4 battle presentation",
    BattleStadiumEffects)
if battleEffectsInstalled then
  mod.log:info("Pokemon Stadium Phase 2 + Phase 3 + Phase 4 battle presentation enabled")
end

-- Phase 5: real world-space procedural effects. This wraps Dramatic Shape's
-- exported Stadium begin/update/draw functions, so the particles are drawn
-- inside the active Voxel3D scene and follow camera orbit/depth naturally.
local BattleStadium3DFx = safeLoadLocal("Pokemon Stadium Phase 5 world-space effects", "lib/BattleStadium3DFx.lua", V)
local battle3DInstalled, battle3DErr =
  safeInstall("Pokemon Stadium Phase 5 world-space effects", BattleStadium3DFx)
if battle3DInstalled then
  mod.log:info("Pokemon Stadium Phase 5 world-space battle effects enabled")
end

-- Patch only structural seams in the exact VoxelScene source from the installed
-- Dramatic Shape build. Stadium operations are isolated per Pokemon, so one
-- bad model falls back to its own sprite without disabling the full overlay.
local VoxelScenePatch = loadLocal("lib/VoxelScenePatch.lua", V)
local rendererInstalled, rendererErr = VoxelScenePatch.install(ds, BaseV, V, Stadium)
if rendererInstalled then
  mod.log:info("Pokemon Stadium overworld renderer installed on current Dramatic Shape VoxelScene")
else
  mod.log:warn("Stadium overworld renderer not installed; Dramatic Shape voxel renderer preserved: %s",
               tostring(rendererErr))
end

-- Standalone roaming Pokemon.  Always boot the embedded, Gen-2-patched Wilds
-- runtime.  Do not let a separately installed Gen-1 Wilds build hijack this
-- package: independence means Gold uses the copy that was actually ported for
-- morning/day/night encounters and the Gen-2 world facade.
local wildsExports, wildsSource, wildsErr
wildsExports, wildsErr = bootEmbeddedWilds()
if wildsExports then
  wildsSource = "embedded"
  mod.log:info("Embedded Wilds of Kanto 1.12.2 Gen-2 roaming spawn runtime enabled")
else
  wildsSource = "failed"
  mod.log:warn("Embedded Wilds roaming spawn runtime failed; Stadium renderer remains available: %s",
               tostring(wildsErr))
end

-- v0.2.12: hold-to-aim overworld Poké Ball throw. Normal roaming-Pokemon
-- contact keeps Wilds' ordinary Gold battle path. While free-roaming the
-- capture module polls Gold's fixed-step input seam, so L2 / right mouse can
-- target a visible Pokemon in the camera cone and immediately throw before
-- contact. Any supported Gold Ball can be used; if prerequisites are missing,
-- the original Gold battle path remains unchanged.
local OverworldCapture, overworldCaptureInstalled, overworldCaptureErr
do
  local okCapture, captureOrErr = pcall(BaseV.require, "OverworldCapture")
  if okCapture and type(captureOrErr) == "table" then
    OverworldCapture = captureOrErr
    if wildsExports and type(wildsExports.logic) == "table"
       and type(OverworldCapture.install) == "function" then
      local okInstall, installed, err = pcall(OverworldCapture.install, wildsExports.logic)
      overworldCaptureInstalled = okInstall and installed ~= false
      if not overworldCaptureInstalled then
        overworldCaptureErr = tostring(okInstall and err or installed)
      end
    else
      overworldCaptureInstalled = false
      overworldCaptureErr = "visible Wilds runtime unavailable"
    end
  else
    overworldCaptureInstalled = false
    overworldCaptureErr = tostring(captureOrErr)
  end
end
if overworldCaptureInstalled then
  do
  local st = OverworldCapture and OverworldCapture.status and OverworldCapture.status() or {}
  mod.log:info("Overworld capture enabled (direct=%s manual=%s)",
               tostring(st.directHookInstalled), tostring(st.manualHookInstalled))
end
else
  mod.log:warn("Overworld capture minigame unavailable; normal battles preserved: %s",
               tostring(overworldCaptureErr))
end

-- Visible roaming Pokemon provider/fallback drawer.  This no longer patches
-- World:drawPeople; it stays independent from voxel and is consumed by the
-- supported Gold render.compose bridge below.
local GoldWildsBridge, goldWildsBridgeErr
if wildsExports then
  local source, readErr = mod:read("lib/GoldWildsBridge.lua")
  if source then
    local loadcode = loadstring or load
    local chunk, compileErr = loadcode(source,
      "@" .. mod.path .. "/lib/GoldWildsBridge.lua")
    if chunk then
      local okLoad, bridgeOrErr = pcall(chunk, mod, wildsExports)
      if okLoad and type(bridgeOrErr) == "table" then
        GoldWildsBridge = bridgeOrErr
        local okInstall, installErr = GoldWildsBridge.install()
        if not okInstall then
          goldWildsBridgeErr = tostring(installErr)
          GoldWildsBridge = nil
        end
      else
        goldWildsBridgeErr = tostring(bridgeOrErr)
      end
    else
      goldWildsBridgeErr = tostring(compileErr)
    end
  else
    goldWildsBridgeErr = tostring(readErr)
  end
  if GoldWildsBridge then
    mod.log:info("Gold visible-Wilds provider/fallback renderer ready")
  else
    mod.log:warn("Gold visible-Wilds provider failed: %s",
                 tostring(goldWildsBridgeErr))
  end
end

-- Feed the same visible roaming-Pokemon set into the voxel scene.  The Stadium
-- VoxelScene overlay can then replace those entities with their imported
-- Stadium 2 models; if voxel fails, GoldComposeBridge still draws their sprites.
if GoldVoxelBridge and GoldWildsBridge
   and type(GoldVoxelBridge.setExtraEntitiesProvider) == "function"
   and type(GoldWildsBridge.visibleEntities) == "function" then
  local okProvider, providerErr = GoldVoxelBridge.setExtraEntitiesProvider(function(world)
    return GoldWildsBridge.visibleEntities(world)
  end)
  if okProvider then
    mod.log:info("Gold visible-Wilds entities bridged into voxel/Stadium scene")
  else
    mod.log:warn("Gold Wilds voxel entity bridge failed: %s", tostring(providerErr))
  end
end

-- Gold compose fallback/coexistence path. Current Gold normally reaches voxels
-- earlier through GoldPipelineBridge/render_pipelines.drawWorld. Older hosts,
-- and installations with red_3d_player (whose own public `voxel` pipeline must
-- remain untouched), deliberately render here instead. When voxel is unavailable,
-- the already-drawn Gold scene is preserved.
local GoldComposeBridge, goldComposeBridgeErr
do
  local source, readErr = mod:read("lib/GoldComposeBridge.lua")
  if source then
    local loadcode = loadstring or load
    local chunk, compileErr = loadcode(source,
      "@" .. mod.path .. "/lib/GoldComposeBridge.lua")
    if chunk then
      local okLoad, bridgeOrErr = pcall(chunk, mod, GoldVoxelBridge, GoldWildsBridge, GoldPipelineBridge)
      if okLoad and type(bridgeOrErr) == "table" then
        GoldComposeBridge = bridgeOrErr
        local okInstall, installErr = GoldComposeBridge.install()
        if not okInstall then
          goldComposeBridgeErr = tostring(installErr)
          GoldComposeBridge = nil
        end
      else
        goldComposeBridgeErr = tostring(bridgeOrErr)
      end
    else
      goldComposeBridgeErr = tostring(compileErr)
    end
  else
    goldComposeBridgeErr = tostring(readErr)
  end
end
if GoldComposeBridge then
  mod.log:info("Gold render.compose integration enabled")
else
  mod.log:error("Gold render.compose integration failed: %s",
                tostring(goldComposeBridgeErr))
end

-- `game.ready` happens before a new Gold World necessarily exists, while
-- `map.entered` happens after the live map/people are built.  The embedded
-- Wilds event listener normally initializes there, but this idempotent repair
-- makes a current map visible even if event ordering differs across builds or
-- after a save reload.
local function ensureWildsCurrentMap(ev)
  if not (wildsExports and type(wildsExports.logic) == "table") then return end
  local worldApi = mod.world
  local ow = worldApi and worldApi.overworld and worldApi:overworld()
  local map = ow and ow.map
  local mapId = (ev and ev.mapId) or (map and map.id)
  if not mapId then return end

  local logic = wildsExports.logic
  local initialized = logic.state and logic.state.initialized == true
  if logic.activeMapId == mapId and initialized then return end
  if type(logic.onMapEntered) ~= "function" then return end

  local ok, err = pcall(logic.onMapEntered, logic, {
    mapId = mapId, map = map, via = "stadium2_gen2_bootstrap",
  })
  if not ok then
    mod.log:warn("Gold visible-Wilds map bootstrap failed: %s", tostring(err))
  end
end

mod.events:on("map.entered", ensureWildsCurrentMap)
mod.events:on("save.loaded", ensureWildsCurrentMap)
mod.events:on("game.ready", ensureWildsCurrentMap)
pcall(ensureWildsCurrentMap)

-- Gold/Silver can change land encounter slots with time of day. Rebuild the
-- embedded Wilds population when the engine announces a TOD transition so the
-- visible roster stays in lockstep with vanilla encounters.
if wildsExports and type(wildsExports.logic) == "table" then
  mod.events:on("world.tod_changed", function(ev)
    local logic = wildsExports.logic
    local world = mod.world
    local ow = world and world.overworld and world:overworld()
    local mapId = (ev and ev.mapId) or (ow and ow.map and ow.map.id)
    if mapId and logic.activeMapId == mapId
       and type(logic.onMapReloaded) == "function" then
      local okReload, reloadErr = pcall(logic.onMapReloaded, logic, { mapId = mapId })
      if not okReload then
        mod.log:warn("Wilds time-of-day refresh failed: %s", tostring(reloadErr))
      end
    end
  end)
end

-- Companion mods can tag a Pokemon entity explicitly through this mod.
mod.exports.version = "0.2.81"
mod.exports.pauseMenuBattleStyle = PauseMenuBattleStyle
mod.exports.goldSubmenuBattleStyle = GoldSubmenuBattleStyle
mod.exports.textBoxBattleStyle = TextBoxBattleStyle
mod.exports.textBoxBattleStyleStatus = function()
  return TextBoxBattleStyle and TextBoxBattleStyle.status and TextBoxBattleStyle.status() or {
    installed = false, error = textBoxStyleErr,
  }
end
mod.exports.openWorldZoom = OpenWorldZoom
mod.exports.openWorldZoomStatus = function()
  return OpenWorldZoom and OpenWorldZoom.status and OpenWorldZoom.status() or {
    installed = false, error = openWorldZoomErr,
  }
end
mod.exports.overworld = Stadium
mod.exports.modelsEnabled = BaseV.modelsEnabled
mod.exports.red3dPlayerCompat = true
mod.exports.red3dPlayerCompatStatus = function()
  local selector = mod.find and mod.find("red_3d_player") or nil
  local okPlayer, Player = pcall(require, "src.world.gen2.Player")
  local renderer = okPlayer and type(Player) == "table" and Player.red3dPlayerRenderer or nil
  local camera = GoldVoxelBridge and GoldVoxelBridge.status and GoldVoxelBridge.status() or nil
  return {
    selectorDetected = selector ~= nil,
    rendererReady = type(renderer) == "table" and type(renderer.drawVoxel) == "function",
    activeId = type(renderer) == "table" and renderer.activeId or nil,
    cameraProvider = camera and camera.cameraProvider or nil,
    externalCameraLabel = camera and camera.externalCameraLabel or nil,
    externalCameraLevel = camera and camera.externalCameraLevel or nil,
  }
end
mod.exports.romMenu = StadiumRomMenu
mod.exports.modOptionsBattleStyle = ModMenuBattleStyle
mod.exports.modMenuBattleStyle = ModMenuBattleStyle
mod.exports.directModSettingsMenu = DirectModSettingsMenu
mod.exports.modSettingsPersistence = ModSettingsPersistence
mod.exports.categorizedModSettings = CategorizedModSettings
mod.exports.androidFullFrameFlip = AndroidFullFrameFlip
-- Tells a host that this mod normalises clip space for LOVE 12 itself
-- (see lib/ClipSpace.lua), so a host-side compatibility flip for the old
-- upside-down behaviour must NOT also be applied -- the two would cancel
-- and put the world back where it started.
mod.exports.loveClipSpaceHandled = true
mod.exports.categorizedModSettingsStatus = function()
  return CategorizedModSettings and CategorizedModSettings.status and CategorizedModSettings.status() or nil
end
mod.exports.androidFullFrameFlipStatus = function()
  return AndroidFullFrameFlip and AndroidFullFrameFlip.status and AndroidFullFrameFlip.status() or nil
end
mod.exports.chooseStadiumRom = function(game)
  if game then return StadiumRomMenu.choose(game) end
  local okGame2, Game2 = pcall(require, "src.core.Game2")
  return StadiumRomMenu.choose(okGame2 and Game2 or nil)
end
mod.exports.tag = function(entity, speciesOrDex)
  return Stadium.tag(entity, speciesOrDex)
end
mod.exports.untag = function(entity)
  return Stadium.untag(entity)
end

mod.exports.active = true
mod.exports.hostDetected = true
mod.exports.hostId = dramaticShapeId
mod.exports.generation = gameGeneration()
mod.exports.gen2Compatible = true
mod.exports.targetGeneration = 2
mod.exports.stadium2Importer = true
mod.exports.standaloneRenderer = true
mod.exports.maxDex = 251
mod.exports.rendererInstalled = rendererInstalled
mod.exports.rendererError = rendererErr
mod.exports.voxelHostId = dramaticShapeId
mod.exports.voxelHostGeneration = 2
mod.exports.voxelPipelineState = voxelPipelineState
mod.exports.voxelDirectWorldHook = goldPipelineInstalled == true
mod.exports.voxelComposeHook = GoldComposeBridge ~= nil
-- Legacy default target remains FULL/diorama level 1. v0.1.89 can select the
-- live first/third-person levels through GoldVoxelBridge without changing this
-- compatibility value expected by older diagnostics.
mod.exports.voxelTargetLevel = 1
mod.exports.voxelStatus = function()
  return GoldVoxelBridge and GoldVoxelBridge.status and GoldVoxelBridge.status() or nil
end
mod.exports.voxelCameraMode = function()
  local status = GoldVoxelBridge and GoldVoxelBridge.status and GoldVoxelBridge.status() or nil
  return status and status.cameraMode or "diorama"
end
mod.exports.voxelCameraLevel = function()
  local status = GoldVoxelBridge and GoldVoxelBridge.status and GoldVoxelBridge.status() or nil
  return status and status.cameraLevel or 1
end
mod.exports.cycleVoxelCamera = function()
  if GoldVoxelBridge and type(GoldVoxelBridge.cycleCameraMode) == "function" then
    return GoldVoxelBridge.cycleCameraMode(true)
  end
  return nil
end
mod.exports.partyFollower = GoldPartyFollower
mod.exports.partyFollowerStatus = function()
  return GoldPartyFollower and GoldPartyFollower.status and GoldPartyFollower.status() or {
    installed = false,
    error = goldPartyFollowerErr,
  }
end
mod.exports.inWorld3DBattles = true
mod.exports.inWorld3DBattleStatus = function()
  local voxel = GoldVoxelBridge and GoldVoxelBridge.status and GoldVoxelBridge.status() or nil
  local compose = GoldComposeBridge and GoldComposeBridge.status and GoldComposeBridge.status() or nil
  return {
    installed = voxel and voxel.battleInstalled or false,
    active = voxel and voxel.battleActive or false,
    error = (voxel and voxel.battleError) or (compose and compose.lastBattleError) or nil,
    frames = compose and compose.battleFrames or 0,
    fallbacks = compose and compose.battleFallbackFrames or 0,
  }
end
mod.exports.battlePokemonControl = BattlePokemonControl
mod.exports.battlePokemonControlStatus = function()
  return BattlePokemonControl and BattlePokemonControl.status and BattlePokemonControl.status() or nil
end
mod.exports.battleControllerUI = BattleControllerUI
mod.exports.battleControllerUIStatus = function()
  return BattleControllerUI and BattleControllerUI.status and BattleControllerUI.status() or nil
end
mod.exports.battleAnimationsInstalled = battleAnimationsInstalled
mod.exports.battleAnimationsError = battleAnimationsErr
mod.exports.battleEffectsInstalled = battleEffectsInstalled
mod.exports.battleEffectsError = battleEffectsErr

mod.exports.battle3DInstalled = battle3DInstalled
mod.exports.battle3DError = battle3DErr
mod.exports.lib = BaseV
mod.exports.wilds = wildsExports
mod.exports.overworldCaptureInstalled = overworldCaptureInstalled
mod.exports.overworldCaptureError = overworldCaptureErr
mod.exports.overworldCaptureStatus = function()
  return OverworldCapture and OverworldCapture.status and OverworldCapture.status() or {
    installed = false, error = overworldCaptureErr,
  }
end
mod.exports.wildSpawnsInstalled = wildsExports ~= nil
mod.exports.wildSpawnsSource = wildsSource
mod.exports.wildSpawnsError = wildsErr
mod.exports.goldWildsDrawBridgeInstalled = GoldWildsBridge ~= nil
mod.exports.goldWildsDrawBridgeError = goldWildsBridgeErr
mod.exports.goldWildsDrawBridgeStatus = function()
  return GoldWildsBridge and GoldWildsBridge.status and GoldWildsBridge.status() or nil
end
mod.exports.goldPipelineBridge = GoldPipelineBridge
mod.exports.goldPipelineBridgeInstalled = goldPipelineInstalled == true
mod.exports.goldPipelineBridgeError = goldPipelineErr
mod.exports.goldPipelineBridgeStatus = function()
  return GoldPipelineBridge and GoldPipelineBridge.status and GoldPipelineBridge.status() or nil
end
mod.exports.goldComposeBridgeInstalled = GoldComposeBridge ~= nil
mod.exports.goldComposeBridgeError = goldComposeBridgeErr
mod.exports.goldComposeBridgeStatus = function()
  return GoldComposeBridge and GoldComposeBridge.status and GoldComposeBridge.status() or nil
end
mod.exports.visibleWildsForced = true
mod.exports.entryCompleted = true
