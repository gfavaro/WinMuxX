# Workspace overview

The overview presents the current project's existing user-facing workspace slots,
including empty slots, using the sidebar's ordering and the existing display
ownership policy. One nonactivating panel is created per connected display.
Opening and closing are presentation actions: the CLI and direct key bindings
skip the command session's layout, reconciliation and persistence passes.
Selection uses the established workspace/focus path and revalidates window object
identity, process, native state, project and display ownership after AX suspension.

## Rendering and resource bounds

Saved pre-parking frames locate inactive-workspace windows. Unit-coordinate frames
are persisted with each frozen window, with optional decoding for older snapshots.
Restoration preserves them through startup parking until the first visible layout
or successful reveal. Floating reveal reuses the restored unit position rather
than the native startup cleanup position. One-pixel parking strips are rejected as geometry. Visible
workspaces prefer current cached native/layout frames over earlier snapshots. Native minimized,
hidden-application and full-screen state are distinct from WinMuxX parking.
Eligibility explicitly excludes hidden apps even with automatic unhiding enabled.
Only active tab members are shown. No real window is repositioned for capture.
Unknown geometry stays in a separate window menu rather than receiving a made-up
position. Known geometry with unavailable pixels keeps an app icon and outline.

The compositor shares a capture gate with horizontal swipe snapshots. The gate
keeps its permit across asynchronous suspension, including cancelled native work.
Each producer owns one capture slot until the native call returns; cancellation
cannot create an unbounded number of native calls. Overview pages supply one
request at a time, with generation and card invalidation checks before publication.
Native stacking order is read once per opening; unavailable ranks preserve model
order behind known ranks.

Each display has twelve cards per page. Cards are captured only on first visit in
a session, with selected cards first. Retained images are at most 640 by 360 pixels
and share a 32 MiB overview budget across displays. The existing swipe cache has
its separate 64 MiB cap. Native source images, graphics contexts, SwiftUI/AppKit
layers and GPU resources are additional transient costs; these limits are not a
claim that process memory grows by only 32 MiB.

Leaving a page evicts its images. Returning to an evicted page shows placeholders
until the next opening. Closed, minimized, hidden or otherwise changed windows
invalidate the affected static card rather than starting a live capture stream.
Dismissal immediately cancels capture publication and removes session observers.
A short rise/zoom/fade uses the same spring and configured duration as horizontal
workspace navigation. Frozen card images remain until closing completes, then
panel contents and images release. Reopening first tears down the retiring panel,
so rapid toggles cannot accumulate closing presentations or image budgets.
Interrupted motion starts closing from the current presentation values. Reduce
Motion, disabled animations, or zero swipe duration skip motion.
The backdrop uses the native frosted HUD material without a custom dark scrim.
One native blur surface exists per display, rather than one per thumbnail.
Captions and outlines use adaptive system colors; Increase Contrast strengthens
outlines and makes captions opaque. Reduce Transparency uses an opaque system background. The
backdrop moves with the existing gesture presentation. There are no overview
polling timers or stationary display callbacks.

## Input and lifetime

Workspace/window buttons expose selected accessibility traits and labels. Keyboard
selection updates accessibility focus, including a workspace-level fallback for a
window without saved geometry. Native editors keep composition and editing commands;
modified shortcuts are not treated as plain grid navigation. Arrow keys, Tab and
Shift-Tab retain the workspace/window navigation behavior.

`workspace-overview [show|hide|toggle]` defaults to toggle. The optional
`workspace-overview.three-finger-up` setting defaults to false. Both gesture
features use one raw-touch callback/router, with axis locking before dispatch.
An overview swipe starts only after each of the three contacts moves in the same
vertical direction; a resting finger plus two moving fingers does not trigger it.
Once recognized, progress remains continuous and can reverse before release.
The private raw-touch source runs if either feature is enabled. With motion enabled,
vertical gestures present the overview during the swipe: upward motion reveals it,
and downward motion withdraws it. Progress updates only existing panel layers;
there are no per-frame model publications, layouts, screenshots or window writes.
Release settles from the current presentation using the shared spring, configured
duration and bounded release velocity. Short reversed/cancelled opening gestures
dismiss their provisional session; cancelled closing gestures settle the same
session back open. Invalid contacts and reset cancel the interaction rather than
triggering a late open. With motion disabled, gestures retain release-only actions. Downward dismissal has a shorter threshold and remains
available whenever the overview is open, including command-opened sessions with
upward activation disabled. Raw touch starts on demand for those sessions and
stops after dismissal when neither gesture feature otherwise needs it.
macOS's own Mission Control gesture must be configured separately by the user.

