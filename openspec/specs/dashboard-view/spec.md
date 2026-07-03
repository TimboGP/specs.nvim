# Dashboard View Specification

## Purpose
The `:Specs view` navigable dashboard: a persistent, collapsible tree panel over
OpenSpec changes and specs, with a live markdown preview pane, in the spirit of
tree-navigation plugins like undotree. This capability owns the tree data model,
its rendering, and its buffer-local keymaps. It delegates data fetching to
cli-integration and reuses change-operations for validate/status/archive/new and
for rendering preview markdown.

## Requirements

### Requirement: Persistent Panel
`:Specs view` SHALL open a dedicated side window hosting a `nofile` buffer that
remains open — surviving expand/collapse and preview navigation — until the user
closes it, rather than a one-shot terminal command whose output disappears when
the job exits. Calling `:Specs view` again while the panel is open SHALL focus the
existing window instead of opening a duplicate.

#### Scenario: Opening the dashboard
- WHEN the user runs `:Specs view`
- THEN a side window opens (per `dashboard.split`) showing the changes/specs tree
- AND the window and its buffer remain open after subsequent navigation

#### Scenario: Reopening while already open
- GIVEN the dashboard window is already open
- WHEN the user runs `:Specs view` again
- THEN focus moves to the existing dashboard window instead of opening a second one

### Requirement: Tree Structure
The dashboard SHALL render two top-level, collapsible sections — "Changes" and
"Specs" — populated from `openspec list --json` and `openspec list --specs --json`
respectively. Each section SHALL show its item count in the label.

#### Scenario: Initial sections
- WHEN the dashboard is opened
- THEN a "Changes (N)" section and a "Specs (N)" section are rendered, both expanded by default, where N is the respective item count

### Requirement: Lazy Artifact Loading
Expanding a change node SHALL lazily fetch that change's artifact checklist via
`openspec status --change <name> --json` and render it as child rows, showing a
"loading…" placeholder until the fetch completes. Spec nodes SHALL NOT be
expandable.

#### Scenario: Expanding a change
- GIVEN a change node is collapsed and its children have not been loaded
- WHEN the user toggles it open
- THEN a "loading…" row is shown immediately
- AND once `openspec status --change` resolves, it is replaced with one row per artifact showing a status icon, the artifact id, and any missing dependencies

#### Scenario: Artifact fetch failure
- WHEN the status fetch for a change fails
- THEN a single informational row indicates status is unavailable, without erroring the whole panel

#### Scenario: Collapsing a node
- GIVEN an expanded node
- WHEN the user toggles it again
- THEN its children are hidden and its already-fetched data is retained for the next expand

### Requirement: Task Checkboxes
Once a change's `tasks` artifact is unblocked, it SHALL itself be expandable into
one leaf node per `- [ ]`/`- [x]` line parsed from its tasks.md, and selecting a
task node SHALL toggle its checkbox and persist the change immediately.

#### Scenario: Expanding tasks
- GIVEN a change's `tasks` artifact has status other than `blocked`
- WHEN the user toggles it open
- THEN each checkbox line in its tasks.md is rendered as a `[ ]`/`[x]` leaf row

#### Scenario: Blocked tasks are not expandable
- GIVEN a change's `tasks` artifact has status `blocked`
- WHEN the user views it
- THEN it is rendered as a plain, non-expandable row, same as any other artifact

#### Scenario: Toggling a task
- WHEN the user presses `<CR>` on a task row
- THEN its `- [ ]`/`- [x]` marker is flipped in tasks.md and the row's icon updates immediately

#### Scenario: Toggling through an open buffer
- GIVEN tasks.md is already open in a Neovim buffer
- WHEN a task in it is toggled from the dashboard
- THEN that buffer's line is edited and saved, rather than writing the file out from under it

#### Scenario: No tasks parsed
- GIVEN tasks.md contains no checkbox lines
- WHEN the `tasks` artifact is expanded
- THEN a single informational row indicates there are no tasks

### Requirement: Jump-to Preview
Selecting a change or spec node SHALL open (or reuse, if already open) a preview
window showing that item's `openspec show` markdown, updating in place on
subsequent selections rather than opening a new split each time.

#### Scenario: Selecting a change or spec
- WHEN the user presses `<CR>` on a change or spec node
- THEN a preview split opens (if not already open) showing that item's rendered markdown
- AND selecting a different item updates the same preview buffer's contents

#### Scenario: Selecting a section header
- WHEN the user presses `<CR>` on a section header or another expandable, non-leaf node (e.g. the `tasks` artifact)
- THEN the node toggles expanded/collapsed, the same as pressing the toggle key

### Requirement: Keymaps
The dashboard buffer SHALL provide `<CR>` (select/toggle/task-toggle, depending on
node kind), `o` and `<Tab>` (toggle expand/collapse), `d` (diff, on a change node),
`R` (refresh), and `q` (close), plus the configured `picker.mappings` for
validate/status/archive/new applied to the node under the cursor.

#### Scenario: Refreshing
- WHEN the user presses `R`
- THEN the tree data is re-fetched from the CLI
- AND previously expanded nodes remain expanded after the refresh

#### Scenario: Closing
- WHEN the user presses `q`
- THEN the dashboard window and its preview window (if open) both close

#### Scenario: Action mappings act on the node under the cursor
- WHEN the user presses the configured validate, status, or archive mapping with the cursor on a change or spec node
- THEN the corresponding action from change-operations runs against that node's name

#### Scenario: Diffing a change from the dashboard
- WHEN the user presses `d` with the cursor on a change node
- THEN the diff operation from change-operations runs against that change
- AND pressing `d` on a spec node or any other node kind does nothing
- AND pressing the new mapping prompts for a new change name and refreshes the tree on success
