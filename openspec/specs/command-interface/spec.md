# Command Interface Specification

## Purpose
The `:Specs` user command and the `require("specs")` Lua API — the primary entry
points a user drives to browse, inspect, and manage OpenSpec changes and specs from
inside Neovim. This capability owns command registration, subcommand dispatch,
tab-completion, and the public Lua surface. It delegates all real work to the
change-operations, telescope-pickers, and cli-integration capabilities.

## Requirements

### Requirement: Command Registration
The plugin SHALL register a single `:Specs` user command when its `plugin/` file
loads, and SHALL guard against double registration and unsupported Neovim versions.

#### Scenario: Fresh load registers the command
- GIVEN a Neovim session at version 0.10 or newer where the plugin has not loaded
- WHEN the plugin file is sourced
- THEN a `:Specs` user command is created with `nargs = "*"` and a completion function
- AND the global `vim.g.loaded_specs` is set to `true`

#### Scenario: Repeated load is a no-op
- GIVEN `vim.g.loaded_specs` is already `true`
- WHEN the plugin file is sourced again
- THEN it returns immediately without re-registering the command

#### Scenario: Unsupported Neovim version aborts
- GIVEN a Neovim older than 0.10 (no `nvim-0.10` feature)
- WHEN the plugin file is sourced
- THEN it notifies at ERROR level that `specs.nvim requires Neovim >= 0.10`
- AND the `:Specs` command is not registered

### Requirement: Subcommand Dispatch
`:Specs <subcommand> [args]` SHALL route to the matching handler. With no
subcommand it SHALL open the changes picker, and an unrecognized subcommand SHALL
warn the user and list the available subcommands.

#### Scenario: No argument opens the changes picker
- GIVEN the user is inside an OpenSpec project
- WHEN the user runs `:Specs` with no arguments
- THEN the changes picker is opened

#### Scenario: Known subcommand routes to its handler
- WHEN the user runs `:Specs <sub>` where `<sub>` is a registered subcommand
- THEN the remaining arguments are sliced off and passed to that subcommand's handler

#### Scenario: Unknown subcommand warns
- WHEN the user runs `:Specs bogus`
- THEN a WARN notification reports the unknown subcommand
- AND it lists the available subcommands sorted alphabetically

### Requirement: Supported Subcommands
The command SHALL support the subcommands `changes`, `specs`, `show`, `validate`,
`status`, `new`, `archive`, `diff`, `view`, and `init`, each mapping to its
documented action.

#### Scenario: Listing subcommands
- WHEN the user runs `:Specs changes` or `:Specs specs`
- THEN the corresponding Telescope picker is opened

#### Scenario: Item subcommands take a name argument
- WHEN the user runs `:Specs show <name>`, `:Specs status <name>`, `:Specs archive <name>`, or `:Specs diff <name>`
- THEN the first argument is forwarded as the item name to the matching operation

#### Scenario: Validate accepts an optional target
- WHEN the user runs `:Specs validate` with no argument, or `:Specs validate all`
- THEN validation runs against all items
- AND WHEN a name is given, only that item is validated

#### Scenario: New accepts a bare name or a `change` prefix
- WHEN the user runs `:Specs new demo`
- THEN a change named `demo` is created
- AND WHEN the user runs `:Specs new change demo`, the same change `demo` is created

#### Scenario: Init passes through to the CLI
- WHEN the user runs `:Specs init` with any trailing arguments
- THEN those arguments are forwarded to `openspec init` without requiring an existing project root

### Requirement: Tab Completion
The command SHALL complete the subcommand on the first argument, and SHALL complete
OpenSpec item names on the second argument for the name-taking subcommands `show`,
`validate`, `status`, `archive`, and `diff`.

#### Scenario: Subcommand completion
- WHEN the user requests completion at the first argument position with a partial lead
- THEN only subcommands whose names begin with the lead are returned

#### Scenario: Item-name completion
- GIVEN the current directory is inside an OpenSpec project
- WHEN the user requests completion of the second argument for `show`, `validate`, `status`, `archive`, or `diff`
- THEN change names from `openspec list --json` that begin with the lead are returned

#### Scenario: No completion outside a project or for other subcommands
- WHEN the second argument is being completed for a subcommand that does not take a name, or no project root is found
- THEN an empty completion list is returned

### Requirement: Lua API Surface
The `require("specs")` module SHALL expose `setup` plus convenience accessors that
re-export the picker and action operations, so the plugin is scriptable without the
`:Specs` command.

#### Scenario: Accessing pickers and actions
- WHEN a user calls `require("specs").changes()` or `require("specs").specs()`
- THEN the corresponding picker function from the pickers module is invoked

#### Scenario: Accessing operations
- WHEN a user calls `require("specs").show(name)`, `.validate(name)`, `.status(name)`, `.new_change(name)`, or `.archive(name)`
- THEN the matching action from the actions module is invoked

#### Scenario: Setup returns merged configuration
- WHEN a user calls `require("specs").setup(opts)`
- THEN the merged configuration table is returned
