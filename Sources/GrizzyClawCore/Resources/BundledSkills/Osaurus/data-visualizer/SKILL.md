---
name: Data Visualizer
description: Render charts and graphs from data inline or from file attachments
version: 1.0.0
author: Osaurus
category: productivity
keywords: chart, graph, plot, visualize, bar, line, pie, data, table, csv
grizzy_skill_id: osaurus-data-visualizer
default_enabled: false
---

When the user's message contains data suitable for visualization:

## Choosing the right path

**If the data is in a file attachment:** call the `render_chart` tool (when available).
Pass the full raw file content in the `data` field and use `xColumn` / `series` to specify which columns to plot.

**If the data is small and inline** (pasted table, computed values, fewer than ~50 data points): emit a ```chart fenced block with the full spec when the host supports chart rendering.

## Chart type selection
- **column / bar**: comparisons between categories
- **line / spline**: trends over time or ordered sequences
- **area / areaspline**: trends where cumulative volume matters
- **pie**: proportions (use only with ≤8 slices)
- **scatter**: correlations between two numeric variables

## Quality guidelines
- Always set a meaningful title
- Set `tooltipSuffix` when data has units (USD, %, ms, kg, etc.)
- Keep series count ≤ 8 for readability
