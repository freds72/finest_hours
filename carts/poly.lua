-- foley rasterizer
function polyfill(p,col)
	--find top & bottom of poly
	local np,miny,maxy,mini=#p,32000,-32000
	for i=1,np do
		local y=p[i].y
		if (y<miny) mini,miny=i,y
		if (y>maxy) maxy=y
	end
	if(not mini) return
	color(col)
	--data for left & right edges:
	local li,lj,ri,rj,ly,ry,lx,ldx,rx,rdx=mini,mini,mini,mini,miny-1,miny-1

	--step through scanlines.
	for y=max(miny\1+1),min(maxy,127) do
		--maybe update to next vert
		while ly<y do
			li,lj=lj,lj+1
			if (lj>np) lj=1
			local v0,v1=p[li],p[lj]
			local y0,y1=v0.y,v1.y
			ly=y1&-1
			lx=v0.x
			ldx=(v1.x-lx)/(y1-y0)
			--sub-pixel correction
			lx+=(y-y0)*ldx
		end   
		while ry<y do
			ri,rj=rj,rj-1
			if (rj<1) rj=np
			local v0,v1=p[ri],p[rj]
			local y0,y1=v0.y,v1.y
			ry=y1&-1
			rx=v0.x
			rdx=(v1.x-rx)/(y1-y0)
			--sub-pixel correction
			rx+=(y-y0)*rdx
		end
		rectfill(lx,y,rx,y)
		lx+=ldx
		rx+=rdx
	end
end

function polyfill2(p,col)
	color(col)
	local np=#p
	for i=1,np do
		local p0,p1=p[i%np+1],p[i]
		line(p0.x,p0.y,p1.x,p1.y)
	end
end