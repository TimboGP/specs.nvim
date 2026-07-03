# Configuration Specification

## Purpose
Plugin configuration: the optional `setup()` entry point, the default options, and
how user overrides are merged. Configuration governs the executable used, whether
notifications are emitted, the in-picker action keymaps, and the window command that
hosts the navigable dashboard panel.

## Requirements

### Requirement: Optional Setup
The plugin SHALL work without any call to `setup()`, applying defaults until one is
made, and `setup()` SHALL deep-merge user options over the defaults and return the
merged table.

#### Scenario: Defaults without setup
- GIVEN `setup()` has never been called
- WHEN configuration is read
- THEN the built-in defaults are in effect

#### Scenario: Merging user options
- WHEN `setup(opts)` is called
- THEN `opts` is deep-merged over a copy of the defaults, the result becomes the active configuration, and the merged table is returned

### Requirement: Default Options
The defaults SHALL be `cmd = "openspec"`, `notify = true`, picker action mappings
`validate = <C-v>`, `status = <C-s>`, `archive = <C-a>`, `new = <C-n>`, and
`dashboard.split = "topleft 40vsplit"`.

#### Scenario: Reading defaults
- WHEN the default configuration is inspected
- THEN `cmd` is `"openspec"`, `notify` is `true`, the four picker mappings hold their default keys, and `dashboard.split` is `"topleft 40vsplit"`

#### Scenario: Partial override preserves other defaults
- WHEN `setup({ cmd = "/usr/local/bin/openspec" })` is called
- THEN `cmd` is overridden while `notify`, the picker mappings, and `dashboard.split` retain their defaults

### Requirement: Notification Toggle
Notifications SHALL be emitted through a single helper that carries the `specs`
title and honors the `notify` option.

#### Scenario: Notifications enabled
- GIVEN `notify` is `true`
- WHEN a notification is emitted
- THEN `vim.notify` is called with the message, the given level, and the title `specs`

#### Scenario: Notifications silenced
- GIVEN `notify` is `false`
- WHEN a notification is emitted
- THEN nothing is shown
