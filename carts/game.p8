pico-8 cartridge // http://www.pico-8.com
version 32
__lua__

#include plain.lua
#include poly.lua

-- globals
local _models,_sun_dir,_cam={},{0,-0.707,0.707}

local k_far,k_near=0,2
local k_right,k_left=4,8
local z_near=1


-- maths & cam
function lerp(a,b,t)
	return a*(1-t)+b*t
end

function make_v(a,b)
	return {
		b[1]-a[1],
		b[2]-a[2],
		b[3]-a[3]}
end
function v_clone(v)
	return {v[1],v[2],v[3]}
end
function v_dot(a,b)
	return a[1]*b[1]+a[2]*b[2]+a[3]*b[3]
end
function v_scale(v,scale)
	v[1]*=scale
	v[2]*=scale
	v[3]*=scale
end
function v_add(v,dv,scale)
	scale=scale or 1
	return {
		v[1]+scale*dv[1],
		v[2]+scale*dv[2],
		v[3]+scale*dv[3]}
end
function v_lerp(a,b,t)
	return {
		lerp(a[1],b[1],t),
		lerp(a[2],b[2],t),
		lerp(a[3],b[3],t)
	}
end
function v2_lerp(a,b,t)
	return {
		lerp(a[1],b[1],t),
		lerp(a[2],b[2],t)
	}
end

function v_cross(a,b)
	local ax,ay,az=a[1],a[2],a[3]
	local bx,by,bz=b[1],b[2],b[3]
	return {ay*bz-az*by,az*bx-ax*bz,ax*by-ay*bx}
end
-- safe for overflow (to some extent)
function v_len(v)
	local x,y,z=v[1],v[2],v[3]
  -- pick major
  local d=max(max(abs(x),abs(y)),abs(z))
  -- adjust
  x/=d
  y/=d
  z/=d
  -- actuel len
  return sqrt(x*x+y*y+z*z)*d
end

function v_normz(v)
	local x,y,z=v[1],v[2],v[3]
  local d=v_len(v)
	return {x/d,y/d,z/d},d
end

-- matrix functions
function make_m_from_euler(x,y,z)
		local a,b = cos(x),-sin(x)
		local c,d = cos(y),-sin(y)
		local e,f = cos(z),-sin(z)
  
    -- yxz order
  local ce,cf,de,df=c*e,c*f,d*e,d*f
	 return {
	  ce+df*b,a*f,cf*b-de,0,
	  de*b-cf,a*e,df+ce*b,0,
	  a*d,-b,a*c,0,
	  0,0,0,1}
end

function m_set_pos(m,v)
	m[13]=v[1]
	m[14]=v[2]
	m[15]=v[3]
end

function m_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	return {m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]}
end

-- inline matrix vector multiply invert
-- inc. position
function m_inv_x_v(m,v)
	local x,y,z=v[1]-m[13],v[2]-m[14],v[3]-m[15]
	return {m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z}
end
-- inline matrix vector multiply invert
-- excl. position
function m_inv_x_n(m,v)
	local x,y,z=v[1],v[2],v[3]
	return {m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z}
end

-- returns basis vectors from matrix
function m_right(m)
	return {m[1],m[2],m[3]}
end
function m_up(m)
	return {m[5],m[6],m[7]}
end
function m_fwd(m)
	return {m[9],m[10],m[11]}
end
-- optimized 4x4 matrix mulitply
function m_x_m(a,b)
	local a11,a12,a13,a21,a22,a23,a31,a32,a33=a[1],a[5],a[9],a[2],a[6],a[10],a[3],a[7],a[11]
	local b11,b12,b13,b14,b21,b22,b23,b24,b31,b32,b33,b34=b[1],b[5],b[9],b[13],b[2],b[6],b[10],b[14],b[3],b[7],b[11],b[15]

	return {
			a11*b11+a12*b21+a13*b31,a21*b11+a22*b21+a23*b31,a31*b11+a32*b21+a33*b31,0,
			a11*b12+a12*b22+a13*b32,a21*b12+a22*b22+a23*b32,a31*b12+a32*b22+a33*b32,0,
			a11*b13+a12*b23+a13*b33,a21*b13+a22*b23+a23*b33,a31*b13+a32*b23+a33*b33,0,
			a11*b14+a12*b24+a13*b34+a[13],a21*b14+a22*b24+a23*b34+a[14],a31*b14+a32*b24+a33*b34+a[15],1
		}
