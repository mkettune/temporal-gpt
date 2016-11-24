function result = timestamp_save(time, path)
    file = fopen(path, 'w');
    fprintf(file, '%d', time);
    fclose(file);
end