Project/display changes, native Mission Control, native Space changes, sleep,
session deactivation, runtime disablement and activating another app dismiss the
presentation. Focus-follows-mouse is suspended and the sidebar is temporarily hidden while it
is open; dismissal restores the configured sidebar presentation. There is no
cross-project browsing, native full-screen Space selection or window dragging.

## Validation

Automated coverage includes command/config parsing, native-state filters, saved
geometry and overlap hit testing, current-project/display ownership, keyboard
navigation, feature-flag combinations, contact/axis arbitration, cancellation
that ignores native task cancellation, static capture counts, pagination, a shared
image budget, synthetic rendering, native panel teardown and 1,000 controller
open/close cycles. Tests inject capture/navigation services; they do not certify
physical trackpad feel, native capture latency or multi-display desktop behavior.

A synthetic rendered fixture is written to `.build/workspace-overview-fixture.png`
by the focused test. Native desktop results and measurements must be recorded
separately; no battery-life or leak-free claim follows from the automated suite.

## Native capture leak found during validation

The first installed implementation (build 84) used the existing legacy capture
API. After native cycles, allocation-stack logging traced growing rectangle
`NSMutableDictionary` allocations to `SLWindowListCreateImage` →
`SLSWindowListCreateImageProxying` → `CGRectCreateDictionaryRepresentation` on
macOS 27.2. A fresh instrumented process reported zero leaks before the workload
and 64 allocations / 5,632 bytes afterward. Small panel/hosting/render probes did
not reproduce those allocations. These are separate from controller retain cycles.

The overview now uses [ScreenCaptureKit single-frame screenshots](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager/captureimage(contentfilter:configuration:completionhandler:))
on macOS 14 and later. It queries shareable window descriptors once per opening,
includes parked windows, requests thumbnail-sized output, and clears descriptors
on dismissal. Failed modern captures use placeholders, not the leaking legacy
fallback. macOS 13 retains the existing capture implementation. Other existing
features that call the legacy API are outside this overview change.

Native build 85 reported zero detected leaks after five overview cycles, and again
after twenty additional cycles with all workspace previews populated, using
`MallocStackLogging` and `leaks --fullStacks`. This is a bounded workload result,
not a whole-application or long-term leak guarantee. The legacy capture path on
macOS 13 and physical multi-display/trackpad behavior still need native validation.

Build 86 native validation preserved all seven saved frames across a normal app
restart and displayed populated inactive cards before visiting those workspaces.
Selecting the floating System Settings window restored all four frame components
to the saved geometry (within the existing two-point tolerance). Exact window
selection and Escape passed; assignments, focus, workspace, config and persistent
signing identity were preserved. A fresh instrumented build 86 process reported
zero detected leaks before and after twenty openings held for two seconds each.
The final installed process was restarted without allocation-stack instrumentation.


## Gesture modules and native drift recovery

`WorkspaceGestureCoordinator` wires configuration and presentation demand to the
native source and router. Recognition, the bounded mailbox, and native device
lifecycle live in separate `WorkspaceTouchRecognizer`, `WorkspaceTouchMailbox`,
and `RawWorkspaceTouch` files. `WorkspaceGestureAnimation` owns the shared spring;
`WorkspaceOverviewPresentation` owns panel motion and `WorkspaceOverviewInteraction`
connects progress/cancellation to the controller session. Startup, reload and runtime
enablement only delegate lifecycle work to the coordinator.

`HiddenWorkspaceWindowRecovery` separately coalesces native geometry notifications
for parked windows. Native bounds are checked before any AX read. Safely parked
windows need no state fetch. Actual drift triggers one bounded native-state read,
including when the cache is empty; generation and window-identity checks reject
stale results. Fullscreen, minimized, hidden-app or newly visible windows are
excluded. Events arriving during that read coalesce into one follow-up batch.
Confirmed unsafe normal windows request a placement-only refresh,
without adopting native focus, enumerating applications, or changing workspace
selection. A pending focus/tab/activation reconciliation takes priority over that
repair. Subscriptions follow the managed-window set, even when borders are disabled.
This closes an event-delivery gap that can leave a background window onscreen
until its delayed or missing AX notification is reconciled. It does not establish
that Safari can never produce a visible frame before a native notification arrives.
