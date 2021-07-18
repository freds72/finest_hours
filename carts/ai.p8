pico-8 cartridge // http://www.pico-8.com
version 32
__lua__

-- sketch/prototype cart for an AI routine

#include math.lua

function getai()
 return {
  p={rnd(128),rnd(128),0},
	d={1,0,0},
	a={64,64,0},
 }
end

local ais={
 getai(),
 getai(),
 getai(),
}

function drawai(ai)
 line(ai.p[1],ai.p[2],ai.p[1]+ai.d[1]*16,ai.p[2]+ai.d[2]*16,9)
 pset(ai.p[1],ai.p[2],7)
 circ(ai.a[1],ai.a[2],1,2)
end

function moveai(ai)
 ai.d=v_normz(v_add(ai.d,v_normz(make_v(ai.p, ai.a)),0.1))
 ai.p=v_add(ai.p,ai.d)
end

function _update()
 for ai in all(ais) do
  ai.a={cos(t()/10)*48+64,sin(t()/9)*48+64,0}
  moveai(ai)
 end
end

function _draw()
 cls()
 for ai in all(ais) do
  drawai(ai)
 end
end
