Project Blueprint: EventFlipbookExplorer
This project will be built in three distinct, self-contained stages. The architecture prioritizes separating the core data processing (the "engine") from the user interface, which makes testing and future modifications much easier.

Stage 1: The Event-Finding Engine.

Goal: Create a standalone, testable MATLAB function that can take a firing rate trace and return a list of statistically significant "burst" events. This is the core logic of the application.

Outcome: A pure function, find_burst_events.m, and a corresponding test script, test_event_finder.m, that verifies its correctness with synthetic data.

Stage 2: GUI Scaffolding & Initial View.

Goal: Build the main application function, EventFlipbookExplorer.m. This stage will handle all data loading, call the event-finding engine, and construct the complete GUI (plots, buttons, labels). It will then display the data window for the first detected event.

Outcome: A functional, but not yet interactive, application. When run, it should successfully find all events and display the view for "Event 1 of X".

Stage 3: Wiring the "Flipbook" Interactivity.

Goal: Implement the final interactive logic by creating the callback functions for the "Next" and "Previous" buttons and attaching them to the GUI.

Outcome: The final, fully interactive EventFlipbookExplorer application.

