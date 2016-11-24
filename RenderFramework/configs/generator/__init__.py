import os
import copy
import sys
import math


def setDefaultParameters(parameters):
    if not 'use_l1' in parameters and not 'use_l2' in parameters:
        parameters['use_l1'] = True
        parameters['use_l2'] = False
    elif not 'use_l1' in parameters:
        parameters['use_l1'] = False
    elif not 'use_l2' in parameters:
        parameters['use_l2'] = False
        
    if not 'useMotionVectors' in parameters:
        parameters['useMotionVectors'] = False
        
    return parameters

def formatKeyValue(key, value):
    if value is True:
        return "{}".format(key)
    elif value is False:
        return "no" + key[0].capitalize() + key[1:]
    else:
        return "{}{}".format(key, value)
    
def getDefaultTaskName(scene, integrator, spp, shutter_time, frame_count, render_parameters = {}):
    task_name = '{}-{}frames-shutter{}'.format(scene, frame_count, shutter_time)
    
    custom_parameter_strings = [formatKeyValue(key, value) for key, value in render_parameters.items()]
    task_name = '-'.join([task_name] + sorted(custom_parameter_strings))
    
    task_name += "-{}spp-{}".format(spp, integrator)
    
    return task_name
    
def getTgptTaskName(scene, integrator, spp, shutter_time, frame_count, render_parameters = {}):
    task_name = '{}-{}frames-shutter{}'.format(scene, frame_count, shutter_time)
    
    custom_parameter_strings = [formatKeyValue(key, value) for key, value in render_parameters.items()]
    task_name = '-'.join([task_name] + sorted(custom_parameter_strings))
    
    task_name += "-2x{}spp-{}".format(spp, integrator)
    
    return task_name
    
def makeParentDirectories(path):
    if not os.path.isdir(os.path.dirname(path)):
        os.makedirs(os.path.dirname(path))
    
def help():
    print("usage: {} [name for generated config]".format(sys.argv[0]))
    
def getConfigName(argv):
    if len(argv) == 1:
        return 'default'
        
    if len(argv) == 2:
        if argv[1] in ('-h', '--help'):
            help()
            sys.exit(1)
        else:
            return argv[1]
    
    help()
    sys.exit(1)
    
    
class Batch:
    def __init__(self, cluster_path, config_name, batch_index):
        self.index = 0 # Index of the current job in the batch.
        self.parameter_file_path = '{}/configs/{}__{}_parameters.cfg'.format(cluster_path, config_name, batch_index)
        self.task_file_path = '{}/configs/{}__{}_tasks.cfg'.format(cluster_path, config_name, batch_index)
        self.store_file_path = '{}/configs/{}__{}_store.cfg'.format(cluster_path, config_name, batch_index)
        
        # Prepare output data.
        self.parameters = []
        self.tasks = []
        self.stores = []
        
    def addJob(self, parameters, outdir):
        '''Adds a render job to be executed.'''
        self.parameters.append(parameters + '\n')
        self.tasks.append('{}\n'.format(self.index))
        self.stores.append(outdir + '\n')
        self.index += 1
    
    def empty(self):
        '''Returns whether the Batch is empty.'''
        return not self.tasks
    
    def close(self):
        # Output the files.

        # Make the required directories.
        makeParentDirectories(self.parameter_file_path)
        makeParentDirectories(self.task_file_path)
        makeParentDirectories(self.store_file_path)
        
        # Output the files.
        parameter_file = open(self.parameter_file_path, "w", newline='\n')
        task_file = open(self.task_file_path, "w", newline='\n')
        store_file = open(self.store_file_path, "w", newline='\n')
        
        for parameter, task, store in zip(self.parameters, self.tasks, self.stores):
            parameter_file.write(parameter)
            task_file.write(task)
            store_file.write(store)
                    
        store_file.close()
        task_file.close()
        parameter_file.close()
            
            

    