end

function make_m_from_v_angle(up,angle)
	local fwd={-sin(angle),0,cos(angle)}
	local right=v_normz(v_cross(up,fwd))
	fwd=v_cross(right,up)
	return {
		right[1],right[2],right[3],0,
		up[1],up[2],up[3],0,
		fwd[1],fwd[2],fwd[3],0,
		0,0,0,1
	}
end

function make_m_look_at(up,fwd)
	local right=v_normz(v_cross(up,fwd))
	fwd=v_cross(right,up)
	return {
		right[1],right[2],right[3],0,
		up[1],up[2],up[3],0,
		fwd[1],fwd[2],fwd[3],0,
		0,0,0,1
	}
end

-- sort
-- https://github.com/morgan3d/misc/tree/master/p8sort
-- 
function sort(data)
	local n = #data 
	if(n<2) return
	
	-- form a max heap
	for i = n\2+1, 1, -1 do
	 -- m is the index of the max child
	 local parent, value, m = i, data[i], i + i
	 local key = value.key 
	 
	 while m <= n do
	  -- find the max child
	  if ((m < n) and (data[m + 1].key > data[m].key)) m += 1
	  local mval = data[m]
	  if (key > mval.key) break
	  data[parent] = mval
	  parent = m
	  m += m
	 end
	 data[parent] = value
	end 
   
	-- read out the values,
	-- restoring the heap property
	-- after each step
	for i = n, 2, -1 do
	 -- swap root with last
	 local value = data[i]
	 data[i], data[1] = data[1], value
   
	 -- restore the heap
	 local parent, terminate, m = 1, i - 1, 2
	 local key = value.key 
	 
	 while m <= terminate do
	  local mval = data[m]
	  local mkey = mval.key
	  if (m < terminate) and (data[m + 1].key > mkey) then
	   m += 1
	   mval = data[m]
	   mkey = mval.key
	  end
	  if (key > mkey) break
	  data[parent] = mval
	  parent = m
	  m += m
	 end  
	 
	 data[parent] = value
	end
end


-->8
-- tracking camera
function make_cam(name)
	local up,target_pos={0,1,0},{0,0,0}
    return {
	    pos=pos,    
		track=function(self,pos,m)
			local target_u=m_up(m)
			-- orientation tracking
			up=v_normz(v_lerp(up,target_u,0.1))
			
			-- pos tracking (without view offset)
			target_pos=v_lerp(target_pos,v_add(pos,m_fwd(m),50),0.2)

			-- behind player
			m=make_m_look_at(up,make_v(target_pos,pos))

			-- shift cam position			
			pos=v_add(target_pos,up,20)

            -- clone matrix
            local m={unpack(m)}		
            -- inverse view matrix
            m[2],m[5]=m[5],m[2]
            m[3],m[9]=m[9],m[3]
            m[7],m[10]=m[10],m[7]
            --
            self.m=m_x_m(m,{
            1,0,0,0,
            0,1,0,0,
            0,0,1,0,
            -pos[1],-pos[2],-pos[3],1
            })
            self.pos=pos
        end,
		project=function(self,v)
			-- world to view
			v=m_x_v(self.m,v)
			-- too close to cam plane?
			local z=v[3]
			if(z<z_near) return
			-- view to screen
 			return {x=64+((v[1]/z)<<6),y=64-((v[2]/z)<<6)}
		end		
    }
end

