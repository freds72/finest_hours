pico-8 cartridge // http://www.pico-8.com
version 32
__lua__

#include plain.lua
#include poly.lua

-- globals
local _models={}

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
function m_x_v(m,v)
	local x,y,z=v[1],v[2],v[3]
	return {m[1]*x+m[5]*y+m[9]*z+m[13],m[2]*x+m[6]*y+m[10]*z+m[14],m[3]*x+m[7]*y+m[11]*z+m[15]}
end

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

-- inline matrix vector multiply invert
-- inc. position
function m_inv_x_v(m,v)
	local x,y,z=v[1]-m[13],v[2]-m[14],v[3]-m[15]
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
	local a11,a21,a31,_,a12,a22,a32,_,a13,a23,a33,_,a14,a24,a34=unpack(a)
	local b11,b21,b31,_,b12,b22,b32,_,b13,b23,b33,_,b14,b24,b34=unpack(b)

	return {
			a11*b11+a12*b21+a13*b31,a21*b11+a22*b21+a23*b31,a31*b11+a32*b21+a33*b31,0,
			a11*b12+a12*b22+a13*b32,a21*b12+a22*b22+a23*b32,a31*b12+a32*b22+a33*b32,0,
			a11*b13+a12*b23+a13*b33,a21*b13+a22*b23+a23*b33,a31*b13+a32*b23+a33*b33,0,
			a11*b14+a12*b24+a13*b34+a14,a21*b14+a22*b24+a23*b34+a24,a31*b14+a32*b24+a33*b34+a34,1
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
-- camera
function make_cam(name)
    return {
	    pos={0,0,0},    
		track=function(self,pos,m)
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

function collect_faces(faces,cam_pos,v_cache,out)
	for _,face in pairs(faces) do
		-- avoid overdraw for shared faces
		if face.flags&0x10!=0 or v_dot(face.n,cam_pos)>face.cp then
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
					-- sort key
					verts.key=-z/ni
					out[#out+1]=verts
				end
			end
		end
	end
end

function collect_model_faces(model,m,out)
	-- cam pos in object space
	local cam_pos=m_inv_x_v(m,_cam.pos)
	
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
	m=m_x_m(_cam.m,m)

	-- vertex cache (and model context)
	local p=setmetatable({m=m},v_cache_cls)

	-- main model
	collect_faces(model.f,cam_pos,p,out)
end

-- draw face
function draw_faces(faces)
	for i,d in ipairs(faces) do
		local face=d.f
		polyfill(d,face.flags&0xf)
	end
end

-->8
-- update & main loop
function _init()
    -- enable 0x8000 memory region
    poke(0x5f36,0x10)

    -- unpack models
    decompress(0x8000,unpack_models)

    _cam=make_cam("main")
end

function _update()
    local m=make_m_from_euler(0,0,0)

    _cam:track({0,20,-50},m)
end

function _draw()
    cls(1)

    local m=make_m_from_euler(0,time()/8,0)
    local out={}
    collect_model_faces(_models["bf109"],m,out)
				sort(out)
    draw_faces(out)
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

function unpack_models()
    -- for all models
	unpack_array(function()
        local model,name,scale={lods={}},unpack_string(),1
        -- printh("decoding:"..name)
        -- lods
        unpack_array(function()
            local verts,lod={},{f={},dist=unpack_double(),groups={}}
            -- vertices
            unpack_array(function()
                add(verts,{unpack_double(scale),unpack_double(scale),unpack_double(scale)})
            end)

            -- faces
            unpack_array(function(i)
                local f=add(lod.f,{flags=mpeek(),gid=mpeek()})
                -- collision group
                if(f.gid>0) lod.groups[f.gid]=1+(lod.groups[f.gid] or 0)

                -- quad?
                f.ni=(f.flags&0x20!=0) and 4 or 3
                -- vertex indices
                for i=1,f.ni do
                    -- direct reference to vertex
                    f[i]=verts[unpack_variant()]
                end
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
