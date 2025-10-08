function EventFlipbookExplorer(session_num, channel_num)
% section: overview
% this function loads neural and audio data, finds burst events, and boots up the flipbook gui focused on the first event.

% section: configuration parameters
% we establish duration, detection thresholds, and viewport width so the rest of the function can reference consistent settings.
DATA_DURATION_S = 900;
THRESHOLD_STD_FACTOR = 3.0;
EVENT_SEPARATION_S = 2.0;
VIEWPORT_WIDTH_S = 10.0;
KERNEL_SD_S = 0.050;
AUDIO_BASE_PATH = '/Volumes/Zhao/JHU_Data/Recording_Colony_Neural/M93A';
MAX_EVENT_WINDOWS = 50;

% section: ensure utility path
% we mirror view_session by adding the src folder so shared helpers stay visible while we run.
this_file = mfilename('fullpath');
project_root = fileparts(this_file);
utilities_dir = fullfile(project_root, 'src');
if ~isfolder(utilities_dir)
    error('EventFlipbookExplorer:MissingSrcDir', 'expected src directory not found beside EventFlipbookExplorer.m.');
end
addpath(utilities_dir);
cleanup_path = onCleanup(@() rmpath(utilities_dir)); %#ok<NASGU>

% section: load raw session data
% we reuse the automated loader from view_session to grab audio, spike, and event data for the requested identifiers.
fprintf('loading audio data for session S%d...\n', session_num);
audio_filename = sprintf('voc_M93A_c_S%d.wav', session_num);
audio_filepath = fullfile(AUDIO_BASE_PATH, audio_filename);
if ~isfile(audio_filepath)
    error('EventFlipbookExplorer:AudioMissing', 'audio file not found: %s', audio_filepath);
end

audio_info = audioinfo(audio_filepath);
fs = audio_info.SampleRate;
samples_to_read = min(audio_info.TotalSamples, round(fs * DATA_DURATION_S));
[audio_waveform, fs] = audioread(audio_filepath, [1, samples_to_read]);
if size(audio_waveform, 2) > 1
    audio_waveform = mean(audio_waveform, 2);
end
audio_waveform = audio_waveform(:);

fprintf('loading spike and behavior data...\n');
[U, behavior] = load_session('M93A', session_num);

channel_idx = find(U.unit_idx == channel_num, 1);
if isempty(channel_idx)
    error('EventFlipbookExplorer:ChannelMissing', 'channel %d not found in session S%d. available channels: %s', ...
        channel_num, session_num, num2str(U.unit_idx));
end
spike_times_all = U.spike_times{channel_idx};

onsets = behavior.times(:, 1);
offsets = behavior.times(:, 2);
if isfield(behavior, 'labels')
    labels = behavior.labels;
    event_table_all = table(onsets, offsets, labels, 'VariableNames', {'Onset', 'Offset', 'Label'});
else
    event_table_all = table(onsets, offsets, 'VariableNames', {'Onset', 'Offset'});
end

% section: trim data chunk
% we align audio, spikes, and events to the requested duration so further processing stays bounded.
chunk_start = 0;
chunk_end = min(DATA_DURATION_S, numel(audio_waveform) / fs);
if chunk_end <= chunk_start
    error('EventFlipbookExplorer:InvalidChunk', 'requested data chunk is empty.');
end

spike_mask = (spike_times_all >= chunk_start) & (spike_times_all <= chunk_end);
spike_times = spike_times_all(spike_mask);

event_mask = (event_table_all.Offset > chunk_start) & (event_table_all.Onset < chunk_end);
event_table = event_table_all(event_mask, :);

time_vector = (0:numel(audio_waveform) - 1)' ./ fs;

% section: derive firing rate and spectrogram settings
% we smooth spike trains into a firing rate and hang on to the spectrogram kernel parameters for per-event rendering.
smoothed_rate = calculate_smoothed_rate(spike_times, KERNEL_SD_S, time_vector);
window_size = 512;
window_func = hann(window_size, 'periodic');
nfft = 1024;
overlap = window_size / 2;

% section: detect burst events
% we locate burst onsets via the new engine so the gui can jump straight to the first significant spike cluster.
event_times = find_burst_events(smoothed_rate, time_vector, THRESHOLD_STD_FACTOR, EVENT_SEPARATION_S);

