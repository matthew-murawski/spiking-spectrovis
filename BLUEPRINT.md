Project Blueprint: spiking_spectrovis
1. Project Goal
The spiking_spectrovis project is a MATLAB-based interactive visualization tool designed for the rapid "visual prospecting" of neurophysiological and audio data. Its purpose is to solve the workflow bottleneck of tedious, manual data labeling by providing a fast, intuitive way to scan for periods of interest (e.g., neural responses to specific auditory events). The user can quickly identify candidate "hotspots" that warrant further, more detailed quantitative analysis.

2. Core Architecture
The application is designed as a programmatic MATLAB GUI, avoiding the use of binary .mlapp files from App Designer to ensure clarity and ease of version control. The architecture follows a principle of separating data handling from the user interface logic.

Data Utilities (/src): A collection of pure, independent functions responsible for loading and processing data. These form the testable foundation of the application.

Main Application (main.m): A single, user-facing script that serves as the entry point and controller. It is responsible for:

Handling user interaction (e.g., file selection).

Orchestrating calls to the data utility functions.

Programmatically building the GUI figure and all its components.

Implementing the interactive logic via a local callback function.

3. Repository Structure & Component Breakdown
The project will be organized into the following file structure:

spiking_spectrovis/
├─ main.m
├─ src/
│  ├─ load_spike_data.m
│  ├─ load_label_data.m
│  └─ calculate_smoothed_rate.m
├─ tests/
│  └─ test_data_utilities.m
├─ README.md
└─ BLUEPRINT.md
Component Responsibilities:
main.m

Role: Main application entry point and controller.

Responsibilities:

Presents uigetfile dialogs to the user for data selection.

Calls the src functions to load and process the selected data.

Builds the uifigure, tiledlayout, uiaxes, and uislider.

Manages the plotting of all data streams.

Contains the slider_callback as a local function to handle interactive scrolling.

src/load_spike_data.m

Role: Data utility.

Input: File path to a .mat file.

Output: A column vector of spike times.

src/load_label_data.m

Role: Data utility.

Input: File path to a .txt file.

Output: A MATLAB table of event data.

src/calculate_smoothed_rate.m

Role: Data utility.

Inputs: A vector of spike times, a time vector for the x-axis, and a kernel standard deviation.

Output: A vector containing the smoothed firing rate in Hz.

tests/test_data_utilities.m

Role: Unit testing script.

Responsibilities: Verifies the correctness of all functions within the src/ directory by using synthetic data and assert statements.

4. Phased Implementation Plan
The project will be built incrementally according to the following phases. This ensures a testable, stable foundation at each step.

Phase 1: Foundational Utilities (The "Model")
Implement src/load_spike_data.m.

Implement src/load_label_data.m.

Implement src/calculate_smoothed_rate.m.

Implement tests/test_data_utilities.m to create synthetic data and verify that all src/ functions produce the expected outputs. This phase is complete when all tests pass.

Phase 2: GUI Scaffolding & Static Visualization (The "View")
Create main.m.

Implement the GUI layout creation: uifigure, tiledlayout, uiaxes, and the uislider. Do not implement the callback yet.

Integrate the Phase 1 functions: Add logic to main.m to call the data loaders and processors.

Implement the plotting logic: Draw the spectrogram, raster, rate, and event patches for the entire loaded data chunk into the GUI's axes.

Link the axes' x-dimensions using linkaxes.

Set the initial xlim to display the first viewport.

Milestone: At the end of this phase, running main.m (with hardcoded file paths) should produce a fully rendered, but non-interactive, GUI.

Phase 3: Adding Interactivity (The "Controller")
Implement the slider_callback as a local function within main.m.

The callback's sole responsibility is to read the slider's new value and update the xlim of the linked axes.

Attach the callback to the slider's ValueChangedFcn property.

Milestone: The application is now fully interactive. The slider correctly scrolls the viewport through the data.

Phase 4: Finalization & User Interface
Replace hardcoded file paths in main.m with uigetfile dialogs to allow the user to select their data dynamically.

Add basic error handling for file selection (e.g., user cancellation).

Add comments and polish the main.m script into a final, user-ready application.

Milestone: The project is feature-complete and meets all requirements.
