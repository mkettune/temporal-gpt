# Heuristically checks the output files of a batch for failed tasks,
# and if requested, creates new configuration files for only these tasks.
import sys
import os
import shutil
import subprocess
import time
import shutil

def help():
	print("Usage: python {0} [config name] [--check|--filter]".format(sys.argv[0]))
	sys.exit(1)

if len(sys.argv) != 3:
	help()

filter = False
set_filter = False

config_name = ""

for arg in sys.argv[1:]:
	if arg == "--check":
		filter = False
		set_filter = True
	elif arg == "--filter":
		filter = True
		set_filter = True
	else:
		if config_name:
			help()
		else:
			config_name = arg

if not set_filter:
	help()


# Read configuration.
CONFIG_NAME = sys.argv[1]

PARAMETER_FILE = "configs/{0}_parameters.cfg".format(CONFIG_NAME)
STORE_FILE = "configs/{0}_store.cfg".format(CONFIG_NAME)
TASK_FILE = "configs/{0}_tasks.cfg".format(CONFIG_NAME)

NEW_PARAMETER_FILE = "configs/{0}-filtered_parameters.cfg".format(CONFIG_NAME)
NEW_STORE_FILE = "configs/{0}-filtered_store.cfg".format(CONFIG_NAME)
NEW_TASK_FILE = "configs/{0}-filtered_tasks.cfg".format(CONFIG_NAME)

task_lines = open(TASK_FILE).readlines()
store_lines = open(STORE_FILE).readlines()
parameter_lines = open(PARAMETER_FILE).readlines()


if filter:
	task_file = open(NEW_TASK_FILE, 'w')

for i in range(len(task_lines)):
	store_directory = os.path.join("results", store_lines[i].strip())

	# Check the total size of EXRs
	failed = ""

	if not os.path.isdir(store_directory):
		failed = "Directory not found."
	else:
		filelist = os.listdir(store_directory)
		exr_size = 0.0

		has_primal = False

		for file in filelist:
			filepath = os.path.join(store_directory, file)
			file_size = os.path.getsize(filepath)

			if file.endswith('-dx.exr') or file.endswith('-dy.exr') or file.endswith('-primal.exr') or file.endswith('-direct.exr'):
				if file.endswith('-direct.exr'):
					if file_size < 20000:
						failed = "File {0} has questionable size: {1}".format(file, file_size)
				elif file_size < 500*1024:
					failed = "File {0} has questionable size: {1}".format(file, file_size)
	
			if file.endswith("-primal.exr") or file.endswith("-image.exr"):
				has_primal = True
		
			if file_size == 0:
				failed = "Empty file: {0}".format(file)
				break

		if not has_primal:
			failed = "No primal image."
	
	#if total_size < 2*1024*1024:	
	if failed:
		if not filter:
			print("Task {0} ({1}) failed: {2}".format(i, store_directory, failed))
		else:
			task_file.write("{0}".format(task_lines[i]))
			#store_file.write("{0}".format(store_lines[i]))
			#parameter_file.write("{0}".format(parameter_lines[i]))

		# total .exr size: {2}".format(i, store_directory, total_size))
		#	print("Task {0} ({1}): total .exr size: {2}".format(i, store_directory, total_size))


if filter:
	task_file.close()
	shutil.copy2(PARAMETER_FILE, NEW_PARAMETER_FILE)
	shutil.copy2(STORE_FILE, NEW_STORE_FILE)
	print("Wrote configuration \"{0}-filtered\".".format(CONFIG_NAME))
