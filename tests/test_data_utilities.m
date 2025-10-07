function tests = test_data_utilities
% test_data_utilities wires up unit tests for the data utility helpers.

%% register local tests so the matlab harness can discover them automatically.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
% setupOnce readies shared state for every test run in this suite.

%% locate the project directories and expose the src folder on the matlab path.
test_file = mfilename('fullpath');
if isempty(test_file)
    test_file = which('test_data_utilities');
end
if isempty(test_file)
    error('test_data_utilities:PathResolutionFailed', 'could not resolve test_data_utilities.m on the path.');
end
tests_dir = fileparts(test_file);
project_root = fileparts(tests_dir);
utilities_dir = fullfile(project_root, 'src');
if ~isfolder(utilities_dir)
    error('test_data_utilities:MissingUtilitiesDir', 'expected src directory was not found.');
end
addpath(utilities_dir);

testCase.TestData.ProjectRoot = project_root;
testCase.TestData.UtilitiesDir = utilities_dir;
end

function teardownOnce(testCase)
% teardownOnce removes shared fixtures after every test has executed.

%% drop the src directory from the matlab path to leave no lingering state.
if isfield(testCase.TestData, 'UtilitiesDir') && isfolder(testCase.TestData.UtilitiesDir)
    rmpath(testCase.TestData.UtilitiesDir);
end
end

function setup(testCase)
% setup prepares per-test fixtures before each individual test runs.

%% create a temporary directory so each test can write fixture files in isolation.
temp_root = tempname();
mkdir(temp_root);

testCase.TestData.TempRoot = temp_root;
end

function teardown(testCase)
% teardown cleans per-test fixtures once each test completes.

%% remove the temporary directory that held synthetic inputs to keep the disk tidy.
if isfield(testCase.TestData, 'TempRoot') && isfolder(testCase.TestData.TempRoot)
    rmdir(testCase.TestData.TempRoot, 's');
end
end

function testLoadSpikeDataReturnsColumnVector(testCase)
% testLoadSpikeDataReturnsColumnVector ensures mat files roundtrip cleanly.

%% craft a synthetic spike vector, persist it, and call the loader on that file.
spike_times = [0.1; 0.5; 0.55; 1.2];
spike_file = fullfile(testCase.TestData.TempRoot, 'test_spikes.mat');
save(spike_file, 'spike_times');
loaded_spikes = load_spike_data(spike_file);

%% confirm the loader preserved both numeric content and column orientation.
testCase.verifyEqual(loaded_spikes, spike_times);
end

function testLoadLabelDataParsesHeaderAndRows(testCase)
% testLoadLabelDataParsesHeaderAndRows checks text labels survive the parser.

%% write a header-plus-data example and invoke the loader on that synthetic file.
label_lines = ["onset_s\toffset_s\tlabel"; "0.5\t0.7\tproduced_call"];
label_file = fullfile(testCase.TestData.TempRoot, 'test_labels.txt');
fid = fopen(label_file, 'w');
cleaner = onCleanup(@() fclose(fid));
for line_idx = 1:numel(label_lines)
    fprintf(fid, '%s\n', label_lines(line_idx));
end
clear cleaner;
label_table = load_label_data(label_file);

%% confirm the loader skipped the header, parsed the fields, and preserved strings.
testCase.verifyEqual(height(label_table), 1);
testCase.verifyEqual(label_table.Onset, 0.5);
testCase.verifyEqual(label_table.Offset, 0.7);
testCase.verifyEqual(label_table.Label, string("produced_call"));
end

function testCalculateSmoothedRateProducesPositiveMass(testCase)
% testCalculateSmoothedRateProducesPositiveMass validates rate smoothing output.

%% compute a smoothed rate across a dense grid and inspect its basic properties.
spike_times = [0.1; 0.5; 0.55; 1.2];
time_vector = 0:0.001:2;
kernel_sd_s = 0.05;
smoothed_rate = calculate_smoothed_rate(spike_times, kernel_sd_s, time_vector);

testCase.verifyEqual(size(smoothed_rate), size(time_vector));
testCase.verifyGreaterThan(sum(smoothed_rate), 0);
testCase.verifyTrue(all(isfinite(smoothed_rate)), 'smoothed rate contains nonfinite values.');
end
