function reconstruct_task(scene_name, task_name, in_dir, out_dir, need_combine, need_reconstruct)

task_path = sprintf('%s/%s', scene_name, task_name);

config = read_task_config(task_path, out_dir);
reconstruct_impl(scene_name, task_name, str2num(config.internal__frame_range_begin) : str2num(config.internal__frame_range_end), config.internal__method, in_dir, out_dir, config, need_combine, need_reconstruct);


end