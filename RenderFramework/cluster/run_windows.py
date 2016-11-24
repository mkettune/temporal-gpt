#!/usr/bin/python
import sys
import os
import string
import datetime
import subprocess
from optparse import OptionParser
	

CPUS_PER_TASK = 8

	
# Configure commandline parameters.
parser = OptionParser(usage="usage: %prog [config]")
(options, args) = parser.parse_args()


# Set defaults.
render_time = 0
config = 'default'

if args:
	config = args[0]


def runBatch(config, batch_index):
	config_name = "{0}__{1}".format(config, batch_index)

	# Check that the files exist.
	for path in ["configs/%s_parameters.cfg" % config_name,
				"configs/%s_store.cfg" % config_name,
				"configs/%s_tasks.cfg" % config_name]:
		if not os.path.isfile(path):
			print('Config "%s" not found!' % config_name)
			sys.exit(1)
	
	
	# Run jobs.
	tasks_file = "configs/%s_tasks.cfg" % config_name
	job_count = len(open(tasks_file).readlines())
	
	for parameters in open(tasks_file).readlines():
		command = "python task_run.py {} {} {}".format(config_name, CPUS_PER_TASK, parameters.strip())
		print(command)
		subprocess.call(command, shell=True);

# Run batches.
runBatch(config, 0)
runBatch(config, 1)
runBatch(config, 2)
