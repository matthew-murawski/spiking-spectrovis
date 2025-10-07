function event_table = load_label_data(filepath)
% load_label_data reads tab-separated label events into a table.

%% confirm the file path input is sane before opening anything on disk.
if ~ischar(filepath) && ~isstring(filepath)
    error('load_label_data:InvalidInput', 'filepath must be a character vector or string scalar.');
end
filepath = char(filepath);
if ~isfile(filepath)
    error('load_label_data:FileNotFound', 'the file %s does not exist.', filepath);
end

%% read the file line by line so we can skip headers and blank rows.
fid = fopen(filepath, 'r');
if fid < 0
    error('load_label_data:FileOpenFailed', 'could not open %s for reading.', filepath);
end
file_guard = onCleanup(@() fclose(fid)); %#ok<NASGU>

onset_values = [];
offset_values = [];
label_values = strings(0, 1);

while true
    current_line = fgetl(fid);
    if ~ischar(current_line)
        break;
    end
    trimmed_line = strtrim(current_line);
    if isempty(trimmed_line)
        continue;
    end
    line_fields = split(string(trimmed_line), "\t");
    if numel(line_fields) < 3
        continue;
    end
    onset_candidate = str2double(line_fields(1));
    offset_candidate = str2double(line_fields(2));
    if isnan(onset_candidate) || isnan(offset_candidate)
        continue;
    end
    label_fragment = strjoin(line_fields(3:end), "\t");
    onset_values(end + 1, 1) = onset_candidate; %#ok<AGROW>
    offset_values(end + 1, 1) = offset_candidate; %#ok<AGROW>
    label_values(end + 1, 1) = string(label_fragment); %#ok<AGROW>
end

%% assemble the output table with consistent variable names and types.
if isempty(onset_values)
    event_table = table(double.empty(0, 1), double.empty(0, 1), strings(0, 1), ...
        'VariableNames', {'Onset', 'Offset', 'Label'});
else
    event_table = table(onset_values, offset_values, label_values, ...
        'VariableNames', {'Onset', 'Offset', 'Label'});
end
end
