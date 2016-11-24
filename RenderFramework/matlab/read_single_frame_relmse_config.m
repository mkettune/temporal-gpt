function result = read_single_frame_relmse_config(scene_name, config_directory)


CONFIG_FILE = sprintf('%s/%s/config_single_frame_relmse.cfg', config_directory, scene_name); 


config = struct();
config.mtime = 0;
config.reference_task = '';
config.frame_number = -1;


% See that the file exists.
if exist(CONFIG_FILE, 'file') ~= 2
    fprintf('Warning: Scene "%s" has no single frame relmse config.\n', scene_name);
    
    result = config;
    return
end


% Read the modification time.
config.mtime = timestamp_file_mtime(CONFIG_FILE);


% Read the fields.
file = fopen(CONFIG_FILE, 'r');
config.reference_task = fgetl(file);
config.frame_number = fscanf(file, '%d', 1);
fclose(file);


% Sanitize input.
if strcmp(config.reference_task, '') || ~ischar(config.reference_task)
    error(sprintf('Scene "%s": Invalid reference task for single frame relMSE.', scene_name));
end
if config.frame_number < 0
    error(sprintf('Scene "%s": Invalid reference task for single frame relMSE.', scene_name));
end


% Output result.
result = config;


end