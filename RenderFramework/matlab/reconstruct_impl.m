function reconstruct_impl(scene_name, task_name, frame_range, reconstruction_method, in_dir, out_dir, parameters, need_combine, need_reconstruct)

addpath('exr')


% Operations to do.
COMBINE = need_combine;
RECONSTRUCT = need_reconstruct;

% Reconstruction window length.
WINDOW_LENGTH = 10;

% How to weight frames in a window.
%weightFunction = @(x, center, length) max(0.0, 1.0 - 2.0 * abs((x - center) / length));     % Triangle
weightFunction = @(x, center, length) 0.5 * (1 + cos(pi * (2.0 * (x - center) / length)));  % Hann


% Full identifier of the task.
task_path = sprintf('%s/%s', scene_name, task_name);


% Read parameters.
RECONSTRUCTION_TYPE = reconstruction_method;
FRAMES = frame_range;
IN_DIR = in_dir;
OUT_DIR = sprintf('%s/%s', out_dir, task_path);
VIDEO_OUT_DIR = sprintf('%s/_aaa_videos', out_dir);


TEMP_DIRECTORY = 'C:\tmp-delete-me';

RECONSTRUCT_L1 = '..\bin\tpoisson.exe';
RECONSTRUCT_L2 = '..\bin\tpoisson.exe';
PFM2PNG = '..\bin\pfm2png_mitsuba.exe';

MAKE_VIDEOS = '..\bin\makevideos.py';
MAKE_VIDEOS_LOOP = '..\bin\makevideos_loop.py';

VIDEO_TYPE = 'loop';
if isfield(parameters, 'video')
    VIDEO_TYPE = parameters.video;
end

USE_MOTION_VECTORS = parameters.useMotionVectors;
USE_DX = true;
USE_DDXX = false;
USE_DDXY = false;
USE_DDXT = false;
USE_TIME = false;
USE_L1 = false;
USE_L2 = false;
    
% Read reconstruction parameters.
if strcmp(RECONSTRUCTION_TYPE, 'gpt-gpt')
    FRAME_A_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameA_template);
    FRAME_B_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameB_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
    USE_TIME = true;
elseif strcmp(RECONSTRUCTION_TYPE, 'gpt-notime')
    FRAME_A_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameA_template);
    FRAME_B_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameB_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
elseif strcmp(RECONSTRUCTION_TYPE, 'tgpt-ddxt')
    FRAME_A_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameA_template);
    FRAME_B_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameB_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
    USE_TIME = true;
	USE_DDXT = true;
elseif strcmp(RECONSTRUCTION_TYPE, 'gpt')
    FRAME_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frame_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
elseif strcmp(RECONSTRUCTION_TYPE, 'gpt-adaptive')
    FRAME_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frame_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
elseif strcmp(RECONSTRUCTION_TYPE, 'pss-tgpt-dx-dt')
    FRAME_A_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameA_template);
    FRAME_B_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameB_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
    use_time = true;
elseif strcmp(RECONSTRUCTION_TYPE, 'pss-gpt-dx')
    FRAME_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frame_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
elseif strcmp(RECONSTRUCTION_TYPE, 'pss-tgpt-dt')
    FRAME_A_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameA_template);
    FRAME_B_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frameB_template);
    USE_L1 = parameters.use_l1;
    USE_L2 = parameters.use_l2;
    USE_DX = false;
    USE_TIME = true;
elseif strcmp(RECONSTRUCTION_TYPE, 'path')
    FRAME_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frame_template);
elseif strcmp(RECONSTRUCTION_TYPE, 'path-adaptive')
    FRAME_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frame_template);
elseif strcmp(RECONSTRUCTION_TYPE, 'average')
    FRAME_TEMPLATE = sprintf('%s/%s', IN_DIR, parameters.frame_template);
else
    error(sprintf('Unknown reconstruction type "%s".', RECONSTRUCTION_TYPE));
end


% Reconstruct.