% section: prioritize event list
% we keep only the top firing-rate peaks so the gui never allocates more than fifty windows at once.
if ~isempty(event_times)
    event_indices = zeros(size(event_times));
    for idx = 1:numel(event_times)
        candidate_idx = find(time_vector >= event_times(idx), 1, 'first');
        if isempty(candidate_idx)
            candidate_idx = numel(time_vector);
        end
        event_indices(idx) = candidate_idx;
    end
    event_scores = smoothed_rate(event_indices);
    if numel(event_times) > MAX_EVENT_WINDOWS
        [~, sort_order] = sort(event_scores, 'descend');
        keep_positions = sort(sort_order(1:MAX_EVENT_WINDOWS));
        event_times = event_times(keep_positions);
        event_indices = event_indices(keep_positions);
        event_scores = event_scores(keep_positions); %#ok<NASGU>
    end
else
    event_indices = zeros(0, 1);
end

% section: prepare event windows
% we cache 10 second windows around each event so the gui only stores data it will actually render.
available_span = chunk_end - chunk_start;
viewport_width = min(VIEWPORT_WIDTH_S, available_span);
if viewport_width <= 0
    viewport_width = available_span;
end
if viewport_width <= 0
    viewport_width = 1;
end

event_chunks = struct('window', {}, 'spectrogram_T', {}, 'spectrogram_F', {}, ...
    'spectrogram_db', {}, 'spectrogram_max_db', {}, 'spike_times', {}, ...
    'rate_time', {}, 'rate_values', {}, 'produced_calls', {});

dynamic_range = 80;
gain_offset = 40;
global_max_db = -inf;

produced_calls_table = event_table([],:);
has_labels = ismember('Label', event_table.Properties.VariableNames);
if has_labels
    produced_mask = contains(event_table.Label, 'prod', 'IgnoreCase', true);
    produced_calls_table = event_table(produced_mask, :);
end

if ~isempty(event_times)
    num_samples = numel(audio_waveform);
    for idx = 1:numel(event_times)
        target_time = event_times(idx);
        half_window = viewport_width / 2;
        window_start = max(chunk_start, target_time - half_window);
        window_end = min(chunk_end, target_time + half_window);

        current_span = window_end - window_start;
        if current_span < viewport_width
            deficit = viewport_width - current_span;
            window_start = max(chunk_start, window_start - deficit / 2);
            window_end = min(chunk_end, window_start + viewport_width);
            current_span = window_end - window_start;
            if current_span < viewport_width
                window_start = max(chunk_start, window_end - viewport_width);
            end
        end

        if window_end <= window_start
            window_end = min(chunk_end, window_start + viewport_width);
            if window_end <= window_start
                window_start = max(chunk_start, window_end - viewport_width);
            end
        end

        sample_start = max(1, floor(window_start * fs) + 1);
        sample_end = min(num_samples, ceil(window_end * fs));
        if sample_end < sample_start
            sample_end = sample_start;
        end

        time_slice = time_vector(sample_start:sample_end);
        rate_slice = smoothed_rate(sample_start:sample_end);
        spike_mask_local = (spike_times >= time_slice(1)) & (spike_times <= time_slice(end));
        spike_slice = spike_times(spike_mask_local);

        audio_slice = audio_waveform(sample_start:sample_end);
        [S_slice, F_slice, T_slice_rel] = spectrogram(audio_slice, window_func, overlap, nfft, fs);
        S_power_slice = abs(S_slice) .^ 2;
        S_db_slice = 10 * log10(S_power_slice + eps);
        T_slice = T_slice_rel + time_slice(1);

        finite_mask_slice = isfinite(S_db_slice);
        if any(finite_mask_slice(:))
            slice_max_db = max(S_db_slice(finite_mask_slice));
        else
            slice_max_db = -inf;
        end
        global_max_db = max(global_max_db, slice_max_db);

        chunk_struct = struct();
        chunk_struct.window = [time_slice(1), time_slice(end)];
        chunk_struct.spectrogram_T = T_slice;
        chunk_struct.spectrogram_F = F_slice;
        chunk_struct.spectrogram_db = S_db_slice;
        chunk_struct.spectrogram_max_db = slice_max_db;
        chunk_struct.spike_times = spike_slice;
        chunk_struct.rate_time = time_slice;
        chunk_struct.rate_values = rate_slice;
        if ~isempty(produced_calls_table)
            overlap_mask = (produced_calls_table.Offset > window_start) & (produced_calls_table.Onset < window_end);
            if any(overlap_mask)
                window_calls = produced_calls_table(overlap_mask, :);
                window_calls.Onset = max(window_calls.Onset, window_start);
                window_calls.Offset = min(window_calls.Offset, window_end);
            else
                window_calls = produced_calls_table([],:);
            end
        else
            window_calls = produced_calls_table;
        end
        chunk_struct.produced_calls = window_calls;

        event_chunks(idx) = chunk_struct; %#ok<AGROW>
    end
