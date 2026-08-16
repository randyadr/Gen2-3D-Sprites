-- STADIUM battles: importing the ROM, instead of being told where to put it.
--
-- The mod ships no Pokemon Stadium models and cannot -- they are that game's
-- data -- so the player supplies the cartridge. The original instruction for
-- that was "make a folder called baseroms next to the game and drop the file
-- in it", which is a fine sentence to write and a poor thing to ask. It needs
-- a folder the player has to create, in a place that is different on every
-- platform and is inside an unwritable archive on a packaged build, and it
-- fails SILENTLY: the two STADIUM rungs are simply not on the row, and
-- nothing on screen says why.
--
-- So this opens a file picker instead, from a row on the OPTIONS menu, and
-- the folder keeps working for anyone who prefers it (StadiumInstall).
--
-- ------- the picker is the host's, not LOVE's
--
-- LOVE 11.5 has no file dialog. love.window.showFileDialog arrived in 12 and
-- love.system.pickFile is a native bridge this project ships for mobile
-- rather than part of LOVE at all. What every desktop OS does have is a
-- dialog reachable from a shell, so that is what is used here -- osascript on
-- macOS, PowerShell's OpenFileDialog on Windows, zenity then kdialog on
-- Linux.
--
-- This is deliberately the SAME four commands the engine's own ROM importer
-- uses for the Game Boy cartridge (src/import/RomImporter.lua's chooseRom),
-- down to writing the Windows pick as UTF-8 -- the console's OEM codepage
-- mangles a non-ASCII path into something that crashes the next text draw.
-- Being a second copy of that is worth it: a mod cannot call into the
-- importer's private helpers, and the alternative is asking the engine to
-- grow a seam for one caller.
--
-- The dialog BLOCKS. io.popen waits for the player to choose, and the game is
-- frozen for as long as it is up. That is what the engine's importer does
-- too, it is what a modal dialog means, and the frame it freezes on is an
-- options menu.
--
-- ------- and the ROM is not kept
--
-- The picked file is read, built from, and forgotten -- nothing is copied
-- anywhere. A Stadium cartridge is 32 MB and the models built out of it are
-- 34, so keeping both would double the cost of a feature for a file that has
-- no further use: the packs are what the game reads afterwards, and the
-- marker records the ROM's md5 so a swapped cartridge is still noticed.
--
-- The one thing that costs is a format bump, which invalidates the packs and
-- leaves nothing to rebuild from. That is what the row still being there is
-- for -- it reads READY, and pressing it imports again.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local StadiumInstall = V.require("StadiumInstall")
local Compat = V.require("EngineCompat")

local StadiumRomPick = {}

local function isGen2()
  return type(StadiumInstall.gameGeneration) == "function"
     and StadiumInstall.gameGeneration() == 2
end

StadiumRomPick.ID = ((V.mod and V.mod.id) or "STADIUM2_OVERWORLD_MODELS") .. ":stadiumRom"

local function label()
  return isGen2() and "STADIUM 2 ROM" or "STADIUM ROM"
end

local function prompt()
  if isGen2() then
    return "Choose your Pokemon Stadium 2 ROM (Gold/Silver models)"
  end
  return "Choose your Pokemon Stadium (US) 1.0 ROM"
end

-- Keep LABEL readable for older callers while the row/value functions below
-- refresh it from the active game generation.
StadiumRomPick.LABEL = label()

-- ------- the host, at arm's length
--
-- Everything below goes through EngineCompat. Current Gen1Recomp deliberately
-- sandboxes raw io and love.system/love.filesystem away from mod chunks, while
-- engine-owned Platform / SaveData / HostShell still provide the same services
-- safely. Older builds fall back through the same guarded compatibility layer.

local function haveShell()
  local shell = Compat.hostShell()
  return shell and type(shell.popen) == "function"
end

local function haveFiles()
  local f = Compat.fs()
  return f and type(f.read) == "function" and type(f.getInfo) == "function"
end

local function osName()
  return Compat.osName()
end

-- Run a command and return its trimmed stdout, or nil for anything that did
-- not produce a line -- a cancelled dialog, a missing zenity, a shell that
-- is not there.
local function commandOutput(cmd)
  if not haveShell() then return nil end
  return Compat.pipeOutput(Compat.hostShell(), cmd)
end

-- ------- can this machine open a DIALOG
--
-- Desktop only, and honestly so.
--
-- On ANDROID the picker is a native bridge (love.system.pickFile) whose
-- kind -> filename mapping is a fixed list of three in the engine's own C++,
-- and an unrecognised kind falls through to `picked_rom.gb`. That is not
-- merely the wrong name -- it is the file the engine's Game Boy importer is
-- watching, and reading that code settles it: the importer's size test only
-- SKIPS a 1 MB file it has already imported, so a 32 MB N64 ROM landing
-- there falls straight through to `love.filesystem.remove` and
-- `startData` -- deleted, and then reported to the player as a broken Game
-- Boy ROM. So the bridge is not called until it learns the kind, which is a
-- two-line change in System.cpp and an APK rebuild (see README).
--
-- Android is not stuck without it: conf.lua points the save directory at the
-- app's external-files folder, so `baseroms/` there is reachable over USB or
-- any file manager with no root and no permission prompt. What Android
-- lacked was being TOLD that -- the row vanished, and the folder's absolute
-- path was only ever written to a console no phone shows. That is what the
-- note below is for.
function StadiumRomPick.canDialog()
  if not (haveShell() and haveFiles()) then return false end
  local p = osName()
  return p == "Windows" or p == "OS X" or p == "Linux"
end

-- Kept as the old name for callers that only wanted "is there a dialog".
StadiumRomPick.available = StadiumRomPick.canDialog

-- Where a SAF pick would land if the native bridge grows a Stadium kind.
-- Watched unconditionally (see poll): on a build that never writes it this
-- costs one getInfo a frame, and on one that does the mod needs no further
-- change to use it.
StadiumRomPick.PICKED = "picked_stadium.z64"

-- Open the dialog. Returns the chosen absolute path, or nil when the player
-- cancelled or no dialog could be opened.
function StadiumRomPick.choose()
  local p = osName()
  if p == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type ]]
       .. [[{"z64", "n64", "v64"})' 2>/dev/null]]):format(prompt()))
  elseif p == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt() .. "';",
      "$d.Filter='Nintendo 64 ROM (*.z64;*.n64;*.v64)|*.z64;*.n64;*.v64"
      .. "|All files (*.*)|*.*';",
      -- as UTF-8: the console's OEM codepage would mangle a non-ASCII path
      -- and crash the next text draw that showed it
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding="
      .. "[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif p == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" ]]
       .. [[--file-filter="Nintendo 64 ROM | *.z64 *.n64 *.v64" 2>/dev/null]])
        :format(prompt()))
    if path then return path end
    -- zenity is absent on plenty of installs (and on most handheld Linux
    -- distributions); KDE's own dialog is the usual second answer
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.z64 *.n64 *.v64|]]
      .. [[Nintendo 64 ROM" 2>/dev/null]])
  end
  return nil
end

-- Read an ABSOLUTE path, which love.filesystem cannot: it only sees inside
-- the physfs mount, and a picked file is anywhere on the disk. Returns the
-- bytes, or nil plus a reason short enough to fit the loading screen.
function StadiumRomPick.read(path)
  if not haveFiles() then return nil, "no file access" end
  local okStage, relOrErr = Compat.stageExternal(path, StadiumRomPick.PICKED)
  if not okStage then return nil, relOrErr or "could not open that file" end
  local f = Compat.fs()
  local okRead, bytes = pcall(f.read, StadiumRomPick.PICKED)
  if type(f.remove) == "function" then pcall(f.remove, StadiumRomPick.PICKED) end
  if not (okRead and type(bytes) == "string" and #bytes > 0) then
    return nil, "could not read that file"
  end
  return bytes
end

-- ------- the whole flow, from one keypress
--
-- Pick, read, start the build, and put the loading screen up over whatever
-- asked -- which is the OPTIONS menu, so the row is there again underneath
-- when the build finishes and now reads READY.
--
-- A CANCELLED dialog is not a failure and says nothing: the player opened a
-- file browser and changed their mind, and a mod that made an announcement
-- about that would be the second most annoying thing on the menu.
--
-- Everything else lands on the loading screen's own failure state, because it
-- is the one surface in this mode with room for a sentence -- and because a
-- player who has just chosen the wrong file is owed a reason and not a row
-- that quietly goes on saying IMPORT.

-- Say where the file goes, on screen. Shared by the no-dialog platforms and
-- by a dialog platform whose engine build cannot stage the pick (see below):
-- both cases end at the same answer, dropping the ROM in baseroms/, and
-- StadiumInstall.begin() already reads that folder directly with no staging
-- step at all.
--
-- `reason` is StadiumInstall.begin()'s own error when THAT was already tried
-- and still had nothing to build from -- shown ahead of the path instead of a
-- bare repeat of instructions the player may have already followed.
local function showFolderNote(game, reason)
  local StadiumScreen = V.require("StadiumScreen")
  if game and game.stack then
    local body = StadiumInstall.romHintFile()
    if reason then body = tostring(reason) .. " -- expected at: " .. body end
    game.stack:push(StadiumScreen.newNote(game, label(),
      isGen2() and "PUT POKEMON STADIUM 2 HERE:" or "PUT STADIUM US 1.0 HERE:",
      body))
  end
end

function StadiumRomPick.import(game)
  if StadiumInstall.status.state == "building" then return false end
  local StadiumScreen = V.require("StadiumScreen")

  -- No dialog on this platform: say where the file goes, on screen, because
  -- that is the whole of what the player is missing and the console is not
  -- somewhere they can read it.
  if not StadiumRomPick.canDialog() then
    showFolderNote(game)
    return false
  end

  local path = StadiumRomPick.choose()
  if not path then return false end
  local function fail(why)
    StadiumInstall.status.state = "failed"
    StadiumInstall.status.error = why
    if game and game.stack then
      game.stack:push(StadiumScreen.new(game, true))
    end
    return false
  end

  local bytes, err = StadiumRomPick.read(path)
  if not bytes then
    -- "save directory unavailable" means EngineCompat.stageExternal could not
    -- get an absolute path to copy the pick INTO -- current engine builds can
    -- route mod persistence through a sandboxed backend that never exposes
    -- one (see EngineCompat.fs). That is not the chosen file's fault and a
    -- different file will not fix it, so try the one staging path that never
    -- needed an absolute directory at all: baseroms/, read directly by
    -- StadiumInstall.begin(). If a ROM is already sitting there -- likely,
    -- since that is exactly the folder this screen would otherwise just
    -- recite instructions for -- this finishes right here with no second
    -- manual step and no dead-end "COULD NOT BUILD".
    if err == "save directory unavailable" then
      local beginOk, beginErr = StadiumInstall.begin()
      if beginOk then
        if game and game.stack then
          game.stack:push(StadiumScreen.new(game, true))
        end
        return true
      end
      showFolderNote(game, beginErr)
      return false
    end
    return fail(err or "could not read that file")
  end

  local ok, beginErr = StadiumInstall.beginFrom(bytes, path)
  if not ok then return fail(tostring(beginErr)) end
  if game and game.stack then
    game.stack:push(StadiumScreen.new(game, true))
  end
  return true
end

-- ------- the row
--
-- An ACTION rather than a value, which is why it is not a ModSetting: there
-- is no rung to store, nothing for the mod manager's page to persist, and
-- nothing to restore on the next boot. What it shows is a STATE -- the models
-- are there or they are not -- and what it does is the only thing it can do.
--
-- Still offered once they ARE there, reading READY. Pressing it imports
-- again, which is how a player swaps to a different revision, and how they
-- rebuild after a format bump has invalidated the packs and left nothing on
-- disk to rebuild from (see the header: the ROM is not kept).
--
-- nil where no dialog can be opened, which takes the row off the menu
-- entirely rather than offering a button that cannot do anything.
function StadiumRomPick.row()
  StadiumRomPick.LABEL = label()
  return {
    id = StadiumRomPick.ID,
    label = StadiumRomPick.LABEL,
    value = function()
      if StadiumInstall.status.state == "building" then return "BUILDING" end
      if StadiumInstall.available() then return "READY" end
      -- WHERE, not IMPORT, where pressing it can only tell you the folder:
      -- a row that says IMPORT and then does not import is a worse row than
      -- one that says what it actually does
      return StadiumRomPick.canDialog() and "IMPORT" or "WHERE?"
    end,
    step = function(game)
      pcall(StadiumRomPick.import, game)
      return true
    end,
  }
end

-- ------- a pick that landed while we were not looking
--
-- The desktop dialog BLOCKS, so `import` above can read the answer on the
-- next line. A SAF pick cannot work that way: it is a separate activity,
-- Android is free to destroy the game while it is up, and the file appears
-- some frames later -- so the only way to notice one is to look for it.
--
-- Nothing writes this filename today (see canDialog). It is watched anyway so
-- that teaching the native bridge one more kind is the whole of the Android
-- picker work, with no second change needed here.
--
-- Consumed and DELETED either way: a 32 MB file left in the save directory
-- would be imported again on the next boot, and kept forever if the import
-- failed.
function StadiumRomPick.poll(game)
  local f = Compat.fs()
  if not (f and type(f.getInfo) == "function") then return false end
  if StadiumInstall.status.state == "building" then return false end
  local ok, info = pcall(f.getInfo, StadiumRomPick.PICKED, "file")
  if not (ok and info) then return false end

  local okRead, bytes = pcall(f.read, StadiumRomPick.PICKED)
  if type(f.remove) == "function" then pcall(f.remove, StadiumRomPick.PICKED) end
  if not (okRead and type(bytes) == "string") then return false end

  local okScreen, StadiumScreen = pcall(V.require, "StadiumScreen")
  local okBegin, started, err = pcall(StadiumInstall.beginFrom, bytes, StadiumRomPick.PICKED)
  if not okBegin then
    StadiumInstall.status.state = "failed"
    StadiumInstall.status.error = tostring(started)
  elseif not started then
    StadiumInstall.status.state = "failed"
    StadiumInstall.status.error = tostring(err)
  end
  if okScreen and StadiumScreen and game and game.stack
      and type(StadiumScreen.new) == "function" then
    pcall(function() game.stack:push(StadiumScreen.new(game, true)) end)
  end
  return true
end

return StadiumRomPick
