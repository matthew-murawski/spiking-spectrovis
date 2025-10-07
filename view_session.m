function view_session(session_num, channel_num)
% view_session interactively visualizes neural and audio data for a session.
% view_session(session_num, channel_num) loads audio, spikes, and events for
% the requested identifiers and opens the spiking spectrovis gui.

%% configuration establishes fixed parameters and project paths up front.
AUDIO_BASE_PATH = '/Volumes/Zhao/JHU_Data/Recording_Colony_Neural/M93A';
DATA_DURATION_S = 600;
VIEWPORT_WIDTH_S = 30;
KERNEL_SD_S = 0.050;

%% ensure the src folder is on the path so shared utilities are available.
this_file = mfilename('fullpath');
project_root = fileparts(this_file);
utilities_dir = fullfile(project_root, 'src');
if ~isfolder(utilities_dir)
    error('view_session:MissingSrcDir', 'expected src directory not found beside view_session.m.');
end
addpath(utilities_dir);
cleanup_path = onCleanup(@() rmpath(utilities_dir)); %#ok<NASGU>

%% automated data loading pulls audio, spike, and behavior information.
fprintf('loading audio data for session S%d...\n', session_num);
audio_filename = sprintf('voc_M93A_c_S%d.wav', session_num);
audio_filepath = fullfile(AUDIO_BASE_PATH, audio_filename);
if ~isfile(audio_filepath)
    error('view_session:AudioMissing', 'audio file not found: %s', audio_filepath);
end

audio_info = audioinfo(audio_filepath);
fs = audio_info.SampleRate;
samples_to_read = min(audio_info.TotalSamples, round(fs * DATA_DURATION_S));
[audio_waveform, fs] = audioread(audio_filepath, [1, samples_to_read]);
if size(audio_waveform, 2) > 1
    audio_waveform = mean(audio_waveform, 2);
end

fprintf('loading spike and behavior data...\n');
[U, behavior] = load_session('M93A', session_num);

channel_idx = find(U.unit_idx == channel_num, 1);
if isempty(channel_idx)
    error('view_session:ChannelMissing', 'channel %d not found in session S%d. available channels: %s', ...
        channel_num, session_num, num2str(U.unit_idx));
end
spike_times_all = U.spike_times{channel_idx};

onsets = behavior.times(:, 1);
offsets = behavior.times(:, 2);
event_table_all = table(onsets, offsets, 'VariableNames', {'Onset', 'Offset'});

%% trim the dataset so spikes and events align with the audio chunk.
max_time = numel(audio_waveform) / fs;
chunk_start = 0;
chunk_end = min(DATA_DURATION_S, max_time);
if chunk_end <= chunk_start
    error('view_session:InvalidChunk', 'requested data chunk is empty.');
end

spike_mask = spike_times_all >= chunk_start & spike_times_all <= chunk_end;
spike_times = spike_times_all(spike_mask);

event_mask = (event_table_all.Offset > chunk_start) & (event_table_all.Onset < chunk_end);
event_table = event_table_all(event_mask, :);

time_vector = (0:numel(audio_waveform) - 1)' ./ fs;
smoothed_rate = calculate_smoothed_rate(spike_times, KERNEL_SD_S, time_vector);

%% prepare spectrogram parameters to mirror audacity configuration.
window_size = 512;
window_func = hann(window_size, 'periodic');
nfft = 1024;
overlap = window_size / 2;
[S, F, T] = spectrogram(audio_waveform, window_func, overlap, nfft, fs);
S_power = abs(S) .^ 2;
S_db = 10 * log10(S_power + eps);

%% gui construction mirrors the existing static plot layout with four panels.
fig_title = sprintf('Spiking SpectroVis: S%d | Unit %d', session_num, channel_num);
fig = uifigure('Name', fig_title, 'Color', 'w');
main_layout = uigridlayout(fig, [2, 1]);
main_layout.RowHeight = {'1x', 30};
main_layout.ColumnWidth = {'1x'};

plot_layout = tiledlayout(main_layout, 7, 1, 'TileSpacing', 'none', 'Padding', 'compact');
plot_layout.Layout.Row = 1;
plot_layout.Layout.Column = 1;

slider = uislider(main_layout);
slider.Layout.Row = 2;
slider.Layout.Column = 1;

%% plotting renders the spectrogram, spike raster, smoothed rate, and event strip.
ax1 = nexttile(plot_layout, [3, 1]);
imagesc(ax1, T + chunk_start, F, S_db);
set(ax1, 'YDir', 'normal');
set(ax1, 'YScale', 'linear');
ylim(ax1, [4000, 12000]);
colormap(ax1, 'hot');
finite_mask = isfinite(S_db);
if any(finite_mask(:))
    max_db = max(S_db(finite_mask));
else
    max_db = 0;
end
dynamic_range = 80;
gain_offset = 40;
clim(ax1, [max_db - dynamic_range, max_db - dynamic_range + gain_offset]);
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

ax3 = nexttile(plot_layout, [2, 1]);
plot(ax3, time_vector, smoothed_rate, 'LineWidth', 1.5);
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

%% interactivity links the axes, configures the slider, and stores state.
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
slider.ValueChangingFcn = @slider_callback;

xlim(ax1, [slider.Value, slider.Value + viewport_width]);
fig.UserData = struct('axes', [ax1, ax2, ax3, ax4], 'viewport_width', viewport_width);

for grid_axis = [ax1, ax3]
    grid(grid_axis, 'on');
end

fprintf('loaded session S%d channel %d.\n', session_num, channel_num);
end

%% local functions ------------------------------------------------------------
function slider_callback(src, event)
% slider_callback adjusts the linked axes viewport whenever the slider moves.

%% guard clauses keep the callback resilient to unexpected input states.
fig = src.Parent.Parent;
if ~isvalid(fig)
    return;
end
user_data = fig.UserData;
if ~isstruct(user_data) || ~isfield(user_data, 'axes') || ~isfield(user_data, 'viewport_width')
    return;
end

if isstruct(event)
    has_value = isfield(event, 'Value');
elseif isobject(event)
    has_value = isprop(event, 'Value');
else
    has_value = false;
end
if ~has_value
    return;
end

%% update the axes limits so the view tracks the slider position.
new_start_time = event.Value;
new_xlim = [new_start_time, new_start_time + user_data.viewport_width];
if ~isempty(user_data.axes) && all(isvalid(user_data.axes))
    xlim(user_data.axes(1), new_xlim);
end
end
