import sys
import os
import shutil
import subprocess
import time


MITSUBA = "dist/mitsuba"


if len(sys.argv) < 4:
	print("Usage: python {0} [config name] [cpu count] [batch index]".format(sys.argv[0]))
	sys.exit(1)

# Read configuration.
CONFIG_NAME = sys.argv[1]
CPU_COUNT = int(sys.argv[2])
BATCH_INDEX = int(sys.argv[3])

PARAMETER_FILE = "configs/{0}_parameters.cfg".format(CONFIG_NAME)
STORE_FILE = "configs/{0}_store.cfg".format(CONFIG_NAME)

PARAMETERS = open(PARAMETER_FILE).readlines()[BATCH_INDEX].strip()
STORE_DIRECTORY = os.path.join("results", open(STORE_FILE).readlines()[BATCH_INDEX]).strip()

MTS_IDENTIFIER = os.getenv('MTS_IDENTIFIER', '')


# Create the result directory.
try:
	os.makedirs(STORE_DIRECTORY)
except:
	pass

# Run the task with the given configuration.
if CPU_COUNT > 0:
	cpu_flag = "-p {0}".format(CPU_COUNT)
else:
	cpu_flag = ""
	
commandline = MITSUBA + " -z -o {0}/image {1} {2}".format(STORE_DIRECTORY, PARAMETERS, cpu_flag)


# Store the command line.
file = open(os.path.join(STORE_DIRECTORY, "info_commandline.txt"), "w")
file.write(commandline)
file.close()

# Store the command line.
file = open(os.path.join(STORE_DIRECTORY, "info_job_identifier.txt"), "w")
file.write(MTS_IDENTIFIER)
file.close()

# Write the config name.
file = open(os.path.join(STORE_DIRECTORY, "cluster_batch.txt"), "w")
file.write("{0}".format(CONFIG_NAME))
file.close()

start_time = time.time()
subprocess.call(commandline.split(" "))
end_time = time.time()

# Rename the results.
for file in os.listdir(STORE_DIRECTORY):
	source_file = os.path.join(STORE_DIRECTORY, file)
	
	target_file = file.replace("_iter1_0", "")	
	target_file = os.path.join(STORE_DIRECTORY, target_file)
	
	if file.startswith("image"):
		shutil.move(source_file, target_file)

# Copy the batch identifier.
shutil.copy2(os.path.join(STORE_DIRECTORY, "cluster_batch.txt"), os.path.join(STORE_DIRECTORY, os.pardir, "cluster_batch.txt"))

# Store the elapsed time.
file = open(os.path.join(STORE_DIRECTORY, "info_rendering_time.txt"), "w")
file.write("{0}".format(end_time - start_time))
file.close()

# Create the timestamps.
file = open(os.path.join(STORE_DIRECTORY, "timestamp.txt"), "w");
file.write("{0}".format(int(time.time())))
file.close()
shutil.copy2(os.path.join(STORE_DIRECTORY, "timestamp.txt"), os.path.join(STORE_DIRECTORY, os.pardir, "timestamp.txt"))
