% section: configure synthetic firing rate trace
% we seed randomness for repeatability and build a noisy baseline with precise burst injections at known times.
rng(42);
time_vector = 0:0.001:60;
smoothed_rate = randn(size(time_vector)) * 0.3 + 2;
burst_times = [10, 30, 50];
burst_sigma = 0.02;
burst_amplitude = 10;
for k = 1:numel(burst_times)
    gaussian_pulse = burst_amplitude * exp(-0.5 * ((time_vector - burst_times(k)) / burst_sigma) .^ 2);
    smoothed_rate = smoothed_rate + gaussian_pulse;
end

% section: run event detection
% we invoke the burst finder with a strict threshold and generous refractory window to isolate the three known peaks.
threshold_std_factor = 3.0;
min_separation_s = 5.0;
detected_times = find_burst_events(smoothed_rate, time_vector, threshold_std_factor, min_separation_s);

% section: assert expected detections
% we confirm the detector finds exactly three bursts and that each aligns with the planted peaks within a tight tolerance.
assert(numel(detected_times) == 3, 'Test Failed: Should have detected 3 events.');
assert(abs(detected_times(1) - 10) < 0.1, 'Test Failed: First event time is incorrect.');
assert(abs(detected_times(2) - 30) < 0.1, 'Test Failed: Second event time is incorrect.');
assert(abs(detected_times(3) - 50) < 0.1, 'Test Failed: Third event time is incorrect.');

% section: report success
% we print a friendly confirmation when all assertions pass.
fprintf('find_burst_events.m passed all tests!\n');
