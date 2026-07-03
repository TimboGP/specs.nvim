# Change Operations Specification

## Purpose
The non-picker operations that render OpenSpec data or drive the CLI: showing an
item as markdown, validating, inspecting artifact status, creating a change, and
archiving a change. These operations are invoked both from `:Specs` subcommands and
from in-picker mappings, and they render results into read-only scratch buffers.
The `:Specs view` dashboard is a separate capability — see dashboard-view — but
reuses these operations for its validate/status/archive/new and preview actions.

## Requirements

### Requirement: Scratch Buffer Rendering
Rendered output SHALL open in a read-only, throwaway scratch buffer that is easy to
dismiss.

#### Scenario: Scratch buffer properties
- WHEN an operation renders output into a scratch buffer
- THEN the buffer is `nofile`, `bufhidden=wipe`, non-modifiable, and named with a `specs://…` identifier
- AND pressing `q` in normal mode closes the window

### Requirement: Show Item
The show operation SHALL render `openspec show <name>` markdown in a scratch buffer,
optionally passing an item `--type`, and SHALL warn when no name is supplied.

#### Scenario: Showing a named item
- WHEN the user shows an item by name
- THEN `openspec show <name>` runs and its markdown is rendered in a scratch buffer titled `specs://show/<name>`

#### Scenario: Type disambiguation
- GIVEN an item type (`change` or `spec`) is provided
- WHEN the item is shown
- THEN `--type <type>` is passed to `openspec show`

#### Scenario: Missing name
- WHEN show is invoked with an empty or missing name
- THEN a WARN notification reports the missing item name and nothing is rendered

### Requirement: Validate
The validate operation SHALL validate one named item, or all items when given no
name or the sentinel `all`, and SHALL render a per-item pass/fail report while
defensively tolerating single-item and `--all` JSON shapes.

#### Scenario: Validate all
- WHEN validate is invoked with no name or with `all`
- THEN `openspec validate --all --json` runs and each item is listed with `✓` (valid) or `✗` (invalid) and any issue messages

#### Scenario: Validate one
- WHEN validate is invoked with a specific name
- THEN `openspec validate <name> --json` runs and its result is rendered

#### Scenario: All valid
- GIVEN every validated item is valid
- WHEN the report is produced
- THEN an INFO notification reports that validation passed

### Requirement: Artifact Status
The status operation SHALL render the artifact-completion checklist for a change
from `openspec status --change <name> --json`, and SHALL warn when no name is given.

#### Scenario: Rendering status
- WHEN status is invoked for a change
- THEN the change name, schema name, and overall completeness are shown, followed by each artifact with a status icon, status label, and id
- AND artifacts with unmet dependencies list them as `(needs: …)`

#### Scenario: Missing name
- WHEN status is invoked with an empty or missing name
- THEN a WARN notification reports the missing change name and nothing is rendered

### Requirement: New Change
The new-change operation SHALL create a change via `openspec new change <name>`,
prompting for a name when none is supplied, and SHALL run an optional callback on
success.

#### Scenario: Named creation
- WHEN new-change is invoked with a name
- THEN `openspec new change <name>` runs, an INFO notification confirms creation, and any `on_done` callback fires

#### Scenario: Prompted creation
- WHEN new-change is invoked without a name
- THEN the user is prompted via `vim.ui.input` and the entered name is used (an empty response cancels)

#### Scenario: Creation failure
- WHEN `openspec new change <name>` exits non-zero (e.g. the change already exists)
- THEN no artifact is opened and no `on_done` callback fires

### Requirement: Jump Into a New Change
After a change is successfully created, the new-change operation SHALL open its
first ready, non-glob artifact (typically `proposal.md`) in a new tab, seeded from
that schema's template file when the artifact is still empty.

#### Scenario: Opening the first artifact
- WHEN a change is created successfully
- THEN `openspec status --change <name> --json` is queried for its artifacts
- AND the first artifact with status `ready` and a concrete (non-glob) `outputPath` is opened in a new tab at `openspec/changes/<name>/<outputPath>`

#### Scenario: Seeding from the schema template
- GIVEN the opened artifact's buffer is still empty
- WHEN it is opened
- THEN `openspec templates --schema <schemaName> --json` resolves that artifact's template file, and its contents seed the buffer

#### Scenario: Never clobbering existing content
- GIVEN the target buffer already has content
- WHEN seeding is attempted
- THEN the buffer is left untouched

### Requirement: Archive Change
The archive operation SHALL require confirmation before archiving a change via
`openspec archive <name> -y`, invalidate the project-root cache afterward, and run
an optional callback on success.

#### Scenario: Confirmed archive
- WHEN archive is invoked and the user selects `Yes`
- THEN `openspec archive <name> -y` runs, the root cache is cleared, an INFO notification confirms it, and any `on_done` callback fires

#### Scenario: Declined archive
- WHEN archive is invoked and the user does not select `Yes`
- THEN nothing is archived

#### Scenario: Missing name
- WHEN archive is invoked with an empty or missing name
- THEN a WARN notification reports the missing change name and nothing happens
