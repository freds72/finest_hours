pico-8 cartridge // http://www.pico-8.com
version 32
__lua__

#include plain.lua
#include poly.lua

-- globals
local _models,_sun_dir,_cam,_plyr={},{0,-0.707,0.707}
local _tick=0

local k_far,k_near=0,2
local k_right,k_left=4,8
local z_near=8

#include math.lua

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
			up=v_normz(v_lerp(up,target_u,0.2))

			-- pos tracking (without view offset)
			target_pos=v_lerp(target_pos,v_add(pos,m_fwd(m),-60),0.05)

			-- behind player
			m=make_m_look_at(up,make_v(target_pos,pos))

			-- shift cam position
			pos=v_add(target_pos,up,30)

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

	-- todo: get animation speed from model
	local tick=_tick%3
	for _,face in pairs(model.f) do
		if (face.frame and face.frame!=tick) goto skip
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
					verts.light=mid(-v_dot(sun,face.n),0,1)
					verts.cache=v_cache
					-- sort key
					-- todo: improve
					verts.key=-z/ni
					out[#out+1]=verts
				end
			end
		end
		::skip::
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
		-- todo: fix (why *16 doesn't work for light???)
		local main_face,light,col=d.f,(d.light<<3)\1
		-- todo: get shininess factor from model
		local col=main_face.ramp[light]

		polyfill(d,col)
		-- decals? (hiden when unlit)
		if light>0 and main_face.inner then
			-- reuse array
			for _,face in pairs(main_face.inner) do
				local v_cache,v4=d.cache,face[4]
				-- reuse light info
				draw_face(v_cache[face[1]],v_cache[face[2]],v_cache[face[3]],v4 and v_cache[v4],face.ramp[light])
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
-- player controller (reads input from controller)
function make_player_controller()
	return {
		init=function()
			-- power: 80
			return 80
		end,
		update=function(self)
			local dpow,droll,dpitch=0,0,0
			if(btn(4)) dpow=1
			if(btn(5)) dpow=-1
			if(btn(0)) droll=1
			if(btn(1)) droll=-1
			if(btn(2)) dpitch=1
			if(btn(3)) dpitch=-1
			return dpow,droll,dpitch
		end
	}
end

function make_level_controller()
	return {
		init=function()
			-- power: 80
			return 80
		end,
		update=function(self)
			return 0,0,0
		end
	}
end

-- make a plane "physic object"
function make_plane(model,pos,ctrl)
	local time_t=0
	local roll,pitch=0,0
	local yaw,dyaw=0,0
	local power,rpm=ctrl:init(),0
	local forces,velocity,angularv={0,0,0},{0,0,0},{0,0,0}

	return {
		model=_models[model],
		pos=v_clone(pos),
		m=make_m_from_euler(0,0,0),
		apply_force=function(self,v,scale)
			scale=scale or 1
			forces=v_add(forces,v,scale/30)
		end,
		update=function(self)
			time_t+=1
			local dpow,droll,dpitch=ctrl:update()

			-- damping
			roll*=0.8
			pitch*=0.8

			-- controls
			roll+=droll/1024
			pitch+=dpitch/2048

			-- current orientation
			local fwd,up,right=m_fwd(self.m),m_up(self.m),m_right(self.m)

			-- gravity
			self:apply_force({0,-1,0})

			-- power --> rpm
			power=mid(power+dpow/4,0,100)
			-- engine "delay"
			rpm=lerp(rpm,power,0.6)
			-- engine max force
			self:apply_force(fwd,rpm/64)

			-- lift?
			local vn,vlen=v_normz(velocity)
			self.vlen=vlen

			local lift=vlen*vlen*(1-v_dot(vn,fwd)/2)
			self.lift=lift
			local antilift=v_dot(up,vn)
			-- todo: fix
			self:apply_force(up,lift*(antilift>0 and -1 or 1))

			-- drag
			self:apply_force(velocity,-lift/5)

			-- tail drag
			local drag=-vlen*vlen*v_dot(vn,right)/80
			self:apply_force(right,drag)
			yaw*=0.4
			yaw=-drag

			-- integrate
			velocity=v_add(velocity,forces)

			-- move
			self.pos=v_add(self.pos,velocity)

			-- todo: boom!
			if self.pos[2]<0 then
				self.pos[2]=0
				velocity[2]=0
			end

			self.m=m_x_m(self.m,make_m_from_euler(pitch,yaw,roll))
			m_set_pos(self.m,self.pos)
			forces={0,0,0}
		end
	}
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
		for i=0,6 do
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
	
	_plyr=make_plane("bf109",{0,60,0},make_player_controller())
	_things={}
	add(_things, _plyr)
	add(_things,make_plane("bf109",{-45,60,25},make_level_controller()))
	add(_things,make_plane("bf109",{90,80,10},make_level_controller()))

	_props={}
	for i=1,5 do
		local pos,m={512*cos(i/6),0,512*sin(i/6)},make_m_from_euler(0,rnd(),0)
		m_set_pos(m,pos)
		add(_props,{
			model=_models["mountain"],
			m=m})
	end
end

function _update()
	for _,thing in pairs(_things) do
		thing:update()
	end

    _cam:track(_plyr.pos,_plyr.m)
	_tick+=1
end

function _draw()
    draw_ground()

    local out={}
	for _,thing in pairs(_things) do
		collect_faces(thing.model,thing.m,out)
	end

	for _,prop in pairs(_props) do
    	collect_faces(prop.model,prop.m,out)
	end
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
                local flags,f=mpeek(),{ramp=ramps[mpeek()]}
				-- animation frame?
				if(flags&0x10!=0) f.frame=mpeek()
				-- backface?
				if(flags&0x1!=0) f.dual_sided=true
				-- edge rendering?
				if(flags&0x4!=0) f.edges=true

                -- quad?
                f.ni=(flags&0x2!=0) and 4 or 3

                -- vertex indices
                for i=1,f.ni do
                    -- direct reference to vertex
                    f[i]=verts[unpack_variant()]
                end

				-- inner faces?
				if flags&0x8!=0 then
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
0011cc77100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
012888e7200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01333bba300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
124499aa400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0155567a500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
156677aa600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
16777aaa700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
12288ef7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
14499f77000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
19aaa777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
133bbba7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011cc777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
15d66677000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
022eefaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
15fffaa7000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
