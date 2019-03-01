Temporal Gradient-Domain Path Tracing
-------------------------------------
  This code extends Mitsuba 0.5.0 and implements the algorithm presented
  in paper "Temporal Gradient-Domain Path Tracing" (T-GPT) by Manzi and
  Kettunen et al.
  
  The implementation is based on Gradient-Domain Path Tracing (GPT)
  [Kettunen et al. 2015] and extends it by adaptive sampling and
  evaluating color differences of corresponding pixels also between adjacent
  frames. The pixel correspondences are defined by tracking object movement
  between frames via motion vectors. Note that there is no support yet
  for a temporal extension of Gradient-Domain Bidirectional Path Tracing
  [Manzi et al. 2015].
  
  T-GPT first evaluates differences between adjacent pixels of an
  animation in a spatio-temporal box of pixels, and then combines these
  spatio-temporal gradients with the standard color estimates by solving
  for the animation sequence that best matches the sampled data.
  
  These pixel differences are evaluated in a manner that often results in
  much less noise than standard sampling. This often leads to a significant
  reduction in noise and flickering in the final animation sequence,
  compared to equal time standard sampling.
  
  The algorithm uses the same path sampling machinery as Gradient-Domain
  Path Tracing, but complements it with machinery for evaluating differences
  between adjacent frames, while only requiring the data of one frame in
  memory at a time. This is implemented as a so-called “primary sample
  space shift” by rendering each frame of the animation twice, but with
  half the samples each. One of the frames shares its random numbers with
  the previous frame, and the other with the next frame. The temporal
  differences are acquired by subtracting the adjacent frames that are
  rendered with the same random numbers from each other. We provide a Matlab
  script that computes these differences that are then used for solving for
  the final animation sequence once the data from all frames is available.
  
  Neither T-GPT or GPT change the importance sampling distribution of the
  unidirectional path tracer. Thus, these methods are no magical fix for
  cases when the unidirectional sampler does not work efficiently. However,
  as we demonstrate in the paper, assuming that you have an animation for
  which the basic method works, using temporal gradient-domain rendering
  often saves very much time.
  
  The L2 reconstruction without adaptive sampling is unbiased, and the
  adaptive sampling could easily be made unbiased at the cost of some
  visual quality. We recommend using L1 reconstruction and the adaptive
  sampling implementation as they are, as they produce visually more
  pleasing results and the bias tends to go away rather quickly.
  
  
  Project home page:
  http://cgg.unibe.ch/publications/temporal-gradient-domain-path-tracing
  
  
  In case of problems/questions/comments don't hesitate to
  contact us directly: markus(dot)kettunen(at)aalto(dot)fi or
  m(dot)manzi1386(at)gmail(dot)com.


About the Implementation:
-------------------------
  This implementation builds on the GPT implementation at
  https://mediatech.aalto.fi/publications/graphics/GPT/. While GPT supports
  low-discrepancy sequences, this implementation of T-GPT relies on the
  proof-of-concept “deterministic sampler” for evaluating temporal
  differences. It uses replayable uniform random numbers with a different
  seed for each pixel and sample index. It should be easy to modify a
  low-discrepancy sequence to provide similar per-pixel replayability.
  
  We also extend GPT / T-GPT by the option to use adaptive sampling based
  on the sampling variance of the spatial gradients. In the current code,
  both GPT and T-GPT have the option to use adaptive sampling. The user
  can specify how many sampling iterations the total sample budget should
  be distributed over. After each sampling iteration, all sampling data
  gathered so far is used to estimate the variance of the spatial gradients
  to compute a sampling map for the next sampling iteration. The first
  iteration does uniform sampling. We recommend using 4 to 8 sampling
  iterations for a good trade-off between speed and adaptivity.
  
  Once the individual frames of an animation sequence have been rendered,
  we combine the outputs from the individual renders into a sequence of
  dx, dy, dt and primal images in a Matlab script. We reconstruct the
  final animation sequence by solving a 3D screened Poisson equation with
  overlapping windows, and smoothly blend between the reconstructed windows
  to produce the final animation sequence. The reconstruction is done in
  CUDA by default, but we fall back to a CPU solver when CUDA support is
  not detected.
  
  The code was implemented and tested using Visual C++ 2013 (with update 4)
  and CUDA Toolkit 7.5.
  
  T-GPT is supposed to be used through the provided rendering scripts
  as described in section Usage, and currently requires Python and Matlab
  for coordinating the reconstruction.
  
  We recommend rendering the individual frames in a supercomputer
  environment as rendering lots of frames tends to be rather time
  consuming. We provide a simple example framework for configuring batch
  runs with different methods, executing them remotely, and finally
  reconstructing them locally on a GPU so that all data is easily
  accessible. We provide example job launcher scripts for workload
  management systems Slurm and Sun Grid Engine, and you may need to
  adapt these for your environment. We also provide a simple script for
  executing the renders locally, but we only recommend this for testing
  and debugging.
  
  
  The integrator implementations are released under the same license as
  the rest of Mitsuba. The original screened Poisson reconstruction code
  from NVIDIA is under the new BSD license and has been modified for the
  temporal reconstruction used in T-GPT. See the source code for details.
  
  
  Note that when running in the GUI, the implementation will run GPT,
  not T-GPT.
  
  
