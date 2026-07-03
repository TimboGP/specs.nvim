# Health Check Specification

## Purpose
The `:checkhealth specs` report. It tells the user whether the environment can run
the plugin: whether the `openspec` binary is on `PATH` (and its version), whether
telescope.nvim is available for the pickers, and whether the current directory is
inside an OpenSpec project. It works across both the modern and legacy Neovim health
APIs.

## Requirements

### Requirement: Binary Availability Check
The health check SHALL report whether the configured `openspec` executable is found,
including its version when available, and SHALL give installation guidance when it
is missing.

#### Scenario: Binary found
- GIVEN the configured `cmd` is executable
- WHEN the health check runs
- THEN it reports OK with the executable name and the output of `openspec --version` (or `unknown version` if the version call fails)

#### Scenario: Binary missing
- GIVEN the configured `cmd` is not on `PATH`
- WHEN the health check runs
- THEN it reports an error that the executable was not found, with advice to install OpenSpec or set `cmd` to an absolute path

### Requirement: Telescope Availability Check
The health check SHALL report whether telescope.nvim is available, since it gates
the pickers.

#### Scenario: Telescope present
- GIVEN telescope.nvim can be required
- WHEN the health check runs
- THEN it reports OK that pickers are enabled

#### Scenario: Telescope absent
- GIVEN telescope.nvim cannot be required
- WHEN the health check runs
- THEN it warns that the pickers are unavailable and advises installing telescope.nvim

### Requirement: Project Detection Check
The health check SHALL report whether the current working directory is inside an
OpenSpec project.

#### Scenario: Inside a project
- GIVEN the current directory is inside an OpenSpec project
- WHEN the health check runs
- THEN it reports OK with the resolved project root path

#### Scenario: Outside a project
- GIVEN the current directory is not inside an OpenSpec project
- WHEN the health check runs
- THEN it warns and advises running `:Specs init`

### Requirement: Health API Compatibility
The health check SHALL work against both the modern `vim.health` API and the legacy
`report_*` API.

#### Scenario: Selecting the health API
- WHEN the health module loads
- THEN it uses `vim.health.start`/`ok`/`warn`/`error` when available and falls back to the legacy `report_*` functions otherwise