class Generator:
    TGPT_PLAIN = 1   # TGPT reconstruction flag: with dt, no ddxt
    TGPT_DDXT = 2    # TGPT reconstruction flag: with dt, with ddxt
    TGPT_NO_TIME = 4 # TGPT reconstruction flag: no dt, no ddxt

    PSS_TGPT_ONLY_DX = 1 # PSS TGPT reconstruction flag: only spatial gradients
    PSS_TGPT_ONLY_DT = 2 # PSS TGPT reconstruction flag: only temporal gradients
    PSS_TGPT_DX_DT = 4   # PSS TGPT reconstruction flag: with dx, with dt.
    
    BATCH_DEPENDENCY_TARGET = 0 # Batch to which something in BATCH_DEPENDENT depends on.
    BATCH_INDEPENDENT = 1       # Batch whose jobs are independent.
    BATCH_DEPENDENT = 2         # Batch whose jobs depend on BATCH_DEPENDENCY_TARGET.
    
    def __init__(self, cluster_path, argv = None):
        # Read sys.argv by default. This is dirty but keeps the user clean in the usual use case.
        if argv is None:
            argv = sys.argv
            
        self.config_name = getConfigName(argv)
        self.cluster_path = cluster_path   # Path to the directory that's copied to the cluster.
        
        # Prepare the batch queues.
        self.batches = [
            Batch(self.cluster_path, self.config_name, 0),
            Batch(self.cluster_path, self.config_name, 1),
            Batch(self.cluster_path, self.config_name, 2)
        ]
                
    # Controls scheduling of render jobs.
    def queueRender(self, task, scene, outdir, seed, integrator, spp, frame_start_time, shutter_time, batch=BATCH_INDEPENDENT, frame_time=None, xml_sequence='', blocksize=32, loop_length=0.0, custom={}):
        '''Queues a single render with the given parameters.'''
        # Validate parameters.
        if type(spp) != int:
            print("Error: Task \"{}\": Non-integral sample count {}".format(task, spp))
            sys.exit(1)
            
        if frame_time is None:
            raise Exception("Frame time not set for queueRender.")
        
        # Convert custom parameters.
        converted_custom = {}
        for key, value in custom.items():
            if value is True:
                value = 'true'
            elif value is False:
                value = 'false'
            converted_custom[key] = value
        
        # Normalize time for sequenced scenes.
        if loop_length:
            frame_start_time = frame_start_time % loop_length
        
        if xml_sequence:
            frame_number = math.floor(frame_start_time)
            frame_start_time -= frame_number
            
            scene_input_xml = 'scenes/{}/{}'.format(scene, xml_sequence % frame_number)
        else:
            scene_input_xml = 'scenes/{}/batch.xml'.format(scene)
        
        # Construct the command line.
        commandline = '{} -b {} -Dsampler=deterministic -Dintegrator={} -Dseed={} -Dspp={} -DshutterOpen={} -DshutterClose={} {}'.format(
            scene_input_xml,
            blocksize,
            integrator,
            seed,
            spp,
            frame_start_time,
            frame_start_time + shutter_time,
            " ".join(["-D{}={}".format(key, value) for key, value in converted_custom.items()])
        )
        
        self.batches[batch].addJob(commandline, outdir)     
    
    def queueReconstruct(self, task, cluster_task, scene, frames, method, parameters):
        '''Stores reconstruction hint in the store directory.'''
        
        # Defaults.
        parameters = setDefaultParameters(parameters)
        
        try:
            os.makedirs("../results/{}".format(scene))
        except:
            pass
            
        # Add in internal parameters.
        parameters['internal__task_name'] = task
        parameters['internal__cluster_task_name'] = cluster_task
        parameters['internal__scene'] = scene
        parameters['internal__method'] = method
        parameters['internal__frame_range_begin'] = frames[0]
        parameters['internal__frame_range_end'] = frames[1]
        
        # Write the reconstruction file.
        result_directory = "../results/{}/{}".format(scene, task)
        if not os.path.isdir(result_directory):
            os.makedirs(result_directory)

        reconstruct_file_path = "{}/config.cfg".format(result_directory)
        
        reconstruct_file = open(reconstruct_file_path, "w", newline='\n')
        reconstruct_file.write("{}\n".format(len(parameters)))
        
        for key, value in sorted(parameters.items()):
            reconstruct_file.write("{}\n{}\n".format(key, value))
            
        reconstruct_file.close()

    def queuePlainTGPT(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                  render_parameters = {}, reconstruct_parameters = {},
                  seed_increment = 1, xml_sequence='', loop_length = 0.0,
                  task_name = ''):
        '''Convenience function for rendering an animation with Temporal GPT without adaptive sampling and motion blur.
           Parameter 'spp' is the total number of samples per pixel.'''
           
        render_parameters = copy.copy(render_parameters)
        
        if not 'useAdaptive' in render_parameters:
            render_parameters['useAdaptive'] = False
            
        if not 'samplingIterations' in render_parameters:
            render_parameters['samplingIterations'] = 1
            
        if not 'useMotionVectors' in render_parameters:
            render_parameters['useMotionVectors'] = False
        
        self.queueTGPT_raw(scene, seed, spp, frame_time, shutter_time, frame_count,
                           frame=frame, render_parameters=render_parameters, reconstruct_parameters=reconstruct_parameters,
                           seed_increment=seed_increment, xml_sequence=xml_sequence, loop_length=loop_length,
                           task_name=task_name)
                           
    def queueTGPT(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                  render_parameters = {}, reconstruct_parameters = {},
                  seed_increment = 1, xml_sequence='', loop_length = 0.0,
                  task_name = ''):
        '''Convenience function for rendering an animation with Temporal GPT with adaptive sampling and motion blur.
           Parameter 'spp' is the total number of samples per pixel.'''
           
        render_parameters = copy.copy(render_parameters)
        
        if not 'useAdaptive' in render_parameters:
            render_parameters['useAdaptive'] = True
            
        if not 'samplingIterations' in render_parameters:
            render_parameters['samplingIterations'] = 4
            
        if not 'useMotionVectors' in render_parameters:
            render_parameters['useMotionVectors'] = True
        
        self.queueTGPT_raw(scene, seed, spp, frame_time, shutter_time, frame_count,
                           frame=frame, render_parameters=render_parameters, reconstruct_parameters=reconstruct_parameters,
                           seed_increment=seed_increment, xml_sequence=xml_sequence, loop_length=loop_length,
                           task_name=task_name)
                      
    def queueTGPT_raw(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                      render_parameters = {}, reconstruct_parameters = {},
                      seed_increment = 1, xml_sequence='', loop_length = 0.0,
                      task_name = ''):
        '''Convenience function for rendering an animation with Temporal GPT.
           Parameter 'spp' is the total number of samples per pixel.'''
        
        if not task_name:
            task_name = getDefaultTaskName(scene, 'tgpt', spp, shutter_time, frame_count, render_parameters)
        
        spp = spp // 2
        
        render_parameters = copy.copy(render_parameters)
        reconstruct_parameters = copy.copy(reconstruct_parameters)
        
        if not task_name:
            task_name = getTgptTaskName(scene, 'tgpt', spp, shutter_time, frame_count, render_parameters)
        
        if not 'method' in reconstruct_parameters:
            reconstruct_parameters['method'] = self.TGPT_DDXT
                    
        FRAME_A_TEMPLATE = task_name + '/frame%03d_seed%d'
        FRAME_B_TEMPLATE = task_name + '/frame%03d_seed%d'
        
        # If motion vectors are used, then the reconstruction must also use the motion vector settings.
        
        if render_parameters.get('useMotionVectors') == True:
            reconstruct_parameters['useMotionVectors'] = True
        
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)
        
        
        # For adaptive sampling or motion vector set-ups, some jobs depend on others. Hence we make 2 renderQueues
        # (but only if adaptive sampling or motion vectors are really used).
        primaryBatch = self.BATCH_INDEPENDENT
        secondaryBatch = self.BATCH_INDEPENDENT
        hasDependencies = False
        
        useAdaptive = render_parameters.get('useAdaptive');
        samplingIterations = render_parameters.get('samplingIterations');
        useMotionVectors = render_parameters.get('useMotionVectors');
        
        if (useAdaptive == True and samplingIterations > 1) or useMotionVectors == True:
            primaryBatch = self.BATCH_DEPENDENCY_TARGET
            secondaryBatch = self.BATCH_DEPENDENT
            hasDependencies = True
        
        # Set block size.
        blocksize = 8 if useAdaptive else 32
        
        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
            
            # For frame 0 there is not previous frame, so frame000_seed0 can be rendered freely.
            currentBatch = secondaryBatch
            if i == 0 and hasDependencies:
                currentBatch = self.BATCH_INDEPENDENT
            
            # Render with seed i and store the results.
            if hasDependencies:
                if i == 0:
                    render_parameters.update({'isBase' : True})
                    render_parameters.update({'isTimeOffset' : False})
                else:
                    render_parameters.update({'isBase' : False})
                    render_parameters.update({'isTimeOffset' : True})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_A_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'gpt',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                batch = currentBatch,
                task = task_name,
                frame_time = frame_time,
                blocksize = blocksize,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
            current_seed += seed_increment
            
            if hasDependencies:
                render_parameters.update({'isBase' : True})
                render_parameters.update({'isTimeOffset' : False})
            
            # Render with seed i+1 and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_B_TEMPLATE % (i, i+1),
                seed = current_seed,
                integrator = 'gpt',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                batch = primaryBatch,
                task = task_name,
                frame_time = frame_time,
                blocksize = blocksize,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
        
        # Queue reconstruction.
        reconstruct_parameters['frameA_template'] = FRAME_A_TEMPLATE
        reconstruct_parameters['frameB_template'] = FRAME_B_TEMPLATE
        
        if reconstruct_parameters['method'] & self.TGPT_PLAIN:
            self.queueReconstruct(
                task = task_name + '-plain',
                cluster_task = task_name,
                scene = scene,
                frames = (0, frame_count - 1),
                method = 'gpt-gpt',
                parameters = reconstruct_parameters
            )

        if reconstruct_parameters['method'] & self.TGPT_DDXT:
            self.queueReconstruct(
                task = task_name + '-ddxt',
                cluster_task = task_name,
                scene = scene,
                frames = (0, frame_count - 1),
                method = 'tgpt-ddxt',
                parameters = reconstruct_parameters
            )
        
        if reconstruct_parameters['method'] & self.TGPT_NO_TIME:
            self.queueReconstruct(
                task = task_name + '-notime',
                cluster_task = task_name,
                scene = scene,
                frames = (0, frame_count - 1),
                method = 'gpt-notime',
                parameters = reconstruct_parameters
            )
            

    def queuePssTgpt(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                     render_parameters = {}, reconstruct_parameters = {},
                     seed_increment = 1, xml_sequence='', loop_length = 0.0,
                     task_name = ''):
        '''Convenience function for rendering an animation with Primary Sample Space TGPT.'''
        
        render_parameters = copy.copy(render_parameters)
        reconstruct_parameters = copy.copy(reconstruct_parameters)

        if not task_name:
            task_name = getDefaultTaskName(scene, 'pss-tgpt', spp, shutter_time, frame_count, render_parameters)
            
        spp //= 4
        
        if not 'method' in reconstruct_parameters:
            reconstruct_parameters['method'] = self.PSS_TGPT_DX_DT
        
        FRAME_A_TEMPLATE = task_name + '/frame%03d_seed%d'
        FRAME_AX_TEMPLATE = task_name + '/frame%03d_seed%d_x'
        FRAME_AY_TEMPLATE = task_name + '/frame%03d_seed%d_y'
        FRAME_B_TEMPLATE = task_name + '/frame%03d_seed%d'
                    
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)

        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
                        
            # Render with seed i and seedshift(0,0) and store the results.
            render_parameters.update({'seed_xoffset' : 0, 'seed_yoffset' : 0})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_A_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )

            #render with seed i and seedshift (-1,0)
            render_parameters.update({'seed_xoffset' : -1, 'seed_yoffset' : 0})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_AX_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
            #render with seed i and seedshift(0,-1)
            render_parameters.update({'seed_xoffset' : 0, 'seed_yoffset' : -1})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_AY_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
            #increment seed !
            current_seed += seed_increment
            
            # Render with seed i+1 and seedshift (0,0) and store the results.
            render_parameters.update({'seed_xoffset' : 0, 'seed_yoffset' : 0})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_B_TEMPLATE % (i, i+1),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
        
        # Queue reconstruction.
        reconstruct_parameters['frameA_template'] = FRAME_A_TEMPLATE
        reconstruct_parameters['frameB_template'] = FRAME_B_TEMPLATE
        
        if reconstruct_parameters['method'] & self.PSS_TGPT_ONLY_DX:
            self.queueReconstruct(
                task = task_name + '-dx',
                cluster_task = task_name,
                scene = scene,
                frames = (0, frame_count - 1),
                method = 'pss-tgpt-dx',
                parameters = reconstruct_parameters
            )
            
        if reconstruct_parameters['method'] & self.PSS_TGPT_ONLY_DT:
            self.queueReconstruct(
                task = task_name + '-dt',
                cluster_task = task_name,
                scene = scene,
                frames = (0, frame_count - 1),
                method = 'pss-tgpt-dt',
                parameters = reconstruct_parameters
            )

        if reconstruct_parameters['method'] & self.PSS_TGPT_DX_DT:
            self.queueReconstruct(
                task = task_name,
                cluster_task = task_name,
                scene = scene,
                frames = (0, frame_count - 1),
                method = 'pss-tgpt-dx-dt',
                parameters = reconstruct_parameters
            )
    
    def queuePssGpt(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                    render_parameters = {}, reconstruct_parameters = {},
                    seed_increment = 1, xml_sequence='', loop_length = 0.0,
                    task_name = ''):
        '''Convenience function for rendering an animation with Primary Sample Space GPT.'''
        
        render_parameters = copy.copy(render_parameters)
        reconstruct_parameters = copy.copy(reconstruct_parameters)

        if not task_name:
            task_name = getDefaultTaskName(scene, 'pss-gpt', spp, shutter_time, frame_count, render_parameters)
            
        spp //= 3
        
        if not 'method' in reconstruct_parameters:
            reconstruct_parameters['method'] = self.PSS_TGPT_ONLY_DX
        
        FRAME_TEMPLATE = task_name + '/frame%03d_seed%d'
        FRAME_X_TEMPLATE = task_name + '/frame%03d_seed%d_x'
        FRAME_Y_TEMPLATE = task_name + '/frame%03d_seed%d_y'
                    
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)

        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
                        
            # Render with seed i and seedshift(0,0) and store the results.
            render_parameters.update({'seed_xoffset' : 0, 'seed_yoffset' : 0})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )

            #render with seed i and seedshift (-1,0)
            render_parameters.update({'seed_xoffset' : -1, 'seed_yoffset' : 0})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_X_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
            #render with seed i and seedshift(0,-1)
            render_parameters.update({'seed_xoffset' : 0, 'seed_yoffset' : -1})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_Y_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
        
        # Queue reconstruction.
        reconstruct_parameters['frame_template'] = FRAME_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'pss-gpt-dx',
            parameters = reconstruct_parameters
        )
        
    def queueDtOnlyFull(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                        render_parameters = {}, reconstruct_parameters = {},
                        seed_increment = 1, xml_sequence='', loop_length = 0.0,
                        task_name = ''):
        '''Convenience function for rendering with temporal graidents only. Can use motion vectors and adaptive sampling'''

        render_parameters = copy.copy(render_parameters)
        reconstruct_parameters = copy.copy(reconstruct_parameters)

        if not task_name:
            task_name = getDefaultTaskName(scene, 'dt-only-full', spp, shutter_time, frame_count, render_parameters)
        
        if not 'method' in reconstruct_parameters:
            reconstruct_parameters['method'] = self.TGPT_DDXT
                    
        FRAME_A_TEMPLATE = task_name + '/frame%03d_seed%d'
        FRAME_B_TEMPLATE = task_name + '/frame%03d_seed%d'
        
        #set all required params automatically
        render_parameters.update({'disableGradients' : True})
        render_parameters.update({'useAdaptive' : True})
        render_parameters.update({'useMotionVectors' : True})
        render_parameters.update({'samplingIterations' : 4})
        
        # If motion vectors are used, then the reconstruction must also use the motion vector settings.
        
        if render_parameters.get('useMotionVectors') == True:
            reconstruct_parameters['useMotionVectors'] = True
        
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)
        
        
        # For adaptive sampling or motion vector set-ups, some jobs depend on others. Hence we make 2 renderQueues
        # (but only if adaptive sampling or motion vectors are really used).
        primaryBatch = self.BATCH_INDEPENDENT
        secondaryBatch = self.BATCH_INDEPENDENT
        hasDependencies = False
        
        useAdaptive = render_parameters.get('useAdaptive');
        samplingIterations = render_parameters.get('samplingIterations');
        useMotionVectors = render_parameters.get('useMotionVectors');
        
        if (useAdaptive == True and samplingIterations > 1) or useMotionVectors == True:
            primaryBatch = self.BATCH_DEPENDENCY_TARGET
            secondaryBatch = self.BATCH_DEPENDENT
            hasDependencies = True
        
        # Set block size.
        blocksize = 8 if useAdaptive else 32
        
        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
            
            #for frame 0 there is not previous frame, therefore frame000_seed0 can be rendered freely.
            currentBatch = secondaryBatch
            if i == 0 and hasDependencies:
                currentBatch = self.BATCH_INDEPENDENT
            
            # Render with seed i and store the results.
            if hasDependencies:
                if i == 0:
                    render_parameters.update({'isBase' : True})
                    render_parameters.update({'isTimeOffset' : False})
                else:
                    render_parameters.update({'isBase' : False})
                    render_parameters.update({'isTimeOffset' : True})
            
            self.queueRender(
                scene = scene,
                outdir = FRAME_A_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'gpt',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                batch = currentBatch,
                task = task_name,
                frame_time = frame_time,
                blocksize = blocksize,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
            current_seed += seed_increment
            
            if hasDependencies:
                render_parameters.update({'isBase' : True})
                render_parameters.update({'isTimeOffset' : False})
            
            # Render with seed i+1 and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_B_TEMPLATE % (i, i+1),
                seed = current_seed,
                integrator = 'gpt',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                batch = primaryBatch,
                task = task_name,
                frame_time = frame_time,
                blocksize = blocksize,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
        
        # Queue reconstruction.
        reconstruct_parameters['frameA_template'] = FRAME_A_TEMPLATE
        reconstruct_parameters['frameB_template'] = FRAME_B_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'dt-only-full',
            parameters = reconstruct_parameters
        )

    
    def queuePssTgptDt(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                       render_parameters = {}, reconstruct_parameters = {},
                       seed_increment = 1, xml_sequence='', loop_length = 0.0,
                       task_name = ''):
        '''Convenience function for rendering an animation with Primary Sample Space TGPT without spatial shifts.'''
        
        render_parameters = copy.copy(render_parameters)
        reconstruct_parameters = copy.copy(reconstruct_parameters)

        if not task_name:
            task_name = getDefaultTaskName(scene, 'pss-tgpt-only-dt', spp, shutter_time, frame_count, render_parameters)
            
        spp //= 2
        
        if not 'method' in reconstruct_parameters:
            reconstruct_parameters['method'] = self.PSS_TGPT_ONLY_DT
        
        FRAME_A_TEMPLATE = task_name + '/frame%03d_seed%d'
        FRAME_B_TEMPLATE = task_name + '/frame%03d_seed%d'
                    
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)

        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
                        
            # Render with seed i and seedshift(0,0) and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_A_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
            #increment seed !
            current_seed += seed_increment
            
            # Render with seed i+1 and seedshift (0,0) and store the results.           
            self.queueRender(
                scene = scene,
                outdir = FRAME_B_TEMPLATE % (i, i+1),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
            
        
        # Queue reconstruction.
        reconstruct_parameters['frameA_template'] = FRAME_A_TEMPLATE
        reconstruct_parameters['frameB_template'] = FRAME_B_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'pss-tgpt-dt',
            parameters = reconstruct_parameters
        )
    
    def queueGPT(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                 render_parameters = {}, reconstruct_parameters = {},
                 seed_increment = 1, xml_sequence='', loop_length = 0.0,
                 task_name = ''):
        '''Convenience function for rendering for an animation with G-PT.'''
        if not task_name:
            task_name = getDefaultTaskName(scene, 'gpt', spp, shutter_time, frame_count, render_parameters)

        FRAME_TEMPLATE = task_name + '/frame%03d_seed%d'
        
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)
        
        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
            
            # Render with seed i and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'gpt',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )

        # Queue reconstruction.
        reconstruct_parameters['frame_template'] = FRAME_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'gpt',
            parameters = reconstruct_parameters
        )

    def queueAdaptiveGPT(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                         render_parameters = {}, reconstruct_parameters = {},
                         seed_increment = 1, xml_sequence='', loop_length = 0.0,
                         task_name = ''):
        '''Convenience function for rendering for an animation with adaptive GPT.'''
        render_parameters = copy.copy(render_parameters)
        reconstruct_parameters = copy.copy(reconstruct_parameters)

        if not task_name:
            task_name = getDefaultTaskName(scene, 'gpt-adaptive', spp, shutter_time, frame_count, render_parameters)

        FRAME_TEMPLATE = task_name + '/frame%03d_seed%d'
        
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)
        
        if 'useAdaptive' not in render_parameters:
            render_parameters['useAdaptive'] = True
        if 'samplingIterations' not in render_parameters:
            render_parameters['samplingIterations'] = 4
        if 'isBase' not in render_parameters:
            render_parameters['isBase'] = True
        if 'isTimeOffset' not in render_parameters:
            render_parameters['isTimeOffset'] = False
        
        
        # Set block size.
        blocksize = 8
        
        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
            
            # Render with seed i and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'gpt',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                blocksize = blocksize,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )

        # Queue reconstruction.
        reconstruct_parameters['frame_template'] = FRAME_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'gpt-adaptive',
            parameters = reconstruct_parameters
        )
        
    def queueAdaptivePath(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                          render_parameters = {}, reconstruct_parameters = {},
                          seed_increment = 1, xml_sequence='', loop_length = 0.0,
                          task_name = ''):
        '''Convenience function for rendering for an animation with adaptive PT.'''
        render_parameters = copy.copy(render_parameters)
        reconstruct_parameters = copy.copy(reconstruct_parameters)

        if not task_name:
            task_name = getDefaultTaskName(scene, 'path-adaptive', spp, shutter_time, frame_count, render_parameters)

        FRAME_TEMPLATE = task_name + '/frame%03d_seed%d'
        
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)
        
        if 'disableGradients' not in render_parameters:
            render_parameters['disableGradients'] = True
        if 'useAdaptive' not in render_parameters:
            render_parameters['useAdaptive'] = True
        if 'samplingIterations' not in render_parameters:
            render_parameters['samplingIterations'] = 4
        if 'isBase' not in render_parameters:
            render_parameters['isBase'] = True
        if 'isTimeOffset' not in render_parameters:
            render_parameters['isTimeOffset'] = False
        
        
        # Set block size.
        blocksize = 8
        
        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
            
            # Render with seed i and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'gpt',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                blocksize = blocksize,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )

        # Queue reconstruction.
        reconstruct_parameters['frame_template'] = FRAME_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'path-adaptive',
            parameters = reconstruct_parameters
        )
                
    def queuePath(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                  render_parameters = {}, reconstruct_parameters = {},
                  seed_increment = 1, xml_sequence='', loop_length = 0.0,
                  task_name = ''):
        '''Convenience function for rendering for an animation with path tracing.'''
        if not task_name:
            task_name = getDefaultTaskName(scene, 'path', spp, shutter_time, frame_count, render_parameters)

        
        FRAME_TEMPLATE = task_name + '/frame%03d_seed%d'
        
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)
        
        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = (frame + i) * frame_time
            current_seed = seed + i * seed_increment
            
            # Render with seed i and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )

        # Queue reconstruction.
        reconstruct_parameters['frame_template'] = FRAME_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'path',
            parameters = reconstruct_parameters
        )
        
    def queueAverage(self, scene, seed, spp, frame_time, shutter_time, frame_count, frame = 0,
                     render_parameters = {}, reconstruct_parameters = {},
                     seed_increment = 1, xml_sequence='', loop_length = 0.0,
                     task_name = ''):
        '''Convenience function for rendering for an animation with Temporal GPT.'''
        if not task_name:
            task_name = getDefaultTaskName(scene, 'average', spp, shutter_time, frame_count, render_parameters)
        
        FRAME_TEMPLATE = task_name + '/frame%03d_seed%d'
        
        reconstruct_parameters = setDefaultParameters(reconstruct_parameters)
        
        # Queue frames to be rendered.
        for i in range(frame_count):
            current_time = frame * frame_time
            current_seed = seed + i * seed_increment
            
            # Render with seed i and store the results.
            self.queueRender(
                scene = scene,
                outdir = FRAME_TEMPLATE % (i, i),
                seed = current_seed,
                integrator = 'path',
                spp = spp,
                frame_start_time = current_time,
                shutter_time = shutter_time,
                task = task_name,
                frame_time = frame_time,
                xml_sequence = xml_sequence,
                custom = render_parameters,
                loop_length = loop_length
            )
                
        # Queue reconstruction.
        reconstruct_parameters['frame_template'] = FRAME_TEMPLATE
        
        self.queueReconstruct(
            task = task_name,
            cluster_task = task_name,
            scene = scene,
            frames = (0, frame_count - 1),
            method = 'average',
            parameters = reconstruct_parameters
        )
    
    def close(self):
        '''Closes all files and shuts down the generator.'''
        for batch in self.batches:
            batch.close()
        
        print('Generated config "{}".'.format(self.config_name))
        