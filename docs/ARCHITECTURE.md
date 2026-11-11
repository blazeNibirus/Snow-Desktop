# Architecture

`SnowCore` owns bounded particle and snowbank arrays in top-left screen-local points. A 120 Hz fixed-step loop handles ambient drift, swept downward collision, finite bank depth, angle-of-repose relaxation, inertia from changes in support velocity, and debris gravity. Frame catch-up is capped at 100 ms. Snowbanks are finite height fields at roughly four-point spacing, at most 1,024 cells each. They are not rigid-body meshes.

Each display has one transparent, click-through AppKit overlay and one display-linked `SnowView`. Shared tiny sprite textures avoid a full-screen CPU rasterizer. Reusable `CALayer` objects represent falling particles; `CAShapeLayer` strips represent banks. Particle count across displays is bounded, and the layer pool shrinks after bursts. Window metadata is sampled at 10 Hz while idle and 30 Hz during a mouse drag; Dock accessibility geometry is sampled at most 24 Hz. This is a tradeoff between support tracking latency and process wakeups.

The front-to-back Core Graphics list defines occlusion intervals. Fullscreen / maximized rectangles are excluded from accumulation and subtracted from the overlay mask. Metadata contains no captured window image. Accessibility is used only to inspect Dock item roles, positions and sizes. Dock calls have a short timeout and a bounded tree traversal. Without permission, no substitute screen-wide floor is guessed.

ScreenSaver runs as a separate `.saver` bundle in Apple's host and shares the physics source at build time. It never requests Accessibility or inspects application windows. Its appearance is a dark background with passive snowfall; its settings live in `ScreenSaverDefaults`.

Native preferences are persisted as versioned JSON in the application's defaults. Startup registration uses `SMAppService.mainApp`. Disabling the desktop effect stops display links and hides overlays; closing the popover stops its preview. Workspace sleep/session and supplementary distributed lock/saver notifications suspend desktop rendering. OS window isolation, not notification delivery, enforces the lock-screen boundary.

Platform-specific concerns live in `SnowDesktop`; a Windows port must implement its own window enumeration, shell/taskbar surfaces, refresh synchronization and settings UI. No Windows behavior is claimed by this repository.
