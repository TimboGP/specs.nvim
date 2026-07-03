# CLI Integration Specification

## Purpose
The single boundary that shells out to the `openspec` CLI. specs.nvim owns no spec
logic of its own — it invokes `openspec`, parses `--json` output, and surfaces
errors. This capability covers OpenSpec project-root detection and caching,
asynchronous execution, JSON decoding, and error notification.

## Requirements

### Requirement: Project Root Detection
The integration SHALL locate the OpenSpec project root by walking upward from a
starting directory (the current buffer's directory, falling back to the current
working directory) to find an `openspec/` directory, returning `nil` when none is
found.

#### Scenario: Root found upward
- GIVEN the current buffer sits somewhere beneath a directory containing `openspec/`
- WHEN the root is resolved
- THEN the directory containing `openspec/` is returned

#### Scenario: No root
- GIVEN no ancestor directory contains `openspec/`
- WHEN the root is resolved
- THEN `nil` is returned

#### Scenario: Empty starting directory falls back to cwd
- GIVEN the current buffer has no on-disk directory
- WHEN the root is resolved
- THEN detection starts from the current working directory

### Requirement: Root Cache
Resolved roots SHALL be cached per starting directory, and the cache SHALL be
clearable so layout changes are picked up.

#### Scenario: Cache hit
- GIVEN a starting directory whose root was already resolved
- WHEN the root is resolved again for that directory
- THEN the cached result is returned without walking the filesystem again

#### Scenario: Cache invalidation
- WHEN `clear_cache` is called
- THEN subsequent resolutions re-walk the filesystem
- AND the cache is cleared after `openspec init` and after archiving a change

### Requirement: Root Requirement Enforcement
Commands that operate on an existing project SHALL require a project root by
default, aborting with a helpful error when none is found, while callers MAY opt out
of the requirement.

#### Scenario: Missing root aborts
- GIVEN no OpenSpec project root exists and a run is made with the default requirement
- WHEN the command is attempted
- THEN it aborts, notifies at ERROR level with `Not in an OpenSpec project — run :Specs init`, and the callback receives that error

#### Scenario: Opting out of the root requirement
- GIVEN a caller passes `require_root = false` (as `:Specs init` does)
- WHEN the command runs
- THEN no root is required and execution proceeds

### Requirement: Asynchronous Execution
Commands SHALL run asynchronously via `vim.system` in text mode, delivering results
to callbacks on the main event loop.

#### Scenario: Async run
- WHEN a command runs
- THEN `openspec` is spawned with `vim.system` in text mode using the configured executable and resolved cwd
- AND the callback is invoked inside `vim.schedule` on the main loop

### Requirement: Error Surfacing
A non-zero exit SHALL be surfaced to the user and to the caller.

#### Scenario: Non-zero exit
- WHEN `openspec` exits with a non-zero code
- THEN the trimmed stderr (or a fallback `openspec exited with code <n>` message) is notified at ERROR level and passed to the callback as the error

### Requirement: JSON Mode
A JSON run SHALL append `--json` to the arguments and decode stdout, reporting a
parse failure rather than passing malformed data downstream.

#### Scenario: Successful decode
- WHEN a JSON run completes successfully
- THEN `--json` was appended and the decoded table is passed to the callback

#### Scenario: Decode failure
- WHEN stdout is not valid JSON
- THEN an ERROR notification reports the parse failure and the callback receives `nil` data

### Requirement: Configurable Executable
Every invocation SHALL use the configured executable name or path.

#### Scenario: Custom executable
- GIVEN `cmd` is set to an absolute path in configuration
- WHEN any command runs
- THEN that executable is used instead of the default `openspec`
