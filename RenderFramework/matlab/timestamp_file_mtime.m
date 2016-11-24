% Returns the time when a file was last modified as a UNIX timestamp.
function result = timestamp_file_mtime(filepath)
    files = dir(filepath);
    
    if length(files) == 0
        result = 0;
        return
    end
    
    % Get current time as a vector.
    dv = int32(datevec(files.datenum));
    
    % Convert to timestamp.
    cal = java.util.Calendar.getInstance;
    cal.set(cal.YEAR, dv(1));
    cal.set(cal.MONTH, dv(2)-1);
    cal.set(cal.DAY_OF_MONTH, dv(3));
    cal.set(cal.HOUR_OF_DAY, dv(4));
    cal.set(cal.MINUTE, dv(5));
    cal.set(cal.SECOND, dv(6));
    result = int64(cal.getTimeInMillis() / 1000);
end
