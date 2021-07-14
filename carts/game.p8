pico-8 cartridge // http://www.pico-8.com
version 32
__lua__
function _init()
    -- enable 0x8000 memory region
    poke(0x5f36,0x10)    
end
__gfx__
