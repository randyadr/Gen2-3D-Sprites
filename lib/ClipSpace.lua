-- Which way clip-space Y points for a pass that builds its OWN projection.
--
-- Every 3D pass here bypasses LOVE's transform_projection and hands the shader
-- a matrix it built itself, so it -- not LOVE -- owns the convention. Those
-- matrices are all built Y-DOWN: Mat4.scale(1, -1, 1) is folded into them
-- (Voxel3D.viewProjection, ShadowMap.update) so that clip Y = -1 is the TOP of
-- the target. That is what lets every CONSUMER read a canvas position straight
-- off the same matrix with `(y / w * 0.5 + 0.5)`, and they all do: the horizon,
-- the sun and moon disc, the battle pins, ShadowMap.uvVP, and Water's
-- screen-space march. All of them stay right for as long as the rendered image
-- agrees with them.
--
-- LOVE 11 stores a canvas exactly that way, so the matrix can go to the GPU
-- untouched. LOVE 12 does not. It normalises clip space itself:
-- love_clipSpaceTransform runs on whatever position() returns, and each backend
-- flips or does not flip so that clip Y = +1 is the top of every target on
-- every renderer -- OpenGL flips only while a render target is bound, Metal has
-- nothing to flip. The Y-down matrix is then one flip too many, and the whole
-- 3D pass composites vertically mirrored.
--
-- Only iOS runs LOVE 12 today: gen1recomp's conf.lua asks for "12.0" there and
-- "11.5" everywhere else. And only Gen 2 shows the mirror, which is why this
-- went unnoticed for so long -- Gen 1 hands its finished world to
-- Renderer:setWorldOverride, whose blit already compensates on iOS/LOVE 12,
-- while Gold's pipeline seam (src/world/gen2/World.lua) blits it straight.
--
-- So: leave the matrices Y-down, which keeps every consumer above and the whole
-- of LOVE 11 byte-identical, and undo the flip once on the way to the GPU.
-- CLIP_Y is what the three shaders that transform geometry with one of these
-- matrices multiply their clip Y by. It is 1.0 on LOVE 11, a no-op the shader
-- compiler folds away.

local ClipSpace = {}

-- love.getVersion is not on the mod sandbox's blocked list (love.system is),
-- but read it defensively all the same: a host that refuses it should get the
-- long-standing LOVE 11 behaviour rather than an upside-down world.
local major = 11
do
  local ok, value = pcall(function() return (love.getVersion()) end)
  if ok then major = tonumber(value) or 11 end
end

ClipSpace.loveMajor = major

-- 1 leaves a Y-down matrix alone; -1 undoes its flip for a LOVE that already
-- normalises clip space on our behalf.
ClipSpace.sign = major >= 12 and -1 or 1

-- Prepended to each shader source that transforms geometry with one of the
-- Y-down matrices, beside the mod's other compile-time defines.
ClipSpace.define = ("#define CLIP_Y %.1f\n"):format(ClipSpace.sign)

return ClipSpace
