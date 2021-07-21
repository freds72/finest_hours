import os
from subprocess import Popen, PIPE
import tempfile
import logging
import argparse
from python2pico import *
from lzs import Codec
from dotdict import dotdict

local_dir = os.path.dirname(os.path.realpath(__file__))
blender_exe = os.path.expandvars(os.path.join("%programfiles%","Blender Foundation","Blender 2.92","blender.exe"))

def call(args):
    proc = Popen(args, stdout=PIPE, stderr=PIPE, cwd=local_dir)
    out, err = proc.communicate()
    exitcode = proc.returncode
    #
    return exitcode, out, err

# compress the given byte string
# raw = True returns an array of bytes (a byte string otherwise)
def compress_byte_str(s,raw=False,more=False):
  b = bytes.fromhex(s)
  min_size = len(b)
  min_off = 8
  min_len = 3
  if more:
    for l in tqdm(range(8), desc="Compression optimization"):
      cc = Codec(b_off = min_off, b_len = l) 
      compressed = cc.toarray(b)
      if len(compressed)<min_size:
        min_size=len(compressed)
        min_len = l      
  
    logging.debug("Best compression parameters: O:{} L:{} - ratio: {}%".format(min_off, min_len, round(100*min_size/len(b),2)))

  # LZSS compressor  
  cc = Codec(b_off = min_off, b_len = min_len) 
  compressed = cc.toarray(b)
  if raw:
    return compressed
  return "".join(map("{:02x}".format, compressed))

def pack_models(home_path):
    # data buffer
    blob = ""

    # 3d models
    file_list = ['mountain','bf109']
    blob += pack_variant(len(file_list))
    for blend_file in file_list:
        logging.info("Exporting: {}.blend".format(blend_file))
        fd, path = tempfile.mkstemp()
        try:
            os.close(fd)
            exitcode, out, err = call([blender_exe,os.path.join(home_path,"models",blend_file + ".blend"),"--background","--python","blender_export.py","--","--out",path])
            if err:
                raise Exception('Unable to loadt: {}. Exception: {}'.format(blend_file,err))
            logging.debug("Blender exit code: {} \n out:{}\n err: {}\n".format(exitcode,out,err))
            with open(path, 'r') as outfile:
                blob += pack_string(blend_file)
                blob += outfile.read()
        finally:
            os.remove(path)
    return blob

def pack_archive(pico_path, home_path, compress=False, release=None, compress_more=False, test=False):
    blob = ""
    # todo: pack map

    # pack models
    blob = pack_models(home_path)

    if not test:
        game_data = compress and compress_byte_str(blob, more=compress_more) or blob
        # must fit into the 0x8000 extended region
        data_len = int(len(game_data)/2)
        if data_len>32767:
            raise Exception("Game data too large ({} bytes), exceeds max. 32767 bytes".format(data_len))

        # pack data
        bootloader_code="""\
pico-8 cartridge // http://www.pico-8.com
version 29
__lua__
-- finest hours
-- @freds72
-- *********************************
-- generated code - do not edit
-- *********************************
function _init()
    -- enable 0x8000 memory region
    poke(0x5f36,0x10)
    memcpy(0x8000,0x0,32767)
    load("game")
end
"""
        to_multicart(game_data, pico_path, os.path.join(home_path,"carts"), "dat", boot_code=bootloader_code)

def main():
  global blender_exe
  parser = argparse.ArgumentParser()
  parser.add_argument("--pico-home", required=True, type=str, help="Full path to PICO8 folder")
  parser.add_argument("--home", required=True, type=str, help="Root of game files (carts, models...)")
  parser.add_argument("--compress", action='store_true', required=False, help="Enable compression (default: false)")
  parser.add_argument("--compress-more", action='store_true', required=False, help="Brute force search of best compression parameters. Warning: takes time (default: false)")
  parser.add_argument("--release", required=False,  type=str, help="Generate html+bin packages with given version. Note: compression mandatory if number of carts above 16.")
  parser.add_argument("--test", action='store_true', required=False, help="Test mode - does not write cart data")
  parser.add_argument("--blender-location", required=False, type=str, help="Full path to Blender 2.9+ executable (default: {})".format(blender_exe))

  args = parser.parse_args()

  logging.basicConfig(level=logging.INFO)
  if args.blender_location:
    blender_exe = args.blender_location
  logging.debug("Blender location: {}".format(blender_exe))
  # test Blender path
  if not os.path.isfile(os.path.join(blender_exe)):
    raise Exception("Unable to locate Blender app at: {}".format(blender_exe))

  pack_archive(args.pico_home, args.home, compress=args.compress or args.compress_more, release=args.release, compress_more=args.compress_more, test=args.test)
  logging.info('DONE')
    
if __name__ == '__main__':
    main()

