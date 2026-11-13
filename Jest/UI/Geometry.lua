-- Wheel geometry with no WoW API calls, so it can be tested outside the game.
--
-- SliceAt must match the copy in Secure/Snippets.lua: the snippet decides what fires, this one
-- drives the highlight. With /jest debug on, every fire reports whether the two agreed.
local _, ns = ...

local Geometry = {}
if ns then ns.Geometry = Geometry end

local atan2, deg, rad, floor, sin, cos = math.atan2, math.deg, math.rad, math.floor, math.sin, math.cos

-- dx, dy: cursor offset from the wheel centre (y up). Returns slice index 1..n, or nil in the dead zone.
-- Slice 1 is centred at 12 o'clock; indices increase clockwise.
function Geometry.SliceAt(dx, dy, n, deadZone)
	if n < 1 or dx * dx + dy * dy < deadZone * deadZone then return nil end
	local a = (90 - deg(atan2(dy, dx))) % 360
	local step = 360 / n
	return floor((a + step / 2) / step) % n + 1
end

-- Angle of slice i's centre in degrees, clockwise from 12 o'clock.
function Geometry.SliceAngle(i, n)
	return (i - 1) * 360 / n
end

-- Centre of slice i as an (x, y) offset from the wheel centre.
function Geometry.SlicePosition(i, n, radius)
	local a = rad(Geometry.SliceAngle(i, n))
	return radius * sin(a), radius * cos(a)
end

-- Signed shortest turn (degrees, -180..180) from angle `from` to angle `to`.
function Geometry.AngleDelta(from, to)
	return (to - from + 540) % 360 - 180
end

return Geometry
