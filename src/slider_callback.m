function slider_callback(src, event)
% slider_callback adjusts the linked axes viewport in response to slider movement.

%% locate the figure and pull the axes plus viewport width from stored metadata.
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

%% compute the new limits based on the current slider value.
new_start_time = event.Value;
new_xlim = [new_start_time, new_start_time + user_data.viewport_width];

%% apply the limits to the first axis; linked axes will follow automatically.
if ~isempty(user_data.axes) && all(isvalid(user_data.axes))
    xlim(user_data.axes(1), new_xlim);
end
end