function combine_GPT_GPT_DDXT(index, USE_MOTION_VECTORS)
   % input0a_directory = sprintf(FRAME_A_TEMPLATE, index - 1, index - 1);
   
    EXR_OUT = false;
    %frame{i-1}_seed{i} aka "base pass"
    input0b_directory = sprintf(FRAME_B_TEMPLATE, index - 1, index);
    %frame{i}_seed{i} aka "time-offset pass"
    input1a_directory = sprintf(FRAME_A_TEMPLATE, index, index);
    %frame{i}_seed{i+1} aka. next frames' base pass
    input1b_directory = sprintf(FRAME_B_TEMPLATE, index, index + 1);
    
    % store sampling maps
    %sm = exrread(sprintf('%s/image-spp.exr', input1b_directory));
    %write_pfm(sm, sprintf('%s/image-spp_%d.pfm', OUT_DIR, index), true);
    %if EXR_OUT
    %   exrwrite( sm, sprintf('%s/image-spp_%d.exr', OUT_DIR, index));
    %end
      
    % Copy motion vectors
    if USE_MOTION_VECTORS && index >= 1
        mvF = exrread(sprintf('%s/image-motion.exr', input0b_directory));
        mvB = exrread(sprintf('%s/image-motion-inv.exr', input0b_directory));
        write_pfm( mvF, sprintf('%s/image-motion_%d.pfm', OUT_DIR, index-1), true);
        write_pfm( mvB, sprintf('%s/image-motion-inv_%d.pfm', OUT_DIR, index-1), true);
        if EXR_OUT
            exrwrite( mvF, sprintf('%s/image-motion_%d.exr', OUT_DIR, index-1));
            exrwrite( mvB, sprintf('%s/image-motion-inv_%d.exr', OUT_DIR, index-1));
        end
    
        % Create motion map for Matlab.
        [ysize, xsize, n] = size(mvB);
        motionX = mvB(:, :, 1);
        motionX = motionX(:);
        motionY = mvB(:, :, 2);
        motionY = motionY(:);
        
        motionMask = abs(motionX) < 10000.0;
        motionIndex = (1 : (xsize * ysize))' + motionY + motionX * ysize;
    end
    
    % Combine dx.
    dx1a = exrread(sprintf('%s/image-dx.exr', input1a_directory));
    dx1b = exrread(sprintf('%s/image-dx.exr', input1b_directory));
    if ~USE_MOTION_VECTORS || index == 0
        dx = 0.5 * (dx1a + dx1b);
    else
        dx = motionAwareCombine(dx1b, dx1a, motionIndex, motionMask);
    end
    write_pfm(dx, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
    if EXR_OUT
        exrwrite(dx, sprintf('%s/image-dx_%d.exr', OUT_DIR, index));
    end
    
    
    % Combine dy.
    dy1a = exrread(sprintf('%s/image-dy.exr', input1a_directory));
    dy1b = exrread(sprintf('%s/image-dy.exr', input1b_directory));
    if ~USE_MOTION_VECTORS || index == 0
        dy = 0.5 * (dy1a + dy1b);
    else
        dy = motionAwareCombine(dy1b, dy1a, motionIndex, motionMask);
    end
    write_pfm(dy, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);
    if EXR_OUT
       exrwrite(dy, sprintf('%s/image-dy_%d.exr', OUT_DIR, index));
    end
    
    % Calculate dt for previous frame.
    t1a = exrread(sprintf('%s/image-primal.exr', input1a_directory));
    d1a = exrread(sprintf('%s/image-direct.exr', input1a_directory));
    
    if index >= 1
        t0b = exrread(sprintf('%s/image-primal.exr', input0b_directory));
        d0b = exrread(sprintf('%s/image-direct.exr', input0b_directory));
        dt = (t1a + d1a) - (t0b + d0b);
        write_pfm(dt, sprintf('%s/image-dt_%d.pfm', OUT_DIR, index - 1), true);
        if EXR_OUT
            exrwrite(dt, sprintf('%s/image-dt_%d.exr', OUT_DIR, index - 1));
        end
    end
    
	% Calculate ddxt for previous frame.
    if index >= 1
        dx0b = exrread(sprintf('%s/image-dx.exr', input0b_directory));
        %dx1a = exrread(sprintf('%s/image-dx.exr', input1a_directory));
        ddxt = dx1a - dx0b;
        write_pfm(ddxt, sprintf('%s/image-ddxt_%d.pfm', OUT_DIR, index - 1), true);
        if EXR_OUT
            exrwrite(ddxt, sprintf('%s/image-ddxt_%d.exr', OUT_DIR, index - 1));
        end
    end

	% Calculate ddyt for previous frame.
    if index >= 1
        dy0b = exrread(sprintf('%s/image-dy.exr', input0b_directory));
        %dy1a = exrread(sprintf('%s/image-dy.exr', input1a_directory));
        ddyt = dy1a - dy0b;
        write_pfm(ddyt, sprintf('%s/image-ddyt_%d.pfm', OUT_DIR, index - 1), true);
        if EXR_OUT
            exrwrite(ddyt, sprintf('%s/image-ddyt_%d.exr', OUT_DIR, index - 1));
        end
    end
    
    % Combine throughputs and directs.
    if ~USE_MOTION_VECTORS || index == 0
        %t1a = exrread(sprintf('%s/image-primal.exr', input1a_directory));
        %d1a = exrread(sprintf('%s/image-direct.exr', input1a_directory));
        t1b = exrread(sprintf('%s/image-primal.exr', input1b_directory));
        d1b = exrread(sprintf('%s/image-direct.exr', input1b_directory));
        t = 0.5 * (t1a + d1a + t1b + d1b);
    else
        t1b = exrread(sprintf('%s/image-primal.exr', input1b_directory));
        d1b = exrread(sprintf('%s/image-direct.exr', input1b_directory));
        
        t = motionAwareCombine(t1b + d1b, t1a + d1a, motionIndex, motionMask);

        
        %t = t1b + d1b;
    end
    
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
    if EXR_OUT
        exrwrite(t, sprintf('%s/image-primal_%d.exr', OUT_DIR, index));
    end
end

function combine_DT_ONLY_FULL(index, USE_MOTION_VECTORS)
   % input0a_directory = sprintf(FRAME_A_TEMPLATE, index - 1, index - 1);
   
    EXR_OUT = false;
    %frame{i-1}_seed{i} aka "base pass"
    input0b_directory = sprintf(FRAME_B_TEMPLATE, index - 1, index);
    %frame{i}_seed{i} aka "time-offset pass"
    input1a_directory = sprintf(FRAME_A_TEMPLATE, index, index);
    %frame{i}_seed{i+1} aka. next frames' base pass
    input1b_directory = sprintf(FRAME_B_TEMPLATE, index, index + 1);
    
    % store sampling-maps
    %sm = exrread(sprintf('%s/image-spp.exr', input1b_directory));
    %write_pfm(sm, sprintf('%s/image-spp_%d.pfm', OUT_DIR, index), true);
    %if EXR_OUT
    %   exrwrite( sm, sprintf('%s/image-spp_%d.exr', OUT_DIR, index));
    %end
      
    % Copy motion vectors
    if USE_MOTION_VECTORS && index >= 1
        mvF = exrread(sprintf('%s/image-motion.exr', input0b_directory));
        mvB = exrread(sprintf('%s/image-motion-inv.exr', input0b_directory));
        write_pfm( mvF, sprintf('%s/image-motion_%d.pfm', OUT_DIR, index-1), true);
        write_pfm( mvB, sprintf('%s/image-motion-inv_%d.pfm', OUT_DIR, index-1), true);
        if EXR_OUT
            exrwrite( mvF, sprintf('%s/image-motion_%d.exr', OUT_DIR, index-1));
            exrwrite( mvB, sprintf('%s/image-motion-inv_%d.exr', OUT_DIR, index-1));
        end
		
		% Create motion map for Matlab.
        [ysize, xsize, n] = size(mvB);
        motionX = mvB(:, :, 1);
        motionX = motionX(:);
        motionY = mvB(:, :, 2);
        motionY = motionY(:);
        
        motionMask = abs(motionX) < 10000.0;
        motionIndex = (1 : (xsize * ysize))' + motionY + motionX * ysize;
    end
       

    
    % Calculate dt for previous frame.
    t1a = exrread(sprintf('%s/image-primal.exr', input1a_directory));
    d1a = exrread(sprintf('%s/image-direct.exr', input1a_directory));
    
   % Output zero derivatives as placeholders.
    ds = zeros(size(t1a));
    write_pfm(ds, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
    write_pfm(ds, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);
    
    if index >= 1
        t0b = exrread(sprintf('%s/image-primal.exr', input0b_directory));
        d0b = exrread(sprintf('%s/image-direct.exr', input0b_directory));
        dt = (t1a + d1a) - (t0b + d0b);
        write_pfm(dt, sprintf('%s/image-dt_%d.pfm', OUT_DIR, index - 1), true);
        if EXR_OUT
            exrwrite(dt, sprintf('%s/image-dt_%d.exr', OUT_DIR, index - 1));
        end
    end
    
    % Combine throughputs and directs.
    if ~USE_MOTION_VECTORS || index == 0
        %t1a = exrread(sprintf('%s/image-primal.exr', input1a_directory));
        %d1a = exrread(sprintf('%s/image-direct.exr', input1a_directory));
        t1b = exrread(sprintf('%s/image-primal.exr', input1b_directory));
        d1b = exrread(sprintf('%s/image-direct.exr', input1b_directory));
        t = 0.5 * (t1a + d1a + t1b + d1b);
    else
        t1b = exrread(sprintf('%s/image-primal.exr', input1b_directory));
        d1b = exrread(sprintf('%s/image-direct.exr', input1b_directory));
		
		t = motionAwareCombine(t1b + d1b, t1a + d1a, motionIndex, motionMask);
    end
    
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
    if EXR_OUT
        exrwrite(t, sprintf('%s/image-primal_%d.exr', OUT_DIR, index));
    end
end

% Recostruction setup for primary sample space TGPT.
function combine_PSS_TGPT_DX_DT(index)
    EXR_OUT = false; %enable for debugging

    input0b_directory = sprintf(FRAME_B_TEMPLATE, index - 1, index);
    input1a_directory = sprintf(FRAME_A_TEMPLATE, index, index);
    input1ax_directory = sprintf('%s_x',sprintf(FRAME_A_TEMPLATE, index, index));
    input1ay_directory = sprintf('%s_y',sprintf(FRAME_A_TEMPLATE, index, index));
    input1b_directory = sprintf(FRAME_B_TEMPLATE, index, index + 1);

    % Read source data.
    t1a = exrread(sprintf('%s/image-image.exr', input1a_directory));
    t1ax = exrread(sprintf('%s/image-image.exr', input1ax_directory));
    t1ay = exrread(sprintf('%s/image-image.exr', input1ay_directory));
    t1b = exrread(sprintf('%s/image-image.exr', input1b_directory));
    if index >= 1
        t0b = exrread(sprintf('%s/image-image.exr', input0b_directory));
    end
    
    % Combine throughputs.
    t = 0.25 * (t1a + t1ax + t1ay + t1b);
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
    if(EXR_OUT)
        exrwrite(t, sprintf('%s/image-primal_%d.exr', OUT_DIR, index));
    end
    
    % Calculate dx.
    t1ax_shifted = [t1ax(:, 2:end, :) t1ax(:, end, :)];
    dx = t1ax_shifted - t1a;
    write_pfm(dx, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
    if(EXR_OUT)
        exrwrite(dx, sprintf('%s/image-dx_%d.exr', OUT_DIR, index));
    end
    
    % Calculate dy.
    t1ay_shifted = [t1ay(2:end, :, :); t1ay(end, :, :)];
    dy = t1ay_shifted - t1a;
    write_pfm(dy, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);
    if(EXR_OUT)
        exrwrite(dy, sprintf('%s/image-dy_%d.exr', OUT_DIR, index));
    end

    % Calculate dt for previous frame.
    if index >= 1
        dt = t1a - t0b;
        write_pfm(dt, sprintf('%s/image-dt_%d.pfm', OUT_DIR, index - 1), true);
        if(EXR_OUT)
            exrwrite(dt, sprintf('%s/image-dt_%d.exr', OUT_DIR, index - 1));
        end
    end
end

% Recostruction setup for primary sample space GPT.
function combine_PSS_GPT_DX(index)
    EXR_OUT = false; %enable for debugging

    input1a_directory = sprintf(FRAME_TEMPLATE, index, index);
    input1ax_directory = sprintf('%s_x',sprintf(FRAME_TEMPLATE, index, index));
    input1ay_directory = sprintf('%s_y',sprintf(FRAME_TEMPLATE, index, index));

    % Read source data.
    t1a = exrread(sprintf('%s/image-image.exr', input1a_directory));
    t1ax = exrread(sprintf('%s/image-image.exr', input1ax_directory));
    t1ay = exrread(sprintf('%s/image-image.exr', input1ay_directory));
    
    % Combine throughputs.
    t = (t1a + t1ax + t1ay) / 3.0;
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
    if(EXR_OUT)
        exrwrite(t, sprintf('%s/image-primal_%d.exr', OUT_DIR, index));
    end
    
    % Calculate dx.
    t1ax_shifted = [t1ax(:, 2:end, :) t1ax(:, end, :)];
    dx = t1ax_shifted - t1a;
    write_pfm(dx, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
    if(EXR_OUT)
        exrwrite(dx, sprintf('%s/image-dx_%d.exr', OUT_DIR, index));
    end
    
    % Calculate dy.
    t1ay_shifted = [t1ay(2:end, :, :); t1ay(end, :, :)];
    dy = t1ay_shifted - t1a;
    write_pfm(dy, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);
    if(EXR_OUT)
        exrwrite(dy, sprintf('%s/image-dy_%d.exr', OUT_DIR, index));
    end
end

% Recostruction setup for primary sample space TGPT without spatial gradients.
function combine_PSS_TGPT_DT(index)
    EXR_OUT = false; %enable for debugging

    input0b_directory = sprintf(FRAME_B_TEMPLATE, index - 1, index);
    input1a_directory = sprintf(FRAME_A_TEMPLATE, index, index);
    input1b_directory = sprintf(FRAME_B_TEMPLATE, index, index + 1);

    % Read source data.
    t1a = exrread(sprintf('%s/image-image.exr', input1a_directory));
    t1b = exrread(sprintf('%s/image-image.exr', input1b_directory));
    if index >= 1
        t0b = exrread(sprintf('%s/image-image.exr', input0b_directory));
    end
    
    % Combine throughputs.
    t = 0.5 * (t1a + t1b);
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
    if(EXR_OUT)
        exrwrite(t, sprintf('%s/image-primal_%d.exr', OUT_DIR, index));
    end
    
    % Output zero derivatives as placeholders.
    ds = zeros(size(t));
    write_pfm(ds, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
    write_pfm(ds, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);

    % Calculate dt for previous frame.
    if index >= 1
        dt = t1a - t0b;
        write_pfm(dt, sprintf('%s/image-dt_%d.pfm', OUT_DIR, index - 1), true);
        if(EXR_OUT)
            exrwrite(dt, sprintf('%s/image-dt_%d.exr', OUT_DIR, index - 1));
        end
    end
end

function combine_GPT_GPT(index, USE_MOTION_VECTORS)
    input0a_directory = sprintf(FRAME_A_TEMPLATE, index - 1, index - 1);
    input0b_directory = sprintf(FRAME_B_TEMPLATE, index - 1, index);
    input1a_directory = sprintf(FRAME_A_TEMPLATE, index, index);
    input1b_directory = sprintf(FRAME_B_TEMPLATE, index, index + 1);

    % Combine dx.
    dx1a = exrread(sprintf('%s/image-dx.exr', input1a_directory));
    dx1b = exrread(sprintf('%s/image-dx.exr', input1b_directory));
    dx = 0.5 * (dx1a + dx1b);
    write_pfm(dx, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
  
    % Combine dy.
    dy1a = exrread(sprintf('%s/image-dy.exr', input1a_directory));
    dy1b = exrread(sprintf('%s/image-dy.exr', input1b_directory));
    dy = 0.5 * (dy1a + dy1b);
    write_pfm(dy, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);

    
    % Calculate dt for previous frame.
    if index >= 1
        t0b = exrread(sprintf('%s/image-primal.exr', input0b_directory));
        d0b = exrread(sprintf('%s/image-direct.exr', input0b_directory));
        t1a = exrread(sprintf('%s/image-primal.exr', input1a_directory));
        d1a = exrread(sprintf('%s/image-direct.exr', input1a_directory));
        dt = (t1a + d1a) - (t0b + d0b);
        write_pfm(dt, sprintf('%s/image-dt_%d.pfm', OUT_DIR, index - 1), true);
    end

    % Combine throughputs and directs.
    t1a = exrread(sprintf('%s/image-primal.exr', input1a_directory));
    d1a = exrread(sprintf('%s/image-direct.exr', input1a_directory));
    t1b = exrread(sprintf('%s/image-primal.exr', input1b_directory));
    d1b = exrread(sprintf('%s/image-direct.exr', input1b_directory));
    t = 0.5 * (t1a + d1a + t1b + d1b);
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
end

function combine_GPT_NOTIME(index)
    input0a_directory = sprintf(FRAME_A_TEMPLATE, index - 1, index - 1);
    input0b_directory = sprintf(FRAME_B_TEMPLATE, index - 1, index);
    input1a_directory = sprintf(FRAME_A_TEMPLATE, index, index);
    input1b_directory = sprintf(FRAME_B_TEMPLATE, index, index + 1);

    % Combine dx.
    dx1a = exrread(sprintf('%s/image-dx.exr', input1a_directory));
    dx1b = exrread(sprintf('%s/image-dx.exr', input1b_directory));
    dx = 0.5 * (dx1a + dx1b);
    write_pfm(dx, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
  
    % Combine dy.
    dy1a = exrread(sprintf('%s/image-dy.exr', input1a_directory));
    dy1b = exrread(sprintf('%s/image-dy.exr', input1b_directory));
    dy = 0.5 * (dy1a + dy1b);
    write_pfm(dy, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);

    % Combine throughputs and directs.
    t1a = exrread(sprintf('%s/image-primal.exr', input1a_directory));
    d1a = exrread(sprintf('%s/image-direct.exr', input1a_directory));
    t1b = exrread(sprintf('%s/image-primal.exr', input1b_directory));
    d1b = exrread(sprintf('%s/image-direct.exr', input1b_directory));
    t = 0.5 * (t1a + d1a + t1b + d1b);
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
end

function combine_GPT(index)
    input1_directory = sprintf(FRAME_TEMPLATE, index, index);

    % Combine dx.
    dx1a = exrread(sprintf('%s/image-dx.exr', input1_directory));
    dx = dx1a;
    write_pfm(dx, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
  
    % Combine dy.
    dy1a = exrread(sprintf('%s/image-dy.exr', input1_directory));
    dy = dy1a;
    write_pfm(dy, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);
    
    % Combine throughputs and directs.
    t1 = exrread(sprintf('%s/image-primal.exr', input1_directory));
    d1 = exrread(sprintf('%s/image-direct.exr', input1_directory));
    t = t1 + d1;
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
end

function combine_GPT_ADAPTIVE(index)
    input1_directory = sprintf(FRAME_TEMPLATE, index, index);

    % Combine dx.
    dx1a = exrread(sprintf('%s/image-dx.exr', input1_directory));
    dx = dx1a;
    write_pfm(dx, sprintf('%s/image-dx_%d.pfm', OUT_DIR, index), true);
  
    % Combine dy.
    dy1a = exrread(sprintf('%s/image-dy.exr', input1_directory));
    dy = dy1a;
    write_pfm(dy, sprintf('%s/image-dy_%d.pfm', OUT_DIR, index), true);
    
    % Combine throughputs and directs.
    t1 = exrread(sprintf('%s/image-primal.exr', input1_directory));
    d1 = exrread(sprintf('%s/image-direct.exr', input1_directory));
    t = t1 + d1;
    write_pfm(t, sprintf('%s/image-primal_%d.pfm', OUT_DIR, index), true);
    
    % Sampling map.
    sm = exrread(sprintf('%s/image-spp.exr', input1_directory));
    write_pfm(sm, sprintf('%s/image-spp_%d.pfm', OUT_DIR, index), true);
    exrwrite(sm, sprintf('%s/image-spp_%d.exr', OUT_DIR, index));
end

function combine_PATH_ADAPTIVE(index)
    input_directory = sprintf(FRAME_TEMPLATE, index, index);

    % Store throughputs.
    t = exrread(sprintf('%s/image-primal.exr', input_directory));
    write_pfm(t, sprintf('%s/image-final_%d.pfm', OUT_DIR, index), true);
    
    sm = exrread(sprintf('%s/image-spp.exr', input_directory));
    write_pfm(sm, sprintf('%s/image-spp_%d.pfm', OUT_DIR, index), true);
    exrwrite(sm, sprintf('%s/image-spp_%d.exr', OUT_DIR, index));
end

function combine_PATH(index)
    input_directory = sprintf(FRAME_TEMPLATE, index, index);

    % Store throughputs.
    t = exrread(sprintf('%s/image-image.exr', input_directory));
    write_pfm(t, sprintf('%s/image-final_%d.pfm', OUT_DIR, index), true);
end

function combine_AVERAGE(frames_)
    
    for i_ = frames_
        input_directory = sprintf(FRAME_TEMPLATE, i_, i_);

        t = exrread(sprintf('%s/image-image.exr', input_directory));
        
        if i_ == frames_(1)
            t_mean = t;
        else
            t_mean = t_mean + t;
        end
    end
       
    t_mean = t_mean / numel(frames_);
    
    % Store average.
    write_pfm(t_mean, sprintf('%s/image-final.pfm', OUT_DIR), true);
end


function reconstructSingleWindow(window_name_, begin_, end_, use_l1_, use_time_, use_ddxt_, use_ddxx_, use_ddxy_, use_mv_, use_dx_)
    % Delete and recreate the temporary directory.
    if exist(TEMP_DIRECTORY, 'dir')
        rmdir(TEMP_DIRECTORY, 's')
    end
    if ~exist(TEMP_DIRECTORY, 'dir')
        mkdir(TEMP_DIRECTORY)
    end
    
    % Copy the files into the temporary directory.
    for i_ = begin_ : end_
        % Dx.
        in_file_ = sprintf('%s/image-dx_%d.pfm', OUT_DIR, i_);
        out_file_ = sprintf('%s/image-dx_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
        copyfile(in_file_, out_file_);
        
        % Dy.
        in_file_ = sprintf('%s/image-dy_%d.pfm', OUT_DIR, i_);
        out_file_ = sprintf('%s/image-dy_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
        copyfile(in_file_, out_file_);
        
		if use_time_
			% Dt.
			in_file_ = sprintf('%s/image-dt_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-dt_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
			if i_ ~= end_
				copyfile(in_file_, out_file_);
			end
        end
		
		if use_ddxt_
			% Ddxt.
			in_file_ = sprintf('%s/image-ddxt_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-ddxt_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
			if i_ ~= end_
				copyfile(in_file_, out_file_);
			end
		
			% Ddyt.
			in_file_ = sprintf('%s/image-ddyt_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-ddyt_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
			if i_ ~= end_
				copyfile(in_file_, out_file_);
			end
        end
		
        if use_ddxx_
			% Ddxx.
			in_file_ = sprintf('%s/image-ddxx_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-ddxx_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
			copyfile(in_file_, out_file_);
				
			% Ddyy.
			in_file_ = sprintf('%s/image-ddyy_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-ddyy_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
			copyfile(in_file_, out_file_);			
        end
        
        if use_ddxy_
			% Ddxy.
			in_file_ = sprintf('%s/image-ddxy_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-ddxy_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
			copyfile(in_file_, out_file_);
        end
        
        if use_mv_
			% Motion map forward.
			in_file_ = sprintf('%s/image-motion_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-motion_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
            if i_ ~= end_
                copyfile(in_file_, out_file_);
            end
            % Motion map backward.
			in_file_ = sprintf('%s/image-motion-inv_%d.pfm', OUT_DIR, i_);
			out_file_ = sprintf('%s/image-motion-inv_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
            if i_ ~= end_
                copyfile(in_file_, out_file_);
            end
         end
        
        % Throughput.
        in_file_ = sprintf('%s/image-primal_%d.pfm', OUT_DIR, i_);
        out_file_ = sprintf('%s/image-primal_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
        copyfile(in_file_, out_file_);
    end
        
    % Set flags.
    if use_time_
        time_flag_ = '-time ';
    else
        time_flag_ = '';
    end
	
	if use_ddxt_
		ddxt_flag_ = '-ddxt ';
	else
		ddxt_flag_ = '';
    end
    
    if use_ddxx_
		ddxx_flag_ = '-ddxx ';
	else
		ddxx_flag_ = '';
    end
    
    if use_ddxy_
		ddxy_flag_ = '-ddxy ';
	else
		ddxy_flag_ = '';
    end
    
    if use_mv_
		mv_flag_ = '-mv ';
	else
		mv_flag_ = '';
    end
    
    if use_dx_
        dx_flag_ = '';
    else
        dx_flag_ = '-weight_ds 0';
    end
    
    % Reconstruct.
    if use_l1_
        fprintf('Constructing window %d..%d with L1.\n', begin_, end_);
        
        reconstruct_command_ = sprintf('%s -dx %s/image-dx.pfm -alpha 0.2 -config L1D -nopngout -nframes %d %s %s %s %s %s %s', RECONSTRUCT_L1, TEMP_DIRECTORY, end_ + 1 - begin_, time_flag_, ddxt_flag_, ddxx_flag_, ddxy_flag_, mv_flag_, dx_flag_);
        
        fprintf('    %s\n', reconstruct_command_);
        tic;
        [status_, cmdout_] = system(reconstruct_command_);
        fprintf('%s\n', cmdout_)
        time_ = toc;
    else
        fprintf('Constructing window %d..%d with L2.\n', begin_, end_);
        
        reconstruct_command_ = sprintf('%s -dx %s/image-dx.pfm -alpha 0.2 -config L2D -nopngout -nframes %d %s %s %s %s %s %s', RECONSTRUCT_L2, TEMP_DIRECTORY, end_ + 1 - begin_, time_flag_, ddxt_flag_, ddxx_flag_, ddxy_flag_, mv_flag_, dx_flag_);
        
        fprintf('    %s\n', reconstruct_command_);
        tic;
        [status_, cmdout_] = system(reconstruct_command_);
        fprintf('%s\n', cmdout_)
        time_ = toc;
    end
    
    % Move the results back.
    for i_ = begin_ : end_
        % Throughput.
        in_file_ = sprintf('%s/image-final_%d.pfm', TEMP_DIRECTORY, i_ - begin_);
        out_file_ = sprintf('%s/image-%s_%d.pfm', OUT_DIR, window_name_, i_);
        movefile(in_file_, out_file_);
    end
    
    % Clean up.
    if exist(TEMP_DIRECTORY, 'dir')
        rmdir(TEMP_DIRECTORY, 's')
    end
end

function reconstructAll(use_l1_, use_time_, use_ddxt_, use_ddxx_, use_ddxy_, use_mv_, use_dx_)
    window_step_ = WINDOW_LENGTH / 2;

    frame_count_ = numel(FRAMES);
    
    %% Reconstruct all windows.
    window_begin_ = 1;
    window_end_ = WINDOW_LENGTH;
    window_index_ = 0;
    
    fprintf('Reconstructing windows.\n');
    
    while true
        window_end_ = min(window_end_, frame_count_);
        
        % Reconstruct the window.
        if mod(window_index_, 2) == 0
            window_name_ = 'windowA';
        else
            window_name_ = 'windowB';
        end
        
        reconstructSingleWindow(window_name_, FRAMES(window_begin_), FRAMES(window_end_), use_l1_, use_time_, use_ddxt_, use_ddxx_, use_ddxy_, use_mv_, use_dx_);
 
        if window_end_ >= frame_count_
            break;
        end
        
        % Next window.
        window_begin_ = window_begin_ + window_step_;
        window_end_ = window_end_ + window_step_;
        window_index_ = window_index_ + 1;
    end
    
    % Calculate weights for frames.
    window_weights_ = zeros(frame_count_, 2);
    
    window_begin_ = 1;
    window_end_ = WINDOW_LENGTH;
    window_center_ = 0.5 * (window_end_ + window_begin_);
    window_index_ = 0;
    
    while  true
        window_end_ = min(window_end_, frame_count_);
        current_window_ = mod(window_index_, 2);
        
        for i_ = window_begin_ : window_end_
            window_weights_(i_, 1 + current_window_) = weightFunction(i_, window_center_, WINDOW_LENGTH);
        end

        if window_end_ >= frame_count_
            break;
        end
        
        window_begin_ = window_begin_ + window_step_;
        window_center_ = window_center_ + window_step_;
        window_end_ = window_end_ + window_step_;
        window_index_ = window_index_ + 1;
    end
        
    % Combine results.
    fprintf('Combining windows.\n');
    
    for i_ = 1 : numel(FRAMES)
        frame_ = FRAMES(i_);
        
        fileA_ = sprintf('%s/image-windowA_%d.pfm', OUT_DIR, frame_);
        fileB_ = sprintf('%s/image-windowB_%d.pfm', OUT_DIR, frame_);
        
        weightA_ = window_weights_(i_, 1);
        weightB_ = window_weights_(i_, 2);
        
        if weightA_ > 0
            image_ = weightA_ * read_pfm(fileA_, true);
            if weightB_ > 0
                image_ = image_ + weightB_ * read_pfm(fileB_, true);
            end
        else
            image_ = weightB_ * read_pfm(fileB_, true);
        end
        
        image_ = image_ / (weightA_ + weightB_);
        
        final_file_ = sprintf('%s/image-final_%d.pfm', OUT_DIR, frame_);
        write_pfm(image_, final_file_, true);
    end
end


function convertFinalToPng()
    fprintf('Converting frames to PNG.\n');
    
    % Convert files to PNG in batches.
    CONVERT_BATCH_SIZE_ = 30;
    files_ = {};
    for i_ = 1 : numel(FRAMES)
        frame_ = FRAMES(i_);
        files_{i_} = sprintf('%s/image-final_%d.pfm', OUT_DIR, frame_);
    end
    
    for i_ = 1 : ceil(numel(FRAMES) / CONVERT_BATCH_SIZE_)
        begin_ = 1 + (i_ - 1) * CONVERT_BATCH_SIZE_;
        end_ = min(begin_ + CONVERT_BATCH_SIZE_, numel(FRAMES));
        
        commandline_ = sprintf('%s %s', PFM2PNG, strjoin(files_(begin_ : end_), ' '));
        [status_, cmdout_] = system(commandline_);
    end
    
    % Convert the single final image if it exists.
    final_image_ = sprintf('%s/image-final.pfm', OUT_DIR);
    if exist(final_image_, 'dir')
        commandline_ = sprintf('%s %s', PFM2PNG, final_image_);
        [status_, cmdout_] = system(commandline_);
    end
    
end

function convertFinalPngToMp4()
    fprintf('Converting PNG to mp4.\n');
    
    % Delete and recreate the temporary directory.
    if exist(TEMP_DIRECTORY, 'dir')
        rmdir(TEMP_DIRECTORY, 's')
    end
    if ~exist(TEMP_DIRECTORY, 'dir')
        mkdir(TEMP_DIRECTORY)
    end
    
    % Copy frames to temporary directory.
    for i_ = 1 : numel(FRAMES)
        frame_ = FRAMES(i_);
		in_file_ = sprintf('%s/image-final_%d.png', OUT_DIR, frame_);
        out_file_ = sprintf('%s/image-final_%d.png', TEMP_DIRECTORY, frame_);
        copyfile(in_file_, out_file_);
    end
    
    % Create the video.
    if strcmp(VIDEO_TYPE, 'loop')
        make_videos = MAKE_VIDEOS_LOOP;
    elseif strcmp(VIDEO_TYPE, 'single')
        make_videos = MAKE_VIDEOS;
    end

    commandline_ = sprintf('%s %s 30 1 %s', make_videos, TEMP_DIRECTORY, task_name);
    system(commandline_);
    
	% Create a directory for the video.
	if ~exist(VIDEO_OUT_DIR, 'dir')
        mkdir(VIDEO_OUT_DIR)
    end
	
    % Copy the video back.
    in_file_ = sprintf('%s.mp4', task_name);
    out_file_ = sprintf('%s/%s.mp4', VIDEO_OUT_DIR, task_name);
    movefile(in_file_, out_file_);
    
    % Delete temporary directory and files.
    if exist(TEMP_DIRECTORY, 'dir')
        rmdir(TEMP_DIRECTORY, 's')
    end
    delete(sprintf('%s_stderr.txt', task_name));
end


% Combine frames.
if COMBINE
    % Create the out directory.
    if ~exist(OUT_DIR, 'dir')
		mkdir(OUT_DIR);
    end

    % Combine the data.
    fprintf('Combining data for reconstruction.\n');
    
    for i = FRAMES
        fprintf('Combining frame %d/%d.\n', 1+i, 1+FRAMES(end))
        if strcmp(RECONSTRUCTION_TYPE, 'gpt-gpt')
            combine_GPT_GPT(i, USE_MOTION_VECTORS)
        elseif strcmp(RECONSTRUCTION_TYPE, 'tgpt-ddxt')
            combine_GPT_GPT_DDXT(i, USE_MOTION_VECTORS)   
        elseif strcmp(RECONSTRUCTION_TYPE, 'path')
            combine_PATH(i)
        elseif strcmp(RECONSTRUCTION_TYPE, 'path-adaptive')
            combine_PATH_ADAPTIVE(i)
        elseif strcmp(RECONSTRUCTION_TYPE, 'gpt')
            combine_GPT(i)
        elseif strcmp(RECONSTRUCTION_TYPE, 'gpt-adaptive')
            combine_GPT_ADAPTIVE(i)
        elseif strcmp(RECONSTRUCTION_TYPE, 'pss-tgpt-dx-dt')
            combine_PSS_TGPT_DX_DT(i)
        elseif strcmp(RECONSTRUCTION_TYPE, 'dt-only-full')
            combine_DT_ONLY_FULL(i, USE_MOTION_VECTORS)
        elseif strcmp(RECONSTRUCTION_TYPE, 'pss-gpt-dx')
            combine_PSS_GPT_DX(i)
        elseif strcmp(RECONSTRUCTION_TYPE, 'pss-tgpt-dt')
            combine_PSS_TGPT_DT(i)
        elseif strcmp(RECONSTRUCTION_TYPE, 'gpt-notime')
            combine_GPT_NOTIME(i)
        end
    end
    
    if strcmp(RECONSTRUCTION_TYPE, 'average')
        combine_AVERAGE(FRAMES)
    end
end



% Reconstuct.
if RECONSTRUCT
    if strcmp(RECONSTRUCTION_TYPE, 'path') || strcmp(RECONSTRUCTION_TYPE, 'path-adaptive')
        convertFinalToPng()
        convertFinalPngToMp4()
    elseif strcmp(RECONSTRUCTION_TYPE, 'gpt-notime') || strcmp(RECONSTRUCTION_TYPE, 'gpt-gpt') || ...
            strcmp(RECONSTRUCTION_TYPE, 'gpt') || strcmp(RECONSTRUCTION_TYPE, 'gpt-adaptive') || strcmp(RECONSTRUCTION_TYPE, 'tgpt-ddxt') || ...
            strcmp(RECONSTRUCTION_TYPE, 'pss-tgpt-dx-dt') || strcmp(RECONSTRUCTION_TYPE, 'pss-gpt-dx') || strcmp(RECONSTRUCTION_TYPE, 'pss-tgpt-dt') || ...
            strcmp(RECONSTRUCTION_TYPE, 'dt-only-full')
        if USE_L1
            reconstructAll(true, USE_TIME, USE_DDXT, USE_DDXX, USE_DDXY, USE_MOTION_VECTORS, USE_DX);
            convertFinalToPng()
            convertFinalPngToMp4()
    
            for i = 0 : numel(FRAMES) - 1
                in_file = sprintf('%s/image-final_%d.pfm', OUT_DIR, i);
                out_file = sprintf('%s/image-final-L1_%d.pfm', OUT_DIR, i);
                movefile(in_file, out_file);

                in_file = sprintf('%s/image-final_%d.png', OUT_DIR, i);
                out_file = sprintf('%s/image-final-L1_%d.png', OUT_DIR, i);
                movefile(in_file, out_file);
            end
            
            in_file = sprintf('%s/%s.mp4', VIDEO_OUT_DIR, task_name);
            out_file = sprintf('%s/%s-L1.mp4', VIDEO_OUT_DIR, task_name);
            movefile(in_file, out_file);
        end

        if USE_L2
            reconstructAll(false, USE_TIME, USE_DDXT, USE_DDXX, USE_DDXY, USE_MOTION_VECTORS, USE_DX);

            convertFinalToPng()
            convertFinalPngToMp4()
            
            for i = 0 : numel(FRAMES) - 1
                in_file = sprintf('%s/image-final_%d.pfm', OUT_DIR, i);
                out_file = sprintf('%s/image-final-L2_%d.pfm', OUT_DIR, i);
                movefile(in_file, out_file);
                
                in_file = sprintf('%s/image-final_%d.png', OUT_DIR, i);
                out_file = sprintf('%s/image-final-L2_%d.png', OUT_DIR, i);
                movefile(in_file, out_file);
            end
            
            in_file = sprintf('%s/%s.mp4', VIDEO_OUT_DIR, task_name);
            out_file = sprintf('%s/%s-L2.mp4', VIDEO_OUT_DIR, task_name);
            movefile(in_file, out_file);
        end
    elseif strcmp(RECONSTRUCTION_TYPE, 'average')
        convertFinalToPng()
    end
end


end


function img = motionAwareCombine(img1, img2, motionIndex, motionMask)
    [ysize, xsize, n] = size(img1);

    imgR = img1(:, :, 1);
    imgR = imgR(:);
    imgG = img1(:, :, 2);
    imgG = imgG(:);
    imgB = img1(:, :, 3);
    imgB = imgB(:);
    img2R = img2(:, :, 1);
    img2R = img2R(:);
    img2G = img2(:, :, 2);
    img2G = img2G(:);
    img2B = img2(:, :, 3);
    img2B = img2B(:);

    imgR(motionMask) = 0.5 * (imgR(motionMask) + img2R(motionIndex(motionMask)));
    imgG(motionMask) = 0.5 * (imgG(motionMask) + img2G(motionIndex(motionMask)));
    imgB(motionMask) = 0.5 * (imgB(motionMask) + img2B(motionIndex(motionMask)));

    img(:, :, 1) = reshape(imgR, ysize, xsize);
    img(:, :, 2) = reshape(imgG, ysize, xsize);
    img(:, :, 3) = reshape(imgB, ysize, xsize);
end        
        