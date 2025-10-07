function spike_times = load_spike_data(filepath)
% load_spike_data loads spike timing data from a mat file.

%% confirm the file exists before attempting to load anything.
if ~ischar(filepath) && ~isstring(filepath)
    error('load_spike_data:InvalidInput', 'filepath must be a character vector or string scalar.');
end
filepath = char(filepath);
if ~isfile(filepath)
    error('load_spike_data:FileNotFound', 'the file %s does not exist.', filepath);
end

%% load the mat file and pull out the spike_times variable alone.
loaded_data = load(filepath);
if ~isfield(loaded_data, 'spike_times')
    error('load_spike_data:MissingVariable', 'the file must contain a spike_times variable.');
end
spike_times = loaded_data.spike_times;

%% validate the spike_times vector and coerce it into a column for downstream code.
if ~isnumeric(spike_times) || ~isvector(spike_times)
    error('load_spike_data:InvalidVariable', 'spike_times must be a numeric vector.');
end
spike_times = spike_times(:);
end
