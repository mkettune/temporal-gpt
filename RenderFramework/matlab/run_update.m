function run_update()


CLUSTER_RESULTS_DIR = '../cluster/results';
CONFIG_DIR = '../configs';
RESULT_DIR = '../results';


DEBUG = true;


%%% Scan data to see what needs to be done.


%% Validate cluster folders.

cluster_task_dirlist = dir(sprintf('%s', CLUSTER_RESULTS_DIR));
if length(cluster_task_dirlist) == 0
   error('Could not open cluster results directory.'); 
end

cluster_task_dirlist = cluster_task_dirlist([cluster_task_dirlist.isdir]);
cluster_task_dirlist(1:2) = [];

% Create a map from cluster tasks to timestamps.
for file = cluster_task_dirlist'
    cluster_task_name = file.name;
    
    if read_cluster_timestamp(cluster_task_name, RESULT_DIR, CLUSTER_RESULTS_DIR) == 0
        fprintf('Warning: Cluster folder "%s" has no timestamp.\n', cluster_task_name);
    end
end


%% Find all local tasks.
valid_tasks = {};
skipped_tasks = {};
failed_tasks = containers.Map;
scene_names = containers.Map;
task_names = containers.Map;

% Iterate over all scene directories.
scenes_dirlist = dir(RESULT_DIR);
scenes_dirlist = scenes_dirlist([scenes_dirlist.isdir]);
scenes_dirlist(1:2) = [];

i = 1;

for scene_file = scenes_dirlist'
    scene_name = scene_file.name;
    scene_directory = sprintf('%s/%s', RESULT_DIR, scene_name);
    
    if scene_name(1) == '_'
        continue;
    end
    
    % Iterate over all tasks in the directory.
    valid_tasks_dirlist = dir(scene_directory);
    valid_tasks_dirlist = valid_tasks_dirlist([valid_tasks_dirlist.isdir]);
    valid_tasks_dirlist(1:2) = [];

    for file = valid_tasks_dirlist'
        task_name = file.name;
    
        if task_name(1) == '_'
            continue;
        end

        task_path = sprintf('%s/%s', scene_name, task_name);

        % Check that the folder has a config file.
        config_file_path = sprintf('%s/%s/config.cfg', RESULT_DIR, task_path);
        if exist(config_file_path, 'file') ~= 2
            fprintf('Warning: Ignoring result folder "%s": Config file not found.\n', task_path);
            continue;
        end
        
        % Check that the folder has a cluster timestamp.
        task_config = read_task_config(task_path, RESULT_DIR);
        cluster_task_name = task_config.internal__cluster_task_name;
        cluster_timestamp = read_cluster_timestamp(cluster_task_name, RESULT_DIR, CLUSTER_RESULTS_DIR);
        if cluster_timestamp == 0
           fprintf('Warning: Skipping result folder "%s": Cluster timestamp not found.\n', task_path); 
           skipped_tasks{1 + numel(skipped_tasks)} = task_path;
           continue;
        end
    
        valid_tasks{i} = task_path;
        scene_names(task_path) = scene_name;
        task_names(task_path) = task_name;
    
        if DEBUG
            fprintf('Found task "%s".\n', task_path);
        end
    
        i = i + 1;
    end
end


