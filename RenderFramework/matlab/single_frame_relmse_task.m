function single_frame_relmse_task(scene_name, task_name, reference_task_name, frame_number, in_dir, out_dir)


task_path = sprintf('%s/%s', scene_name, task_name);
reference_task_path = sprintf('%s/%s', scene_name, reference_task_name);


fprintf('Estimating single frame relMSE for task "%s".\n', task_name);

% Create directory.
out_directory = sprintf('%s/_aaa_single_frame_relmse', out_dir);

if ~exist(out_directory, 'dir')
    mkdir(out_directory)
end

% Get the results.
relmse = single_frame_relmse(task_path, reference_task_path, frame_number, in_dir);
fprintf('    %f\n', relmse);

% Write to file.
outfile_path = sprintf('%s/%s.txt', out_directory, task_name);
outfile = fopen(outfile_path, 'w');
fprintf(outfile, '%f', relmse);
fclose(outfile);


end