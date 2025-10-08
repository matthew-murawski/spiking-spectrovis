function event_times = find_burst_events(smoothed_rate, time_vector, threshold_std_factor, min_separation_s)
% section: overview
% this function identifies statistically meaningful burst onsets by combining a global threshold with a debounce window to avoid double-reporting.

% section: input normalization
% we coerce inputs to columns and confirm matching lengths so time indexing stays valid.
smoothed_rate = smoothed_rate(:);
time_vector = time_vector(:);
if numel(smoothed_rate) ~= numel(time_vector)
    error('find_burst_events:inputSizeMismatch', 'smoothed_rate and time_vector must be the same length.');
end
if ~isscalar(threshold_std_factor) || ~isscalar(min_separation_s)
    error('find_burst_events:scalarParams', 'threshold_std_factor and min_separation_s must be scalars.');
end
if min_separation_s < 0
    error('find_burst_events:negativeSeparation', 'min_separation_s must be nonnegative.');
end

% section: compute global threshold
% we estimate central tendency and spread from the smoothed rate and derive the detection boundary.
rate_mean = mean(smoothed_rate);
rate_std = std(smoothed_rate);
threshold_value = rate_mean + threshold_std_factor * rate_std;

% section: detect upward crossings
% we locate the first samples that jump above the threshold and translate them to candidate event times.
above_threshold = smoothed_rate >= threshold_value;
transition_mask = diff([false; above_threshold]) == 1;
candidate_indices = find(transition_mask);
candidate_times = time_vector(candidate_indices);

% section: enforce minimum separation
% we walk the candidate list and keep the first event in each cluster that violates the debounce spacing.
event_times = zeros(0, 1);
if isempty(candidate_times)
    return
end
last_kept_time = -inf;
for idx = 1:numel(candidate_times)
    current_time = candidate_times(idx);
    if current_time - last_kept_time >= min_separation_s
        event_times(end + 1, 1) = current_time; %#ok<AGROW>
        last_kept_time = current_time;
    end
end
end
