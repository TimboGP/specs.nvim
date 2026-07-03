# Telescope Pickers Specification

## Purpose
The visual, list-style core of specs.nvim: Telescope pickers over OpenSpec changes
and specs, each with a live markdown preview pane and in-picker action mappings.
Telescope is an optional dependency — these pickers degrade gracefully when it is
absent. This capability also owns the Telescope extension registration that enables
`:Telescope specs changes` and `:Telescope specs specs`.

## Requirements

### Requirement: Optional Telescope Dependency
The pickers SHALL soft-depend on telescope.nvim: when Telescope cannot be required,
each picker SHALL notify the user and no-op rather than erroring.

#### Scenario: Telescope missing
- GIVEN telescope.nvim is not installed
- WHEN the user invokes the changes or specs picker
- THEN a WARN notification states that telescope.nvim is required for pickers
- AND no picker window opens

### Requirement: Changes Picker
The changes picker SHALL list active changes from `openspec list --json`, displaying
a status glyph, the change name, and a completed/total task count per entry.

#### Scenario: Rendering change entries
- GIVEN one or more active changes exist
- WHEN the user opens the changes picker
- THEN each entry shows a status glyph (`✓` complete, `◐` in-progress, `○` no-tasks, `•` otherwise), the change name, and a `completed/total` task count

#### Scenario: No changes present
- GIVEN the project has no active changes
- WHEN the user opens the changes picker
- THEN an INFO notification reports that no changes were found and no picker opens

### Requirement: Specs Picker
The specs picker SHALL list specifications from `openspec list --specs --json`, and
SHALL tolerate spec entries that are either plain strings or objects carrying a
`name`/`id` field.

#### Scenario: Rendering spec entries
- GIVEN one or more specs exist
- WHEN the user opens the specs picker
- THEN each entry is displayed prefixed with `▪` using the spec's name (from a string entry, or from an object's `name`/`id`)

#### Scenario: No specs present
- GIVEN the project has no specs
- WHEN the user opens the specs picker
- THEN an INFO notification reports that no specs were found and no picker opens

### Requirement: Markdown Preview
Each picker SHALL render the highlighted item's `openspec show <name>` markdown in
the previewer pane, keeping the buffer's filetype set to markdown.

#### Scenario: Previewing the highlighted item
- WHEN the selection moves to an item in a picker
- THEN the preview buffer is populated with that item's `openspec show` markdown output
- AND falls back to `(no preview)` when the show output is empty

#### Scenario: Preview buffer discarded before render
- GIVEN the preview buffer has been closed before the async show completes
- WHEN the show result arrives
- THEN the result is dropped without error

### Requirement: In-Picker Actions
Within a picker, `<CR>` SHALL open the item's full markdown detail in a split, and
mapped keys SHALL invoke validate, status, archive, and new-change actions on the
selection. Archive and new-change SHALL refresh the picker on completion.

#### Scenario: Opening detail
- WHEN the user presses `<CR>` on an entry
- THEN the picker closes and the item's full `openspec show` markdown opens in a scratch split

#### Scenario: Validate and status from the picker
- WHEN the user presses the validate mapping (`<C-v>` by default) or the status mapping (`<C-s>` by default)
- THEN the picker closes and the selected item is validated, or its artifact status is shown

#### Scenario: Archive refreshes the list
- WHEN the user presses the archive mapping (`<C-a>` by default) and confirms
- THEN the change is archived and the picker is closed and reopened to reflect the change

#### Scenario: New change refreshes the list
- WHEN the user presses the new-change mapping (`<C-n>` by default) and supplies a name
- THEN the change is created and the picker is closed and reopened to reflect it

#### Scenario: Action keys are configurable
- GIVEN the user overrode `picker.mappings` in setup
- WHEN a picker is opened
- THEN the configured keys are bound (in both insert and normal mode) instead of the defaults

### Requirement: Telescope Extension Registration
The plugin SHALL register a Telescope extension named `specs` exporting `changes`
and `specs`, and its setup SHALL merge extension-level config into the plugin's
picker configuration.

#### Scenario: Extension exports
- GIVEN telescope.nvim is installed
- WHEN the `specs` extension is loaded
- THEN `:Telescope specs changes` and `:Telescope specs specs` invoke the respective pickers

#### Scenario: Extension config merge
- WHEN Telescope loads the extension with a non-empty config table
- THEN that config is merged into the plugin's `picker` configuration via setup