(Required) Installation (Local, Windows):
-----------------------------------------
  - Acquire Matlab (used for combining renders for reconstruction).
  - Acquire Python 3.1 or later (used for generating batch job
  configurations).
  - Acquire ffmpeg.exe (used for generating animations). The recommended
  way is by installing WinFF. The expected path for ffmpeg.exe is
  ‘c:\program files\winff\ffmpeg.exe’. If you change this you need to
  update ‘bin/makevideos.py’ and ‘bin/makevideos_loop.py’.
  - Configure the reconstruction to use a valid temporary directory: Change
  the variable TEMP_DIRECTORY in ‘matlab/reconstruct_impl.m’ to point
  somewhere with fast read and write operations, preferably an SSD drive.
  
  
(Optional) Remote Installation on a Supercomputer:
--------------------------------------------------
  Supercomputer environments can be tricky. They often feature some kind of
  a packet library that you can use, but often things are still complicated
  and you will need to install libraries locally. When this happens you may
  need to edit config files manually to tell Mitsuba where to find them.
  
  It may be a good idea to first make sure you can compile standard
  Mitsuba 0.5.0 without any modifications. Some problems will probably
  arise, and some of the tips below may help.
  
  This is our guideline for building T-GPT on a supercomputer:
  
  - Acquire Python 2.7, scons and any libraries required by Mitsuba.
  
  - Clone T-GPT from git.
  
  - Disable the GUI by commenting out the following lines:
      File ‘SConstruct’:
          build('src/mtsgui/SConscript', ['mainEnv', ...
      File ‘build/SConscript.install’:
          if hasQt:
              install(distDir, ['mtsgui/mtsgui'])
  
  - Copy a suitable configuration script from ‘build/’.
        Example: cp build/config-linux-gcc.py config.py
  
  - Modify ‘config.py’ as follows:
      - Line ‘CXXFLAGS = ...’:
          - Add '-std=c++11',
                '-Wno-unused-local-typedefs',
                '-DDOUBLE_PRECISION'.
          - Remove '-DSINGLE_PRECISION',
                   '-DMTS_SSE',
                   '-DMTS_HAS_COHERENT_RT'.
      - Configure and add in any missing INCLUDE and LIBDIR directories.
          - Example: XERCESINCLUDE = ['/path/to/xerces/include']
                     XERCESLIBDIR = ['/path/to/xerces/lib'].
          - Pay extra attention to BOOSTINCLUDE, BOOSTLIBDIR and Boost version.
            Version 1.54 should work.
          - See Mitsuba documentation for details.
  
  - Compile with ‘scons’.
        Example: scons
  
  - If compilation fails, see file ‘config.log’.
  
  If all goes well, proceed with the installation by copying the build
  result from ‘dist/’ to ‘cluster/dist/’ inside the framework
  directory.
  
  Finally, you need to adapt the provided run scripts ‘run_slurm.py’
  (for Slurm) and ‘run_sge.py’ (for Sun Grid Engine) for your
  environment. In most cases you should only need to modify the function
  ‘runBatch’ which feeds the rendering tasks to the supercomputer’s
  workload management system.
  
  Note that reconstructions in Mitsuba are currently enabled in code only
  for Windows platforms.
  
  
Usage:
------
  A Windows build of Mitsuba with non-temporal GPT and adaptive sampling
  can be found in ‘RenderFramework/cluster/dist/’. This executable
  cannot be used directly for Temporal Gradient-Domain Path Tracing. This
  implementation of T-GPT is designed to be used through a simple framework
  designed for easy rendering of animations on a supercomputer environment,
  but it can also be used locally.
  
  To render tasks on a supercomputer, be sure to first compile Mitsuba
  with T-GPT. See ‘Remote Installation on a Supercomputer’ for details.
  
  To render an animation, first a render task is written into directory
  ‘RenderFramework/configs/’, and it is a simple Python call to a
  generator object. 
  
  Example config:
      # Render Crytek Sponza animation with T-GPT.
      gen.queueTGPT(
          scene = 'crytek_sponza',
          seed = 0,
          spp = 128,
          frame_time = 1.0,
          shutter_time = 0.5,
          frame_count = 240
      )
  
  The batch configurations are located in folder ‘configs/’. They
  define what to render, how, and what kind of reconstruction to use. See
  the example configuration ‘configs/generate_crytek_sponza.py’ and
  the files in ‘configs/crytek_sponza/’ for examples.
  
  Warning: Do not change the value of frame_time as some parts of the
  code were not updated to support other values.
  
  Run your batch configuration script with Python 3.1 or later.
      Example: python generate_crytek_sponza.py my_batch
  
  This will create configuration files into ‘cluster/configs/’ with
  the name ‘my_batch’. The batch name can be omitted, in which case
  ‘default’ will be used. These configuration files are used by the
  supercomputer for launching the render tasks.
  
  If rendering remotely, sync the ‘cluster/configs/’ directory to
  the remote computer. (Hint: If this needs to be done repeatedly, the
  ‘rsync’ application may be of help.)
  
  Pick the most closely matching run script in ‘cluster/’ and configure
  it for your environment on the computer doing the renderign. When ready,
  add the suitable parameters for your environment launch the run script.
      Example (local): python run_windows.py my_batch
      Example (remote): python run_slurm.py my_batch -p short -t 4
  
  If the batch name is omitted then batch name ‘default’ is used.
  
  These run scripts send the individual render jobs to the
  supercomputer’s workload management system. The run scripts may benefit
  from some flags related to the workload management on your supercomputer
  such as maximum render time, queueing partition or memory required. Run
  the scripts with command line parameter ‘--help’ for help. The
  Windows script is simpler and just runs the renders sequentially. 
  
  You can change the number of threads the renders are done by changing
  the variables 
  
  When the renderings have finished, sync the results to your local
  computer. The results are located in ‘cluster/results/’; sync these
  to the local directory ‘cluster/results/’.
  
  Next, run the reconstruction script ‘matlab/run_update.m’ on the
  local computer. This will do the following:
  
  - Read the batch configuration files ‘config.cfg’ under
  ‘results/’ and see which tasks need to be reconstructed
  based on timestamps in the result folders ‘results/’ and
  ‘cluster/results/’.
  
  - Combine the rendering outputs so that they can be fed to the Poisson
  reconstruction tool.
  
  - Run the reconstruction using ‘bin/tpoisson.exe’.
  
  - Convert the final images to PNG.
  
  - Construct animations from the PNGs to be placed into
  ‘results/_aaa_videos’ by using ‘bin/makevideos.py’.
  
  - If so desired, it can also calculate the relative mean square error
  (RelMSE) of a single frame of the animation against a reference frame. See
  ‘Outputting Single Frame Relative MSE’ below.
  
  To remove render tasks from being processed by ‘matlab/run_update.m’,
  delete their folders in ‘RenderFramework/results/scene_name/’.
  
  Note: The data combining and GPU reconstruction tasks may be parallelized
  by enabling the parfor on run_update.m:185. Note that this will make
  debugging any failure cases, such as the supercomputer’s workload
  management system killing a render job, much harder.
  
  
(Optional) Configuring New Scenes:
----------------------------------
  Configuring existing scenes for the rendering framework requires a
  specific setting for the scenes.
  
  The scene directory should be copied under ‘cluster/scenes/’ under a
  unique name. Rename your scene’s .xml file into name ‘batch.xml’ and
  copy the following configuration there from an existing ‘batch.xml’,
  replacing existing definitions when it makes sense:
    - The section DEFAULT PARAMETERS in the beginning.
    - The <integrator> specification.
    - The “shutterOpen” and “shutterClose” properties of the sensor.
    - The <sampler> definition inside <sensor>.
    - The <film> definition.
  
  Continue by creating the corresponding render configuration scripts
  under ‘configs/’. Use the existing scripts as examples and see
  section ‘Usage’ for details.
  
  Note: The directory of the scene under ‘cluster/scenes/’ should
  correspond to the folder in ‘configs/’ if automatic single frame
  RelMSE calculation is used.
  
  
(Optional) Building Mitsuba with T-GPT on Windows:
--------------------------------------------------
  Begin by installing CUDA toolkit (at least version 6.5) if you don’t
  have it yet. Copy the static CUDA runtime library ‘cudart_static.lib’
  from ‘NVIDIA GPU Computing Toolkit/CUDA/vx.y/lib/x64’ into folder
  ‘mitsuba/dependencies/lib/x64_vc12’.
  
  Download the dependencies package from the Mitsuba Repository
  https://www.mitsuba-renderer.org/repos/ and merge its contents into
  'mitsuba/dependencies/'.
  
  Install Python 2.7 and Scons. Scons requires 32 bit Python 2.7. Newer
  versions do not work with scons. Add the python27 directory and
  python27/script directory into VC++ directories / executable directories
  in Visual Studio. Also install Pywin32.
  
  Now you should be able to compile Mitsuba with Visual C++ 2013 or
  above. When done, install the build into the rendering framework by
  copying the contents of your ‘dist/’ folder into ‘cluster/dist/’
  inside the framework.
  
  
(Optional) Outputting Single Frame Relative MSE:
------------------------------------------------
  Relative mean square error (RelMSE) is an often used metric for
  evaluating the remaining noise in renders. It outputs a measure of error
  (lower is better) by comparing a rendering result to an independently
  rendered near-perfect reference.
  
  Since the reference needs lots of samples, it takes a very long
  time to render. Rendering a reference for every frame of even a short
  animation sequence would multiply the cost by hundreds, making it often
  prohibitively expensive. As such, we implemented support for calculating
  the RelMSE for a single frame of an animation.
  
  Note, however, that RelMSE for a single frame tells nothing about
  a rendering algorithm’s temporal behavior which is essential
  for real world use, so it is not a very useful metric for studying
  animations. Still, this information could sometimes be interesting.
  
  To make the reconstruction script ‘matlab/run_update.m’
  evaluate single frame RelMSE, render the reference frame using the
  ‘gen.queueAverage’ function in the configuration scripts. See
  ‘configs/crytek_sponza/batch_reference_frame.py’ for an example.
  
  Next, create file ‘config_single_frame_relmse.cfg’ into
  folder ‘configs/scene_name’. The first line must be the
  directory of the reference render in ‘results/’. The second
  line must be the frame number of the previous reference render. See
  ‘configs/crytek_sponza/config_single_frame_relmse.cfg’ for an
  example.
  
  Note that the folder ‘configs/scene_name/’ above must correspond
  to the scene parameter passed to ‘gen’ in the configuration scripts.
  
  Single frame RelMSE estimation can be disabled by deleting
  the config file. The relative MSEs are outputted into directory
  ‘results/_aaa_single_frame_relmse/’.
  
  
(Optional) Using the Reconstruction Code as Stand-Alone:
--------------------------------------------------------
  In the usual scenario the Poisson reconstruction (bin/tpoisson.exe)
  is called directly from the Matlab scripts with appropriate parameters
  to reconstruct the animation. However, the reconstruction can also be
  run directly from command line. 
  
  Run ‘bin/tpoisson.exe -h’ for the list of supported command line
  parameters.
  
  Here is an example on how to run a reconstruction:
      Example: bin/tpoisson.exe -dx results/img-dx.pfm -alpha 0.2
                                -nframes 10 -time -ddxt -mv
  
  Currently only PFM images are accepted as input. Also make sure that
  the naming convention of your files is the same as when they are created
  by the Matlab scripts.
  
  Please be aware that reconstructing very many frames at once (the
  ‘-nframes’ parameter) may make the reconstruction run out of
  memory. The memory usage increases linearly with the number of frames
  to be reconstructed. If the reconstruction crashes, it is most likely
  because not enough memory was available. The solution is to reconstruct
  the sequence in several overlapping batches of frames like recommended
  in the paper.
  
  
Troubleshooting:
----------------
  In case of the following error message while building Mitsuba:
  
  ‘Could not compile a simple C++ fragment, verify that cl is
  installed! This could also mean that the Boost libraries are missing. The
  file "config.log" should contain more information',
  
  make sure you installed the static CUDA runtime library
  ‘cudart_static.lib’ and other dependencies like instructed in chapter
  ‘Building Mitsuba with T-GPT on Windows’.
  
  
  If this doesn’t help, try bypassing the test in
  build/SConscript.configure by changing
        137: conf = Configure(env, custom_tests = { 'CheckCXX' : CheckCXX })
            to
        137: conf = Configure(env).
  The error messages produced by the compiler afterwards could be more
  informative.
  
  
  Make sure that the config.py files use DOUBLE_PRECISON flag instead of
  SINGLE_PRECISION since gradient-rendering in the current form is sensitive
  to the used precision. This will hopefully be fixed at a later time.
  
  
  To create a documentation with doxygen run the gendoc.py script in
  mitsuba/doc. If this fails it might be because some packages of LaTeX
  are missing (especially mathtools).
  
  [With MiKTeX, install them with the package manager admin tool. In
  Windows this can be found in MiKTeX\miktex\bin\mpm_mfc_admin.]
  
  
  In case of problems, remove database files like .sconsign.dblite,
  .sconf_temp and everything in build/Release and build/Debug.
  
  
  If render tasks finish on a supercomputer suspiciously
  fast or produces no output, see the outputs in directory
  ‘cluster/results/task_name/’. See for example the file
  ‘info_commandline.txt’ and try to run the task manually on the login
  node.
  
  Also try to run the task manually using ‘task_run.py’. See
  ‘--help’ for details. The config name passed to it is typically
  e.g. ‘my_batch__0’, ‘my_batch__1’ or ‘my_batch__2’, depending
  on which parts of a task you want to render. ‘__0’ is for tasks that
  other tasks depend on, ‘__1’ is for independent tasks and ‘__2’
  is for tasks with dependencies.
  
  
  We noticed that if we let OpenMP use all CPU cores for the Poisson
  reconstruction, OpenMP may end being slower than a single core
  reconstruction. We suspect this to be caused by hyper threading. We
  recommend configuring OpenMP to only use as many threads as there are
  physical cores.
  
  
Notes:
------
  When running G-PT in the GUI, what is displayed during rendering is
  only the sampled color data. Reconstruction of the final image is done
  only after the color and gradient buffers have been sampled.
  
  This codebase does NOT support gradient-domain bidirectional path tracing
  (G-BDPT)!
  
  This implementation does not yet support the 'hide emitters' option in
  Mitsuba, even though it is displayed in the GUI!
  
  Measuring rendering time on supercomputers is extremely unreliable. We
  thus recommend doing rendering time experiments locally. Some
  supercomputer environments seem to aggressively reallocate batch jobs’
  CPU resources to other processes.
  
  We recommend using quite small rendering block sizes when adaptive
  sampling is used since the costs of the render blocks may sometimes be
  very uneven.
  
  While our modification of Mitsuba should run on Linux (without GUI),
  the reconstruction tool is not designed to be run on Linux.
  
  
Change log:
-----------
  2019/03/01: Fix a bug in the environment map shift.
  2017/11/27: Add note that Python 3.1 or later is required.
              Change default temporary directory from D drive to C.
  2017/11/24: Initial release.
  
  
License Information:
--------------------
  All source code files contain their licensing information.
  
  Most notably, unlike Mitsuba code, the screened Poisson reconstruction
  code is NOT covered by GNU GPL 3, but the following license:


  Copyright (c) 2016, Marco Manzi and Markus Kettunen. All rights reserved.
  Copyright (c) 2015, NVIDIA CORPORATION. All rights reserved.


  Redistribution and use in source and binary forms, with or without
  modification, are permitted provided that the following conditions are met:
     *  Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.
     *  Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.
     *  Neither the name of the NVIDIA CORPORATION nor the
        names of its contributors may be used to endorse or promote products
        derived from this software without specific prior written permission.


  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
  DISCLAIMED. IN NO EVENT SHALL NVIDIA CORPORATION BE LIABLE FOR ANY
  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


  The scene "Crytek Sponza" is courtesy of Frank Meinl, Crytek,
  and ported to Mitsuba renderer by McGuire [1].


  [1] McGuire, Computer Graphics Archive, Aug 2011
      (http://graphics.cs.williams.edu/data)