%% Invoke reconstruction.
combine_write_index = 0;
combine_queue = {};
reconstruct_write_index = 0;
reconstruct_queue = {};
for i = 1 : length(valid_tasks)
    task_path = valid_tasks{i};
    scene_name = scene_names(task_path);
    task_name = task_names(task_path);
    
    % Get the cluster timestamp.
    task_config = read_task_config(task_path, RESULT_DIR);
    cluster_task_name = task_config.internal__cluster_task_name;
    cluster_timestamp = read_cluster_timestamp(cluster_task_name, RESULT_DIR, CLUSTER_RESULTS_DIR);
    
    % Get local timestamps.
	combine_timestamp = read_task_timestamp(task_path, RESULT_DIR, 'combine');
    reconstruct_timestamp = read_task_timestamp(task_path, RESULT_DIR, 'reconstruct');    

	% Workaround for data rendered with older versions of the rendering framework.
	if combine_timestamp == 0 && reconstruct_timestamp > 0
		combine_timestamp = reconstruct_timestamp;
	end
	
	% Check what needs to be done.
	need_combine = false;
	if combine_timestamp == 0 || combine_timestamp < cluster_timestamp
		need_combine = true;
	end
	
	need_reconstruct = false;
	if need_combine || reconstruct_timestamp == 0 || reconstruct_timestamp < cluster_timestamp
		need_reconstruct = true;
	end
	
	if need_combine || need_reconstruct
        % Invoke.
        if DEBUG
            fprintf('Task "%s" needs to be reconstructed.\n', task_path);
        end
        
        % Queue tasks for parallel execution.
        if need_combine
            task = struct('scene_name', scene_name, 'task_name', task_name, 'task_path', task_path, 'need_reconstruct', need_reconstruct);
            combine_write_index = combine_write_index + 1;
            combine_queue{combine_write_index} = task;
        elseif need_reconstruct
            task = struct('scene_name', scene_name, 'task_name', task_name, 'task_path', task_path);
            reconstruct_write_index = reconstruct_write_index + 1;
            reconstruct_queue{reconstruct_write_index} = task;
		end
        
        % Copy the config batch tag.
        task_batch = read_cluster_config(task_path, RESULT_DIR, CLUSTER_RESULTS_DIR);
        write_task_config(task_path, RESULT_DIR, task_batch)
    end
end

% Execute combining and reconstruction simultaneously.
combine_read_index = 1;
reconstruct_read_index = 1;

while combine_read_index <= numel(combine_queue) || reconstruct_read_index <= numel(reconstruct_queue)
    % Prepare tasks.
    c_task = struct('scene_name', '', 'task_name', '', 'task_path', '');
    r_task = struct('scene_name', '', 'task_name', '', 'task_path', '');
    c_error = 0;
    r_error = 0;
    
    if combine_read_index <= length(combine_queue)
        c_task = combine_queue{combine_read_index};
        combine_read_index = combine_read_index + 1;
        
        fprintf('Combining task "%s".\n', c_task.task_name);
    end
    
    if reconstruct_read_index <= length(reconstruct_queue)
        r_task = reconstruct_queue{reconstruct_read_index};
        reconstruct_read_index = reconstruct_read_index + 1;

        fprintf('Reconstructing task "%s".\n', r_task.task_name);
    end
    
    % Execute tasks.
    %parfor t = 1 : 2 % Enable for performance.
    for t = 1 : 2 % Enable for debugging.
        if t == 1
            if ~isempty(c_task.task_name)
                %try
                    % Combine.
                    reconstruct_task(c_task.scene_name, c_task.task_name, CLUSTER_RESULTS_DIR, RESULT_DIR, true, false);
                    write_task_timestamp(c_task.task_path, RESULT_DIR, 'combine');
                %catch ME
                %    warning(ME.identifier, ME.message);
                %    c_error = ME;
                %end
            end
        elseif t == 2
            if ~isempty(r_task.task_name)
                %try
                    % Reconstruct.
                    reconstruct_task(r_task.scene_name, r_task.task_name, CLUSTER_RESULTS_DIR, RESULT_DIR, false, true);
                    write_task_timestamp(r_task.task_path, RESULT_DIR, 'reconstruct');
                %catch ME
                %    warning(ME.identifier, ME.message);
                %    if ~isKey(failed_tasks, c_task.task_path)
                %        r_error = ME;
                %    end
                %end
            end
        end
    end
    
    % Add possible errors.
    if c_error ~= 0
        failed_tasks(c_task.task_path) = c_error
    end
    if r_error ~= 0
        failed_tasks(r_task.task_path) = r_error
    end

    % Create new tasks.
    if ~isempty(c_task.task_name)
        if c_task.need_reconstruct
            reconstruct_write_index = reconstruct_write_index + 1;
            reconstruct_queue{reconstruct_write_index} = struct('scene_name', c_task.scene_name, 'task_name', c_task.task_name, 'task_path', c_task.task_path);
        end
    end
