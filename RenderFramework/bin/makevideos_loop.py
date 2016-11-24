# Version 3

import sys
import os
import shutil
import subprocess
import re


def natural_sort(l): 
    convert = lambda text: int(text) if text.isdigit() else text.lower() 
    alphanum_key = lambda key: [ convert(c) for c in re.split('([0-9]+)', key) ] 
    return sorted(l, key = alphanum_key)


if len(sys.argv) < 3:
	print("Usage: makevideos.py [image_directory] [fps] ([repeat count] ([output file prefix]))")
	sys.exit(1)
	
IMAGE_DIRECTORY = sys.argv[1]
FPS = int(sys.argv[2]) if len(sys.argv) >= 3 else 30
TEMP_DIRECTORY = os.path.join(IMAGE_DIRECTORY, "video_temp")

REPEAT = int(sys.argv[3]) if len(sys.argv) >= 4 else 1

OUT_PREFIX = sys.argv[4] if len(sys.argv) >= 5 else "out"

FFMPEG = "C:\\program files\\winff\\ffmpeg.exe"


def unlinkIfEmpty(path):
	'''Deletes a file if it is empty.'''
	try:
		if os.stat(path).st_size == 0:
			os.unlink(path)
	except OSError:
		pass

	
# Make the temp directory.
try:
	os.makedirs(TEMP_DIRECTORY)	
except:
	pass

# Clean the directory.
try:
	for file in os.listdir(TEMP_DIRECTORY):
		basename, extension = os.path.splitext(file)
		if extension == ".png" and basename.startswith("temp"):
			os.unlink(os.path.join(TEMP_DIRECTORY, file))
except:
	pass

# Collect the frames to the temp directory.
files = os.listdir(IMAGE_DIRECTORY)
files = natural_sort(files)

output_frame = 0

for i in range(REPEAT):
	for file in files + files[::-1]:
		basename, extension = os.path.splitext(file)
		if extension != ".png":
			continue
			
		# Copy with image number.
		in_file = os.path.join(IMAGE_DIRECTORY, file)
		out_file = os.path.join(TEMP_DIRECTORY, "temp%06d.png" % output_frame)
				
		shutil.copy2(in_file, out_file)
		
		output_frame += 1
	
# Make the video.
basename = OUT_PREFIX
out_file = basename + ".mp4"
stdout_file = basename + "_stdout.txt"
stderr_file = basename + "_stderr.txt"
	
if os.path.exists(out_file):
	os.unlink(out_file)
	
PARAMETERS = [
	FFMPEG,
	"-r", "%d" % FPS,
	"-f", "image2",
	"-i", "%s/temp%%06d.png" % TEMP_DIRECTORY,
	"-c:v", "libx264",
	"-r", "%d" % FPS,
	"-pix_fmt", "yuv420p", #"bgr24", #"yuv444p", # 
	"-b:v", "24000k", #"9600k",
	"-profile:v", "high",
	"-level", "4.2",
	out_file
]
	
subprocess.Popen(
	PARAMETERS,
	stdout = open(stdout_file, "w"),
	stderr = open(stderr_file, "w")
).communicate()	

unlinkIfEmpty(stdout_file)
unlinkIfEmpty(stderr_file)