-- clipping
function z_poly_clip(znear,v)
	local res,v0={},v[#v]
	local d0=v0[3]-znear
	for i=1,#v do
		local v1=v[i]
		local d1=v1[3]-znear
		if d1>0 then
			if d0<=0 then
				local nv=v_lerp(v0,v1,d0/(d0-d1)) 
				nv.x=64+((nv[1]/nv[3])<<6)
				nv.y=64-((nv[2]/nv[3])<<6)
				res[#res+1]=nv
			end
			res[#res+1]=v1
		elseif d0>0 then
			local nv=v_lerp(v0,v1,d0/(d0-d1)) 
			nv.x=64+((nv[1]/nv[3])<<6)
			nv.y=64-((nv[2]/nv[3])<<6)
			res[#res+1]=nv
		end
		v0=v1
		d0=d1
	end
	return res
end

-- sutherland-hodgman clipping
function plane_poly_clip(n,p,v)
	local dist,allin={},true
	for i=1,#v do
		dist[i]=v_dot(make_v(v[i],p),n)
		allin = allin and dist[i]>0
	end
	-- early exit
	if(allin) return v
	
	local res={}
	local v0,d0=v[#v],dist[#v]
	for i=1,#v do
		local v1,d1=v[i],dist[i]
		if d1>0 then
			if d0<=0 then
				local nv=v_lerp(v0,v1,d0/(d0-d1)) 
				nv.x=64+((nv[1]/nv[3])<<6)
				nv.y=64-((nv[2]/nv[3])<<6)
				res[#res+1]=nv
			end
			res[#res+1]=v1
		elseif d0>0 then
			local nv=v_lerp(v0,v1,d0/(d0-d1)) 
			nv.x=64+((nv[1]/nv[3])<<6)
			nv.y=64-((nv[2]/nv[3])<<6)
			res[#res+1]=nv
		end
		v0,d0=v1,d1
	end
	return res
end

-- vertex cache class
-- uses m (matrix) and v (vertices) from self
-- saves the 'if not ...' in inner loop
local v_cache_cls={
	-- v is vertex reference
	__index=function(t,v)
		-- inline: local a=m_x_v(t.m,t.v[k]) 
		local m,x,y,z=t.m,v[1],v[2],v[3]
		local ax,ay,az=m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]
	
		local outcode=k_near
		if(az>z_near) outcode=k_far
		if(ax>az) outcode+=k_right
		if(-ax>az) outcode+=k_left

		-- not faster :/
		-- local bo=-(((az-z_near)>>31)<<17)-(((az-ax)>>31)<<18)-(((az+ax)>>31)<<19)
		-- assert(bo==outcode,"outcode:"..outcode.." bits:"..bo)

		-- assume vertex is visible, compute 2d coords
		local a={ax,ay,az,outcode=outcode,clipcode=outcode&2,x=64+((ax/az)<<6),y=64-((ay/az)<<6)} 
		t[v]=a
		return a
	end
}

function collect_faces(model,m,out)
	-- cam pos in object space
	local cam_pos=m_inv_x_v(m,_cam.pos)
	-- sun vector in model space	
	local sun=m_inv_x_n(m,_sun_dir)
	
	-- select lod
	local d=v_dot(cam_pos,cam_pos)
	
	-- lod selection
	local lodid=0
	for i=1,#model.lods do
		if(d>model.lods[i].dist) lodid+=1
	end
	-- cap to max lod if too far away
	model=model.lods[min(lodid,#model.lods-1)+1]

	-- object to world
	-- world to cam
	-- vertex cache (and model context)
	local v_cache=setmetatable({m=m_x_m(_cam.m,m)},v_cache_cls)

	for _,face in pairs(model.f) do
		if face.dual_sided or v_dot(face.n,cam_pos)>face.cp then
			-- project vertices
			local v4=face[4]
			local v0,v1,v2,v3=v_cache[face[1]],v_cache[face[2]],v_cache[face[3]],v4 and v_cache[v4]			
			-- mix of near/far verts?
			if v0.outcode&v1.outcode&v2.outcode&(v3 and v3.outcode or 0xffff)==0 then
				local verts={v0,v1,v2,v3}

				local ni,is_clipped,y,z=9,v0.clipcode+v1.clipcode+v2.clipcode,v0[2]+v1[2]+v2[2],v0[3]+v1[3]+v2[3]
				if v3 then
					is_clipped+=v3.clipcode
					y+=v3[2]
					z+=v3[3]
					-- number of faces^2
					ni=16
				end
				-- mix of near+far vertices?
				if(is_clipped>0) verts=z_poly_clip(z_near,verts)
				if #verts>2 then
					verts.f=face
					verts.light=mid(-v_dot(sun,face.n),-1,1)
					verts.cache=v_cache
					-- sort key
					-- todo: improve
					verts.key=-z/ni
					out[#out+1]=verts
				end
			end
		end
	end
end

-- draw face
function draw_face(v0,v1,v2,v3,col)
	if v0.outcode&v1.outcode&v2.outcode&(v3 and v3.outcode or 0xffff)==0 then
		local verts={v0,v1,v2,v3}
		if(v0.clipcode+v1.clipcode+v2.clipcode+(v3 and v3.clipcode or 0)>0) verts=z_poly_clip(z_near,verts)
		if(#verts>2) polyfill(verts,col)
	end
end

function draw_faces(faces)
	for i,d in ipairs(faces) do
		-- todo: get dark color from model / use diffuse anyway?
		local main_face,light,col=d.f,d.light,0x11
		if light>0 then
			-- pick base shaded color
			-- todo: get shininess from model
			col=main_face.ramp[(light<<2)\1]
		end

		polyfill(d,col)
		-- decals?
		-- todo: hide decals when face is unlit??
		if main_face.inner then
			-- reuse array
			for _,face in pairs(main_face.inner) do
				local v_cache,v4=d.cache,face[4]
				-- reuse light information
				if light>0 then
					col=face.ramp[(light<<2)\1]
				end
				draw_face(v_cache[face[1]],v_cache[face[2]],v_cache[face[3]],v4 and v_cache[v4],col)
			end
		end

		if(main_face.edges) polylines(d,0)
	end
end

local sky_gradient={0x77,0xc7,0xc6,0xcc}
local sky_fillp={0xffff,0xa5a5,0xa5a5,0xffff}
function draw_ground()
	cls(3)
	
	-- draw horizon
	local zfar=-256
	local farplane={
			{-zfar,zfar,zfar},
			{-zfar,-zfar,zfar},
			{zfar,-zfar,zfar},
			{zfar,zfar,zfar}}

	-- ground normal in cam space
	local n=m_up(_cam.m)

	for k=0,#sky_gradient-1 do
		-- ground location in cam space	
		local p=m_x_v(_cam.m,{0,_cam.pos[2]-10*k*k,0})
		local sky=plane_poly_clip(n,p,farplane)
		for _,v in pairs(sky) do
			v.x=64+((v[1]/v[3])<<6)
			v.y=64-((v[2]/v[3])<<6)
		end
		fillp(sky_fillp[k+1])		
		polyfill(sky,sky_gradient[k+1])
	end

	-- sun
	fillp(0xa5a5)
	local sun_pos=_cam:project({_cam.pos[1],_cam.pos[2]+64,_cam.pos[3]-64})
	if sun_pos then
		circfill(sun_pos.x,sun_pos.y,7+rnd(2),0xc7)
		circfill(sun_pos.x,sun_pos.y,5,0x7a)
	end
	fillp()

	local cy=_cam.pos[2]

	local scale=4*max(flr(cy/32+0.5),1)
	scale*=scale
	local x0,z0=_cam.pos[1],_cam.pos[3]
	local dx,dy=x0%scale,z0%scale
	
	for i=-4,4 do
		local ii=scale*i-dx+x0
		for j=-4,4 do
			local jj=scale*j-dy+z0
			local dot_pos=_cam:project({ii,0,jj})
			if dot_pos then
				pset(dot_pos.x,dot_pos.y,1)
			end
 		end
	end
end

-->8
-- update & main loop
function _init()
    -- enable 0x8000 memory region
    poke(0x5f36,0x10)

	local ramps={}
	-- get from spritesheet
	for c=0,15 do
		local ramp={}
		for i=0,3 do
			local base=sget(i,c)
			-- solid color
			ramp[2*i]=base*0x11
			-- intermediate color (dithered)
			ramp[2*i+1]=base|sget(i+1,c)<<4
		end
		ramps[c]=ramp
	end
    -- unpack models
    decompress(0x8000,unpack_models,ramps)

    _cam=make_cam("main")
end

_player_angle=0
_player_da=0
_player_ttl=0
_player_pos={0,60,0}
function _update()
	_player_angle+=_player_da
	_player_ttl-=1
	if(_player_ttl<0) _player_ttl=10+rnd(15) _player_da=(1-rnd(2))/64
	
	_player_orient=make_m_from_euler(0,0,_player_angle)
	_player_pos=v_add(_player_pos,m_fwd(_player_orient),-8)
	m_set_pos(_player_orient,_player_pos)

    _cam:track(_player_pos,_player_orient)
end

function _draw()
    draw_ground()

    local out={}
    collect_faces(_models["bf109"],_player_orient,out)
	sort(out)

	-- dithered fill mode
  	fillp(0xa5a5)

    draw_faces(out)

	fillp()

	-- memory
	-- print(stat(0).."b",2,2,8)
end

-->8
-- unpack 1 or 2 bytes
function unpack_variant(force)
	local h=mpeek()
	-- above 127?
  if force or h&0x80>0 then
    h=(h&0x7f)<<8|mpeek()
  end
	return h
end
-- unpack a float from 2 bytes
function unpack_double(scale)
	local f=(unpack_variant(true)-0x4000)>>4
	return f*(scale or 1)
end
-- unpack an array of bytes
function unpack_array(fn)
	for i=1,unpack_variant() do
		fn(i)
	end
end

-- valid chars for model names
function unpack_string()
	local s=""
	unpack_array(function()
		s=s..chr(mpeek())
	end)
	return s
end

function unpack_models(ramps)
    -- for all models
	unpack_array(function()
        local model,name,scale={lods={}},unpack_string(),1
        -- printh("decoding:"..name)
        -- lods
        unpack_array(function()
            local verts,lod={},{f={},dist=unpack_double()}
            -- vertices
            unpack_array(function()
                add(verts,{unpack_double(scale),unpack_double(scale),unpack_double(scale)})
            end)
			local function unpack_face()			
                local flags,f=mpeek(),{}
				-- colors
				f.ramp=ramps[flags&0xf]

				-- backface?
				if(flags&0x10!=0) f.dual_sided=true
				-- edge rendering?
				if(flags&0x40!=0) f.edges=true
                -- quad?
                f.ni=(flags&0x20!=0) and 4 or 3
                -- vertex indices
                for i=1,f.ni do
                    -- direct reference to vertex
                    f[i]=verts[unpack_variant()]
                end

				-- inner faces?
				if flags&0x80!=0 then
					f.inner={}
					unpack_array(function()
						add(f.inner,unpack_face())
					end)
				end

				return f
			end

            -- faces
            unpack_array(function()				
				local f=add(lod.f,unpack_face())
                -- normal
                f.n={unpack_double(),unpack_double(),unpack_double()}
                -- n.p cache
                f.cp=v_dot(f.n,f[1])
            end)

            add(model.lods,lod)
        end)
		-- index by name
		_models[name]=model
	end)
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01c77000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
128e7000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
13bba000300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
249aa000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1567a000500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
567aa000600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
67aaa000700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
28ef7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
49f7a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
9aaaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
3bbaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1c777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5d677000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2e8ee000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
5faaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