end


%% Invoke single frame relmse tasks.
for i = 1 : length(valid_tasks)
    task_path = valid_tasks{i};
    scene_name = scene_names(task_path);
    task_name = task_names(task_path);
    
    % Skip failed tasks.
    if isKey(failed_tasks, task_path)
        continue;
    end

    % Read config.
    task_config = read_task_config(task_path, RESULT_DIR);
    
    config = read_single_frame_relmse_config(scene_name, CONFIG_DIR);
    
    % Skip some reconstruction methods.
    if strcmp(task_config.internal__method, 'average')
        continue;
    end
    
    % Skip tasks with not enough frames.
    if config.frame_number > str2num(task_config.internal__frame_range_end)
        continue;
    end
    
    % Get timestamps.
    config_timestamp = config.mtime;
    local_timestamp = read_task_timestamp(task_path, RESULT_DIR, 'single_frame_relmse');

    % Validate input.
    if config_timestamp == 0
        %if DEBUG
        %    fprintf('Scene "%s" does not have single frame relMSE configuration.\n', scene_name)
        %end
        continue;
    end
    
    % Do the task.
    if local_timestamp == 0 || config_timestamp > local_timestamp
        % Invoke.
        if DEBUG
            fprintf('Task "%s" needs single frame relMSE.\n', task_path);
        end

        single_frame_relmse_task(scene_name, task_name, config.reference_task, config.frame_number, RESULT_DIR, RESULT_DIR);
        write_task_timestamp(task_path, RESULT_DIR, 'single_frame_relmse');
    end
end


all_done = true;

if numel(skipped_tasks) > 0
    all_done = false;
    fprintf('*** The following tasks were skipped ***\n');
    for i = 1 : numel(skipped_tasks)
       fprintf('   * %s\n', skipped_tasks{i}); 
    end
end

if length(failed_tasks) > 0
    all_done = false;
    fprintf('*** The following errors were caught: ***\n');
    
    error_keys = keys(failed_tasks);
    for i = 1 : length(error_keys)
        task_path = keys{i}
        ME = failed_tasks{task_path};
        
        warning(ME.identifier, ME.message);
    end
else
    fprintf('All done.\n')
end


end


% Splits full path of a task into scene name and task name.
function [scene_name, task_name] = split_task_path(task_path)
    [pathstr, name, ext] = fileparts(task_path);
    scene_name = pathstr;
    task_name = name;
end

% Reads the timestamp when an operation was last made to a task.
function result = read_task_timestamp(task_name, result_dir, operation)
    task_timestamp_path = sprintf('%s/%s/timestamp_%s.txt', result_dir, task_name, operation);
    result = timestamp_load(task_timestamp_path);
end
    
% Updates the timestamp when an operation was last made to a task.
function write_task_timestamp(task_name, result_dir, operation)
    task_timestamp_time = timestamp();
    task_timestamp_path = sprintf('%s/%s/timestamp_%s.txt', result_dir, task_name, operation);
    timestamp_save(task_timestamp_time, task_timestamp_path);
end

% Reads the timestamp when the data was last updated.
function result = read_cluster_timestamp(cluster_task_name, results_dir, cluster_dir)    
    task_timestamp_path = sprintf('%s/%s/timestamp.txt', cluster_dir, cluster_task_name);
    result = timestamp_load(task_timestamp_path);
end

% Reads what batch config name the cluster rendering was done with.
function result = read_cluster_config(task_name, results_dir, cluster_dir)
    task_config = read_task_config(task_name, results_dir);
    cluster_task_name = task_config.internal__cluster_task_name;
    
    cluster_batch_path = sprintf('%s/%s/cluster_batch.txt', cluster_dir, cluster_task_name);
    cluster_batch = fileread(cluster_batch_path);
    
    result = cluster_batch;
end

% Creates a file that describes the name of the batch used for the task's cluster data.
function write_task_config(task_name, result_dir, batch)
    batch_path = sprintf('%s/%s/batch.txt', result_dir, task_name);
    file = fopen(batch_path, 'w');
    fprintf(file, '%s', batch);
    fclose(file);
end
