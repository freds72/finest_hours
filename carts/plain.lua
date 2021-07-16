-- plain read from cart (e.g. not compressed)
function decompress(mem,fn,...)
	-- register global mpeek function
	mpeek=function()
		local b=@mem
		mem+=1
		return b
	end
	-- deserialize in context	
	return fn(...)
end