end

audio_waveform = [];
smoothed_rate = [];
time_vector = [];

% section: construct gui layout
% we assemble a two-row layout with plots on top and navigation controls ready for the next development stage.
fig_title = sprintf('EventFlipbookExplorer: S%d | Unit %d', session_num, channel_num);
fig = uifigure('Name', fig_title, 'Color', 'w');
main_layout = uigridlayout(fig, [2, 1]);
main_layout.RowHeight = {'1x', 60};
main_layout.ColumnWidth = {'1x'};

plot_layout = tiledlayout(main_layout, 8, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
plot_layout.Layout.Row = 1;
plot_layout.Layout.Column = 1;

control_layout = uigridlayout(main_layout, [1, 3]);
control_layout.Layout.Row = 2;
control_layout.Layout.Column = 1;
control_layout.ColumnWidth = {'fit', '1x', 'fit'};
control_layout.RowHeight = {'fit'};
control_layout.Padding = [10, 10, 10, 10];
control_layout.ColumnSpacing = 15;
control_layout.RowSpacing = 0;

previous_button = uibutton(control_layout, 'Text', 'Previous');
previous_button.Layout.Row = 1;
previous_button.Layout.Column = 1;
previous_button.ButtonPushedFcn = @prev_button_callback;
previous_button.Enable = 'off';

status_label = uilabel(control_layout, 'Text', '');
status_label.Layout.Row = 1;
status_label.Layout.Column = 2;
status_label.HorizontalAlignment = 'center';
status_label.FontWeight = 'bold';

next_button = uibutton(control_layout, 'Text', 'Next');
next_button.Layout.Row = 1;
next_button.Layout.Column = 3;
next_button.ButtonPushedFcn = @next_button_callback;
next_button.Enable = 'off';

% section: initialize axes
% we label the axes up front so precomputed event windows can populate them without redrawing the layout.
ax_spectrogram = nexttile(plot_layout, [5, 1]);
set(ax_spectrogram, 'YDir', 'normal');
colormap(ax_spectrogram, 'hot');
ylabel(ax_spectrogram, 'Frequency (Hz)');
xticklabels(ax_spectrogram, []);

ax_raster = nexttile(plot_layout, [1, 1]);
ylim(ax_raster, [0, 1]);
yticks(ax_raster, []);
yticklabels(ax_raster, []);
box(ax_raster, 'off');
xticklabels(ax_raster, []);

ax_rate = nexttile(plot_layout, [2, 1]);
ylabel(ax_rate, 'Firing Rate (Hz)');
xlabel(ax_rate, 'Time (s)');
box(ax_rate, 'off');
grid(ax_rate, 'on');

ax_calls = nexttile(plot_layout, [1, 1]);
ylim(ax_calls, [0, 1]);
yticks(ax_calls, []);
yticklabels(ax_calls, []);
box(ax_calls, 'off');
xlabel(ax_calls, 'Time (s)');

% section: store app state
% we keep all handles and data in user data so callbacks can find them later.
axes_array = [ax_spectrogram, ax_raster, ax_rate, ax_calls];
linkaxes(axes_array, 'x');

available_span = chunk_end - chunk_start;
viewport_width = min(VIEWPORT_WIDTH_S, available_span);
if viewport_width <= 0
    viewport_width = available_span;
end
if viewport_width <= 0
    viewport_width = 1;
end

spectrogram_defaults = struct('max_db', global_max_db, 'dynamic_range', dynamic_range, ...
    'gain_offset', gain_offset);

app_state = struct();
app_state.handles = struct('axes_all', axes_array, 'spectrogram', ax_spectrogram, ...
    'raster', ax_raster, 'rate', ax_rate, 'calls', ax_calls, ...
    'previous_button', previous_button, 'next_button', next_button, ...
    'status_label', status_label, 'figure', fig);
app_state.data = struct('event_table', event_table, 'chunk_limits', [chunk_start, chunk_end], ...
    'viewport_width', viewport_width, 'event_chunks', event_chunks, ...
    'spectrogram_defaults', spectrogram_defaults);
app_state.events = struct('times', event_times(:), 'current_index', 1);

fig.UserData = app_state;

% section: initialize view
% we render the very first event so users see a meaningful window when the gui opens.
update_view(fig);

fprintf('EventFlipbookExplorer loaded session S%d channel %d.\n', session_num, channel_num);
end

function update_view(fig)
% section: overview
% this helper pulls state from the figure, syncs axis limits around the active event, and updates control text.

% section: retrieve app state
% we guard against missing or malformed state so the gui does not error out during early stages.
if nargin < 1 || ~isvalid(fig)
    return;
end
app_state = fig.UserData;
if ~isstruct(app_state) || ~isfield(app_state, 'handles') || ~isfield(app_state, 'data') || ~isfield(app_state, 'events')
    return;
end

axes_array = app_state.handles.axes_all;
status_label = app_state.handles.status_label;
previous_button = app_state.handles.previous_button;
next_button = app_state.handles.next_button;
chunk_limits = app_state.data.chunk_limits;
event_times = app_state.events.times;
event_chunks = app_state.data.event_chunks;
spectrogram_defaults = app_state.data.spectrogram_defaults;

if isempty(event_times)
    render_empty_axes(app_state.handles, chunk_limits);
    if isvalid(status_label)
        status_label.Text = 'no events found.';
    end
    if isvalid(previous_button)
        previous_button.Enable = 'off';
    end
    if isvalid(next_button)
        next_button.Enable = 'off';
    end
    return;
end

current_index = app_state.events.current_index;
if isempty(current_index) || ~isscalar(current_index) || ~isfinite(current_index)
    current_index = 1;
end
current_index = max(1, min(numel(event_times), round(current_index)));

if current_index <= numel(event_chunks)
    active_chunk = event_chunks(current_index);
    render_event_chunk(app_state.handles, active_chunk, spectrogram_defaults);
else
    render_empty_axes(app_state.handles, chunk_limits);
end

if isvalid(status_label)
    status_label.Text = sprintf('Event: %d of %d', current_index, numel(event_times));
end

if isvalid(previous_button)
    if current_index > 1
        previous_button.Enable = 'on';
    else
        previous_button.Enable = 'off';
    end
end

if isvalid(next_button)
    if current_index < numel(event_times)
        next_button.Enable = 'on';
    else
        next_button.Enable = 'off';
    end
end

app_state.events.current_index = current_index;
fig.UserData = app_state;
end

function next_button_callback(src, ~)
% section: overview
% this callback advances the active event index and refreshes the gui.

% section: retrieve state
% we walk up to the top-level figure and pull the stored app state before mutating anything.
fig = src.Parent.Parent.Parent;
if ~isvalid(fig)
    return;
end
app_state = fig.UserData;
if ~isstruct(app_state) || ~isfield(app_state, 'events')
    return;
end

% section: mutate index
% we bump the current index forward and stash the result before redrawing.
app_state.events.current_index = app_state.events.current_index + 1;
fig.UserData = app_state;

% section: refresh view
% we ask the existing helper to clamp and redraw so all controls stay in sync.
update_view(fig);
end

function prev_button_callback(src, ~)
% section: overview
% this callback backs up to the previous event and triggers a redraw.

% section: retrieve state
% we recover the stored figure state via the parent chain just like the next handler.
fig = src.Parent.Parent.Parent;
if ~isvalid(fig)
    return;
end
app_state = fig.UserData;
if ~isstruct(app_state) || ~isfield(app_state, 'events')
    return;
end

% section: mutate index
% we decrement the current index then store and display the updated view.
app_state.events.current_index = app_state.events.current_index - 1;
fig.UserData = app_state;

% section: refresh view
% we delegate to the existing viewer logic so axes limits and controls update together.
update_view(fig);
end

function render_event_chunk(handles, chunk, spectrogram_defaults)
% section: overview
% this helper draws a cached 10 second slice onto the spectrogram, raster, firing rate, and call axes so we never have to pull in the full recording.

% section: validate handles
% we make sure the axes still exist before trying to update them, because closing the window will invalidate the graphics objects.
axes_array = handles.axes_all;
if isempty(axes_array) || any(~isvalid(axes_array))
    return;
end

ax_spectrogram = handles.spectrogram;
ax_raster = handles.raster;
ax_rate = handles.rate;
ax_calls = handles.calls;

% section: draw spectrogram
% we refresh the spectrogram with the precomputed power slice and reuse the project-wide color scaling to keep contrast consistent.
cla(ax_spectrogram);
if ~isempty(chunk.spectrogram_db)
    imagesc(ax_spectrogram, chunk.spectrogram_T, chunk.spectrogram_F, chunk.spectrogram_db);
else
    imagesc(ax_spectrogram, chunk.window, [0, 1], zeros(2));
end
set(ax_spectrogram, 'YDir', 'normal');
colormap(ax_spectrogram, 'hot');
ylabel(ax_spectrogram, 'Frequency (Hz)');
xticklabels(ax_spectrogram, []);
if ~isempty(chunk.spectrogram_F)
    ylim(ax_spectrogram, [min(chunk.spectrogram_F), max(chunk.spectrogram_F)]);
end
max_db = chunk.spectrogram_max_db;
if ~isfinite(max_db)
    max_db = spectrogram_defaults.max_db;
end
if ~isfinite(max_db)
    max_db = 0;
end
clim(ax_spectrogram, [max_db - spectrogram_defaults.dynamic_range, ...
    max_db - spectrogram_defaults.dynamic_range + spectrogram_defaults.gain_offset]);
xlim(ax_spectrogram, chunk.window);

% section: draw raster
% we rebuild the spike raster inside the window so navigation never touches spikes outside the cached range.
cla(ax_raster);
line_half_height = 0.05;
line_thickness = 2.0;
if ~isempty(chunk.spike_times)
    hold(ax_raster, 'on');
    for spike_idx = 1:numel(chunk.spike_times)
        spike_time = chunk.spike_times(spike_idx);
        line(ax_raster, [spike_time, spike_time], [0.5 - line_half_height, 0.5 + line_half_height], ...
            'Color', 'k', 'LineWidth', line_thickness);
    end
    hold(ax_raster, 'off');
else
    hold(ax_raster, 'off');
end
ylim(ax_raster, [0, 1]);
yticks(ax_raster, []);
yticklabels(ax_raster, []);
box(ax_raster, 'off');
xticklabels(ax_raster, []);
xlim(ax_raster, chunk.window);

% section: draw firing rate
% we plot the smoothed rate slice so the axes stay in lockstep with the spectrogram and raster.
cla(ax_rate);
if ~isempty(chunk.rate_time)
    plot(ax_rate, chunk.rate_time, chunk.rate_values, 'LineWidth', 1.5);
end
ylabel(ax_rate, 'Firing Rate (Hz)');
xlabel(ax_rate, 'Time (s)');
box(ax_rate, 'off');
grid(ax_rate, 'on');
xlim(ax_rate, chunk.window);

cla(ax_calls);
if ~isempty(chunk.produced_calls)
    hold(ax_calls, 'on');
    call_color = [0.2, 0.45, 0.85];
    for call_idx = 1:height(chunk.produced_calls)
        onset = chunk.produced_calls.Onset(call_idx);
        offset = chunk.produced_calls.Offset(call_idx);
        patch(ax_calls, [onset, offset, offset, onset], [0.1, 0.1, 0.9, 0.9], ...
            call_color, 'FaceAlpha', 0.5, 'EdgeColor', 'none');
    end
    hold(ax_calls, 'off');
else
    hold(ax_calls, 'off');
end
ylim(ax_calls, [0, 1]);
yticks(ax_calls, []);
yticklabels(ax_calls, []);
box(ax_calls, 'off');
xlim(ax_calls, chunk.window);
xlabel(ax_calls, 'Time (s)');

linkaxes(axes_array, 'x');

linkaxes(axes_array, 'x');
end

function render_empty_axes(handles, chunk_limits)
% section: overview
% this helper clears out the axes when no events are available so the gui stays tidy instead of showing stale data.

% section: validate handles
% we bail gracefully if the window closed and the axes no longer exist.
axes_array = handles.axes_all;
if isempty(axes_array) || any(~isvalid(axes_array))
    return;
end

ax_spectrogram = handles.spectrogram;
ax_raster = handles.raster;
ax_rate = handles.rate;

% section: clear plots
% we reset each axis to an empty state but keep labels intact for consistency.
cla(ax_spectrogram);
colormap(ax_spectrogram, 'hot');
ylabel(ax_spectrogram, 'Frequency (Hz)');
xticklabels(ax_spectrogram, []);
xlim(ax_spectrogram, chunk_limits);

cla(ax_raster);
ylim(ax_raster, [0, 1]);
yticks(ax_raster, []);
yticklabels(ax_raster, []);
box(ax_raster, 'off');
xticklabels(ax_raster, []);
xlim(ax_raster, chunk_limits);

cla(ax_rate);
ylabel(ax_rate, 'Firing Rate (Hz)');
xlabel(ax_rate, 'Time (s)');
box(ax_rate, 'off');
grid(ax_rate, 'on');
xlim(ax_rate, chunk_limits);

cla(ax_calls);
ylim(ax_calls, [0, 1]);
yticks(ax_calls, []);
yticklabels(ax_calls, []);
box(ax_calls, 'off');
xlabel(ax_calls, 'Time (s)');
xlim(ax_calls, chunk_limits);

linkaxes(axes_array, 'x');
end
