function result = read_task_config(task_path, results_directory)


CONFIG_FILE = sprintf('%s/%s/config.cfg', results_directory, task_path);


config = struct();


% Read config.
config_file = fopen(CONFIG_FILE, 'r');

if config_file < 0
    result = [];
    return;
end

key_value_pair_count = fscanf(config_file, '%d\n', 1);

for i = 1 : key_value_pair_count
    key = fgetl(config_file);
    value = fgetl(config_file);
    
    if strcmp(value, 'True')
        value = true;
    elseif strcmp(value, 'False')
        value = false;
    end
    
    config = setfield(config, key, value);
end


result = config;

fclose(config_file);


end