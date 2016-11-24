import os
import shutil


# Fix accidentally wrongly named directories. To get at least something done without needing to re-render.
#
# Modify as needed.


format = "frame%03d_path_seed%d"


for file in os.listdir("."):
	if not os.path.isdir(file):
		continue
		
	frame = int(file[5:8])
	seed = int(file[18:])
	
	infile = format % (frame, seed)
	outfile = format % (frame, frame)
	
	#print("{} -> {}".format(infile, outfile))
	shutil.move(infile, outfile)
