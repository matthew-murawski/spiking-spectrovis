% create_static_plot builds a static multi-panel visualization for demo data.

%% resolve project paths so the utility functions are available on the matlab path.
script_full_path = mfilename('fullpath');
if isempty(script_full_path)
    script_full_path = which('create_static_plot');
end
if isempty(script_full_path)
    error('create_static_plot:PathResolutionFailed', 'could not resolve create_static_plot.m on the matlab path.');
end
script_dir = fileparts(script_full_path);
project_root = script_dir;
utility_dir = fullfile(project_root, 'src');
if ~isfolder(utility_dir)
    error('create_static_plot:MissingSrcDir', 'expected src directory not found relative to the script.');
end
addpath(utility_dir);

%% configuration
demo_data_dir = fullfile(project_root, 'demo_data');
SPIKE_FILE = fullfile(demo_data_dir, 'test_spikes.mat');
AUDIO_FILE = fullfile(demo_data_dir, 'test_audio.wav');
LABEL_FILE = fullfile(demo_data_dir, 'test_labels.txt');
VIEW_WINDOW_S = [0, 10];
KERNEL_SD_S = 0.050;
AUDIO_SAMPLE_RATE = 44100;
AUDIO_DURATION_S = 10;
SPIKE_VALUES_S = [0.1; 0.5; 0.55; 1.2; 2.0; 2.5; 3.2; 4.0; 4.1; 5.7; 6.3; 7.8; 8.1; 9.4]; %#ok<NASGU>

%% ensure the demo data directory and its fixture files exist.
if ~isfolder(demo_data_dir)
    mkdir(demo_data_dir);
end
if ~isfile(SPIKE_FILE)
    spike_times = SPIKE_VALUES_S; %#ok<NASGU>
    save(SPIKE_FILE, 'spike_times');
end
if ~isfile(AUDIO_FILE)
    t = (0:(AUDIO_DURATION_S * AUDIO_SAMPLE_RATE) - 1)' ./ AUDIO_SAMPLE_RATE;
    audio_waveform = 0.05 * sin(2 * pi * 440 * t);
    audiowrite(AUDIO_FILE, audio_waveform, AUDIO_SAMPLE_RATE);
end
if ~isfile(LABEL_FILE)
    label_lines = [ ...
        "onset_s\toffset_s\tlabel"; ...
        "0.5\t0.7\tproduced_call"; ...
        "2.5\t3.2\tproduced_call"; ...
        "6.0\t7.0\tproduced_call"; ...
        "8.5\t9.5\tnoise_call" ...
    ];
    fid = fopen(LABEL_FILE, 'w');
    if fid < 0
        error('create_static_plot:LabelWriteFailed', 'could not open %s for writing.', LABEL_FILE);
    end
    cleaner = onCleanup(@() fclose(fid));
    for line_idx = 1:numel(label_lines)
        fprintf(fid, '%s\n', label_lines(line_idx));
    end
    clear cleaner;
end

%% data loading
spike_times = load_spike_data(SPIKE_FILE);
[audio_waveform, fs] = audioread(AUDIO_FILE);
event_table = load_label_data(LABEL_FILE);

%% data processing
time_vector = (0:numel(audio_waveform) - 1)' ./ fs;
smoothed_rate = calculate_smoothed_rate(spike_times, KERNEL_SD_S, time_vector);

%% plotting setup
figure('Name', 'Static Data Overview', 'Color', 'w');
layout = tiledlayout(7, 1, 'TileSpacing', 'none', 'Padding', 'compact');

%% spectrogram panel
ax1 = nexttile(layout, [3, 1]);
[s, f, t] = spectrogram(audio_waveform, 256, 128, 256, fs);
power_db = 20 * log10(abs(s) + eps);
frequency_axis = f;
if frequency_axis(1) == 0
    if numel(frequency_axis) > 1 && frequency_axis(2) > 0
        frequency_axis(1) = frequency_axis(2) / 2;
    else
        frequency_axis(1) = 1;
    end
end
imagesc(ax1, t, frequency_axis, power_db);
axis(ax1, 'xy');
colormap(ax1, 'turbo');
set(ax1, 'YScale', 'log');
ylabel(ax1, 'Frequency (Hz)');
xticklabels(ax1, []);

%% spike raster panel
ax2 = nexttile(layout);
hold(ax2, 'on');
line_half_height = 0.05;
line_thickness = 2.5;
for spike_idx = 1:numel(spike_times)
    spike_time = spike_times(spike_idx);
    line(ax2, [spike_time, spike_time], [0.5 - line_half_height, 0.5 + line_half_height], ...
        'Color', 'k', 'LineWidth', line_thickness);
end
hold(ax2, 'off');
ylim(ax2, [0, 1]);
yticks(ax2, []);
yticklabels(ax2, []);
box(ax2, 'off');
xticklabels(ax2, []);

%% smoothed firing rate panel
ax3 = nexttile(layout, [2, 1]);
plot(ax3, time_vector, smoothed_rate, 'LineWidth', 1.5);
ylabel(ax3, 'Firing Rate (Hz)');
grid(ax3, 'off');
xticklabels(ax3, []);

%% event indicator panel
ax4 = nexttile(layout);
hold(ax4, 'on');
ax4_color = [0.85, 0.15, 0.15];
baseline_height = [0.2, 0.8];
for event_idx = 1:height(event_table)
    onset = event_table.Onset(event_idx);
    offset = event_table.Offset(event_idx);
    patch(ax4, [onset, offset, offset, onset], ...
        [baseline_height(1), baseline_height(1), baseline_height(2), baseline_height(2)], ...
        ax4_color, 'FaceAlpha', 0.4, 'EdgeColor', 'none');
end
hold(ax4, 'off');
ylim(ax4, [0, 1]);
yticks(ax4, []);
yticklabels(ax4, []);
box(ax4, 'off');
xlabel(ax4, 'Time (s)');

%% synchronize axes and focus on the view window
linkaxes([ax1, ax2, ax3, ax4], 'x');
xlim(ax4, VIEW_WINDOW_S);

%% apply light grids to relevant panels for readability
for grid_axis = [ax1, ax3]
    grid(grid_axis, 'on');
end
