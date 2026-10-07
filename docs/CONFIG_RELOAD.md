# Configuration reload

WinMuxX keeps TOML and the existing `auto-reload-config` setting. When enabled, the configuration directory is observed so saving in place, replacing the file atomically, or recreating a deleted file continues to work. Symbolic links are observed at both the link and the resolved target; each reload updates the observed paths.

Content events are grouped with a 200 ms debounce. Reloads are serialized, including manual commands. A save during an automatic reload requests a subsequent reload rather than canceling the application in progress. Changes during startup wait until workspace initialization finishes. Turning auto reload off cancels pending automatic work and stops observation.

An unreadable, missing or invalid selected file preserves the current configuration, mode, workspace assignments and enabled state. Defaults are used when starting without a custom configuration; an automatic reload never falls back to defaults because a file was temporarily removed. Saving a corrected file clears the error. Automatic notifications suppress consecutive identical errors, while manual reload commands still report each failure. Diagnostics and the unified config log retain the failure.

The tests use isolated temporary directories to exercise real FSEvents and never edit the personal configuration file.
