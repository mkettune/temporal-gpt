function result = single_frame_relmse(task_name, reference_task_name, frame_number, in_dir)
    image = load_image(task_name, frame_number, in_dir);
    reference_image = read_pfm(sprintf('%s/%s/image-final.pfm', in_dir, reference_task_name), true);
    
    result = calculate_relmse(image, reference_image);
end


function result = load_image(task_name, frame_number, in_dir)
    % Read image.
    found = false;
    
    % Read L1 reconstruction if available.
    candidate = sprintf('%s/%s/image-final-L1_%d.pfm', in_dir, task_name, frame_number);
    if exist(candidate, 'file') == 2
        file = candidate;
        found = true;
    else
        candidate = sprintf('%s/%s/image-final_%d.pfm', in_dir, task_name, frame_number);
        if exist(candidate, 'file') == 2
            file = candidate;
            found = true;
        end
    end
    
    if ~found
        error(sprintf('Frame %d of task %s file not found.', frame_number, task_name));
    end
    
    % Read the image.
    result = read_pfm(candidate, true);
end


function result = calculate_relmse(image, reference_image)
    relmse = 0.0;

    grayscale_reference = (0.2126 * reference_image(:, :, 1) + 0.7152 * reference_image(:, :, 2) + 0.0722 * reference_image(:, :, 3));
    grayscale_reference_rgb = repmat(grayscale_reference, [1 1 3]);

    result = mean(mean(mean((image - reference_image).^2 ./ (10e-3 + grayscale_reference_rgb.^2))));
end