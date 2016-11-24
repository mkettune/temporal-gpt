function result = timestamp_load(path)
    % Reads a timestamp from a file. If the file doesn't exist, returns 0.
    try
        file = fopen(path, 'r');
        data = fscanf(file, '%d');
        fclose(file);
        
        result = data;
    catch
        %fprintf('Warning: Could not open timestamp-file: %s\n', path);
        result = 0;
    end
end
