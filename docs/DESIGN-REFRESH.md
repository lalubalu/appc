# Verdure design refresh

## Direction and baseline

Verdure should feel like a field guide for real local experiences: calm,
editorial and useful to students, families and young adults. The existing
palette is distinctive enough to keep. The largest visual problems in the
simulator baseline are the rounded display face, broad pill corners, heavy
double shadows and alternating accent colors on adjacent cards. The six-tab
bar also compresses labels. Baseline screenshots were taken on an iPhone 16
Plus simulator before D1-D4.

| Surface | Before | After |
| --- | --- | --- |
| Events / Discover | [before](design-refresh/before/events.png) | [after](design-refresh/after/events.png) |
| Explore | [before](design-refresh/before/explore.png) | Pending |
| Map | [before](design-refresh/before/map.png) | Pending |
| Collect | [before](design-refresh/before/collect.png) | Pending |
| Community | [before](design-refresh/before/community.png) | Pending |
| Profile | [before](design-refresh/before/profile.png) | Pending |

## Token contract

| Role | Decision |
| --- | --- |
| Display | iOS system serif (New York), dynamically scaled. Rubik remains body and numerals. |
| Surfaces | Keep sage cream, graphite forest and evergreen ink. |
| Screen accent | One contextual accent per surface; category colors only where they encode a category. |
| Shape | chip 10, sm 12, md 16, lg 20, xl 24, xxl 28, pill 999. |
| Depth | One soft outer shadow at offset 3 and blur 10; inner shading only inside inset fields and wells. |
| Motion | Keep purposeful transitions and pressed feedback; reduce ornamental movement when Reduce Motion is enabled. |

## Layout review questions for D5

- At larger Dynamic Type, are titles, card actions and the tab bar readable?
- Does the calmer depth preserve clear tap targets and hierarchy in light and dark mode?
- Are empty states honest when the live event index is empty?
- After the five-tab restructure, can every existing surface still be found?

The Events after image was captured with Computer on the iPhone 16 Plus
Simulator after the token commit and layout sweep. Moving attendance stats to
Profile freed the first screen for actual events and their empty state. With an
empty live event index, the screen honestly shows no event cards and the
network error. Its count, filters, and empty-state explanation are visible
above the tab bar.

The Profile and Collection summaries were also compressed in code, and the
Explore now starts with nearby places; level, points, and challenges stay in
Profile. Arbitrary accent rotation in badges, challenges, and community posts
was removed in favor of a consistent spruce accent. The Simulator build passed
after that sweep. Computer screenshot
capture subsequently timed out on
the Simulator window, so their after screenshots and visual accessibility
review remain pending. No physical-device contrast or Dynamic Type result is
claimed. Re-run the full screen matrix once the Simulator window is reachable.
