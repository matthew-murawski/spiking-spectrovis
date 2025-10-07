function smoothed_rate = calculate_smoothed_rate(spike_times, kernel_sd_s, time_vector)
% calculate_smoothed_rate converts spike times into a gaussian smoothed rate profile.

%% validate the spike time vector, kernel width, and evaluation grid before computing anything.
if ~isnumeric(spike_times) || ~isvector(spike_times)
    error('calculate_smoothed_rate:InvalidSpikes', 'spike_times must be a numeric vector.');
end
if ~isnumeric(kernel_sd_s) || ~isscalar(kernel_sd_s) || ~(kernel_sd_s > 0)
    error('calculate_smoothed_rate:InvalidKernel', 'kernel_sd_s must be a positive scalar.');
end
if ~isnumeric(time_vector) || ~isvector(time_vector)
    error('calculate_smoothed_rate:InvalidTimeVector', 'time_vector must be a numeric vector.');
end

spike_times = spike_times(:);
time_vector_size = size(time_vector);
time_points = time_vector(:);

%% handle empty spike trains early to avoid unnecessary allocation later.
if isempty(spike_times)
    smoothed_rate = zeros(time_vector_size);
    return;
end

%% ensure the time vector is strictly increasing to let us index contiguous windows.
if numel(time_points) > 1
    time_diffs = diff(time_points);
    if any(time_diffs <= 0)
        error('calculate_smoothed_rate:NonIncreasingTimeVector', 'time_vector must be strictly increasing.');
    end
    dt_est = median(time_diffs);
else
    dt_est = 1;
end

%% preallocate the rate vector and define the kernel support window in seconds.
smoothed_rate = zeros(size(time_points));
kernel_support_s = 6 * kernel_sd_s; % six sigma captures nearly all gaussian mass.
half_window = max(1, ceil(kernel_support_s / dt_est));

gaussian_norm = kernel_sd_s * sqrt(2 * pi);

%% loop over spikes and add localised gaussian contributions in place.
for spike_idx = 1:numel(spike_times)
    spike_time = spike_times(spike_idx);
    window_start = spike_time - half_window * dt_est;
    window_end = spike_time + half_window * dt_est;

    idx_start = find(time_points >= window_start, 1, 'first');
    idx_end = find(time_points <= window_end, 1, 'last');
    if isempty(idx_start) || isempty(idx_end)
        continue;
    end

    local_times = time_points(idx_start:idx_end);
    local_exponent = (local_times - spike_time) ./ kernel_sd_s;
    contribution = exp(-0.5 * (local_exponent .^ 2)) ./ gaussian_norm;
    smoothed_rate(idx_start:idx_end) = smoothed_rate(idx_start:idx_end) + contribution;
end

%% reshape the rate back to the original layout of time_vector for caller convenience.
smoothed_rate = reshape(smoothed_rate, time_vector_size);
end
