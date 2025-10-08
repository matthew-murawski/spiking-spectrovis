% build_gui assembles the gui shell, loads demo data, and renders static plots.

%% resolve project paths so utility functions are reachable from this script.
script_full_path = mfilename('fullpath');
if isempty(script_full_path)
    script_full_path = which('build_gui');
end
if isempty(script_full_path)
    error('build_gui:PathResolutionFailed', 'could not resolve build_gui.m on the matlab path.');
end
script_dir = fileparts(script_full_path);
project_root = script_dir;
utility_dir = fullfile(project_root, 'src');
if ~isfolder(utility_dir)
    error('build_gui:MissingSrcDir', 'expected src directory not found relative to the script.');
end
addpath(utility_dir);

%% configuration
DemoDir = fullfile(project_root, 'demo_data');
SPIKE_FILE = fullfile(DemoDir, 'test_spikes.mat');
AUDIO_FILE = fullfile(DemoDir, 'test_audio.wav');
LABEL_FILE = fullfile(DemoDir, 'test_labels.txt');
VIEW_WINDOW_S = [0, 10];
KERNEL_SD_S = 0.050;
AUDIO_SAMPLE_RATE = 44100;
AUDIO_DURATION_S = 10;
SPIKE_VALUES_S = [0.1; 0.5; 0.55; 1.2; 2.0; 2.5; 3.2; 4.0; 4.1; 5.7; 6.3; 7.8; 8.1; 9.4]; %#ok<NASGU>
DATA_CHUNK_S = [0, min(300, AUDIO_DURATION_S)];
VIEWPORT_WIDTH_S = 3;

%% ensure demo fixture files exist for the gui to load.
if ~isfolder(DemoDir)
    mkdir(DemoDir);
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
        error('build_gui:LabelWriteFailed', 'could not open %s for writing.', LABEL_FILE);
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

%% data chunk selection filters spikes, audio, and events to the desired window.
chunk_start = DATA_CHUNK_S(1);
chunk_end = DATA_CHUNK_S(2);
if chunk_end <= chunk_start
    error('build_gui:InvalidChunk', 'DATA_CHUNK_S must cover a positive time span.');
end

spike_mask = spike_times >= chunk_start & spike_times <= chunk_end;
spike_times = spike_times(spike_mask);

event_mask = (event_table.Offset > chunk_start) & (event_table.Onset < chunk_end);
event_table = event_table(event_mask, :);

sample_start = max(0, floor(chunk_start * fs));
sample_end = min(numel(audio_waveform), ceil(chunk_end * fs));
if sample_end <= sample_start
    error('build_gui:ChunkOutOfRange', 'the requested audio chunk falls outside the waveform.');
end
audio_segment = audio_waveform(sample_start + 1:sample_end);
time_vector = ((sample_start:sample_end - 1)' ) ./ fs;

%% data processing
smoothed_rate = calculate_smoothed_rate(spike_times, KERNEL_SD_S, time_vector);

%% gui construction defines the figure, layout, axes, and slider shell.
fig = uifigure('Name', 'Spiking SpectroVis', 'Color', 'w');
main_layout = uigridlayout(fig, [2, 1]);
main_layout.RowHeight = {'1x', 30};
main_layout.ColumnWidth = {'1x'};

plot_layout = tiledlayout(main_layout, 7, 1, 'TileSpacing', 'none', 'Padding', 'compact');
plot_layout.Layout.Row = 1;
plot_layout.Layout.Column = 1;

slider = uislider(main_layout);
slider.Layout.Row = 2;
slider.Layout.Column = 1;

%% plot the spectrogram, spike raster, smoothed rate, and event indicator panels.
ax1 = nexttile(plot_layout, [3, 1]);
[s, f, t] = spectrogram(audio_segment, 256, 128, 256, fs);
power_db = 20 * log10(abs(s) + eps);
frequency_axis = f;
if frequency_axis(1) == 0
    if numel(frequency_axis) > 1 && frequency_axis(2) > 0
        frequency_axis(1) = frequency_axis(2) / 2;
    else
        frequency_axis(1) = 1;
    end
end
imagesc(ax1, t + time_vector(1), frequency_axis, power_db);
axis(ax1, 'xy');
colormap(ax1, 'turbo');
set(ax1, 'YScale', 'log');
ylabel(ax1, 'Frequency (Hz)');
xticklabels(ax1, []);

ax2 = nexttile(plot_layout);
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

target_time = time_vector;
ax3 = nexttile(plot_layout, [2, 1]);
plot(ax3, target_time, smoothed_rate, 'LineWidth', 1.5);
ylabel(ax3, 'Firing Rate (Hz)');
xticklabels(ax3, []);

ax4 = nexttile(plot_layout);
hold(ax4, 'on');
indicator_color = [0.85, 0.15, 0.15];
for event_idx = 1:height(event_table)
    onset = max(event_table.Onset(event_idx), chunk_start);
    offset = min(event_table.Offset(event_idx), chunk_end);
    patch(ax4, [onset, offset, offset, onset], [0.2, 0.2, 0.8, 0.8], ...
        indicator_color, 'FaceAlpha', 0.4, 'EdgeColor', 'none');
end
hold(ax4, 'off');
ylim(ax4, [0, 1]);
yticks(ax4, []);
yticklabels(ax4, []);
box(ax4, 'off');
xlabel(ax4, 'Time (s)');

%% synchronize axes and configure the slider limits for the forthcoming callback.
linkaxes([ax1, ax2, ax3, ax4], 'x');
available_span = chunk_end - chunk_start;
viewport_width = min(VIEWPORT_WIDTH_S, available_span);
if viewport_width <= 0
    viewport_width = available_span;
end
slider_min = chunk_start;
slider_max = max(slider_min, chunk_end - viewport_width);
slider.Limits = [slider_min, slider_max];
slider.Value = slider_min;
slider.ValueChangedFcn = @slider_callback;

xlim(ax1, [slider.Value, slider.Value + viewport_width]);
fig.UserData = struct('axes', [ax1, ax2, ax3, ax4], 'viewport_width', viewport_width, ...
    'slider', slider, 'chunk', DATA_CHUNK_S);

%% add light grids to the frequency and rate panels for reference.
for grid_axis = [ax1, ax3]
    grid(grid_axis, 'on');
end
