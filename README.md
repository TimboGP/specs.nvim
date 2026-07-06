# specs.nvim

A Neovim front-end for spec-driven development — drive it without leaving your editor.
Browse changes/features and specs in visual
[Telescope](https://github.com/nvim-telescope/telescope.nvim) pickers or a persistent,
undotree-style navigable dashboard, validate and inspect artifact status, and create
changes/features.

It supports two backends and **auto-detects** which one a project uses:

- **[OpenSpec](https://github.com/Fission-AI/OpenSpec)** — shells out to the `openspec`
  CLI and renders its `--json` output.
- **[spec-kit](https://github.com/github/spec-kit)** — reads the project filesystem
  directly (`specs/NNN-*/` feature folders + `.specify/memory/`), since spec-kit has no
  query CLI. See [Backends](#backends) for the mapping and caveats.

The plugin owns no spec logic of its own — it renders whatever the active backend exposes.

## Requirements

- Neovim **≥ 0.10** (uses `vim.system`)
- A backend, depending on your project:
  - **OpenSpec**: the [`openspec`](https://github.com/Fission-AI/OpenSpec) CLI on your `PATH`.
  - **spec-kit**: nothing required for browsing (pure filesystem). The
    [`specify`](https://github.com/github/spec-kit) CLI is only used by `:Specs init`, and
    spec-kit's own `.specify/scripts/bash/create-new-feature.sh` is used by `:Specs new`
    when present (with a pure-Lua fallback).
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) — **optional**, but
  required for the `changes`/`specs` list pickers. Everything else works without it.

## Install

### lazy.nvim

```lua
{
  "TimboGP/specs.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" }, -- optional, enables the pickers
  cmd = "Specs",
  keys = {
    { "<leader>oc", "<cmd>Specs changes<cr>", desc = "Specs: changes" },
    { "<leader>os", "<cmd>Specs specs<cr>",   desc = "Specs: specs" },
  },
  opts = {}, -- lazy calls require("specs").setup(opts) for you
}
```

> `opts = {}` is enough — lazy runs `setup()` on the `specs` module automatically.
> Telescope auto-loads the extension the first time you run `:Telescope specs …`, so
> an explicit `require("telescope").load_extension("specs")` is optional.

### From a local clone (no GitHub remote)

If the plugin lives in a local checkout, point lazy at it with `dir`:

```lua
{
  dir = "~/Repositories/specs.nvim", -- path to your local clone
  dependencies = { "nvim-telescope/telescope.nvim" },
  cmd = "Specs",
  keys = {
    { "<leader>oc", "<cmd>Specs changes<cr>", desc = "Specs: changes" },
    { "<leader>os", "<cmd>Specs specs<cr>",   desc = "Specs: specs" },
  },
  opts = {},
}
```

Alternatively, set a dev path in your lazy setup
(`{ dev = { path = "~/Repositories" } }`) and use `{ "TimboGP/specs.nvim", dev = true }`.

### packer.nvim

```lua
use({
  "TimboGP/specs.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("specs").setup({})
    pcall(require("telescope").load_extension, "specs")
  end,
})
```

## Usage

### `:Specs` command

| Command | Action |
|---------|--------|
| `:Specs` / `:Specs changes` | Open the **changes** picker |
| `:Specs specs` | Open the **specs** picker |
| `:Specs show <name>` | Show a change/spec as markdown in a scratch buffer |
| `:Specs validate [name\|all]` | Validate one item, or all with no arg — issues open in the quickfix list |
| `:Specs status <name>` | Artifact completion checklist for a change |
| `:Specs new [name]` | Create a change/feature (prompts if no name), then open its first artifact |
| `:Specs archive <name>` | Archive a change (OpenSpec only; asks to confirm) |
| `:Specs diff <name>` | Diff a change/feature (see below — meaning differs per backend) |
| `:Specs view` | Open the navigable changes/specs dashboard |
| `:Specs init [args]` | Initialize a project with the active backend's CLI |

Subcommands and change/feature names tab-complete. Behavior adapts to the detected
backend — see [Backends](#backends) for the full mapping.

`:Specs new` doesn't stop at creating the directory: it opens the first ready artifact
(OpenSpec `proposal.md`; spec-kit `spec.md`) in a new tab, seeded from the backend's
template so you land on a filled-in skeleton instead of a blank file.

`:Specs diff <name>` on **OpenSpec** opens one tab per capability the change touches, each
a Neovim diff (`vert diffsplit`) between the current `openspec/specs/<capability>/spec.md`
and the change's proposed spec delta (a not-yet-existing capability diffs against an empty
buffer, showing the whole delta as added). On **spec-kit** it shows a `git diff` of the
feature folder in a scratch buffer.

### Dashboard

`:Specs view` opens a persistent, collapsible tree panel over changes and specs —
undotree-style navigation instead of a one-shot printout. It stays open until you
close it.

| Key | Action |
|-----|--------|
| `<CR>` | Change/spec: open/update the preview pane. Section/tasks: toggle expand/collapse. Task: toggle its checkbox |
| `o` / `<Tab>` | Toggle expand/collapse of the node under the cursor |
| `d` | On a change: open its spec delta diff (see `:Specs diff` above) |
| `R` | Refresh from the CLI (keeps expand state) |
| `q` | Close the dashboard and its preview pane |

Expanding a change/feature lazily fetches its artifact checklist from the active backend.
Once unblocked, the `tasks` artifact expands further into its individual `- [ ]`
checkboxes — toggling one edits and saves `tasks.md` directly (through an
already-open buffer for it, if there is one) without leaving the dashboard.
The `validate`/`status`/`archive`/`new` picker mappings (below) also work here, on
whichever change/spec is under the cursor.

### Telescope

```
:Telescope specs changes
:Telescope specs specs
```

Inside a picker:

| Key | Action |
|-----|--------|
| `<CR>` | Open full markdown detail in a split |
| `<C-v>` | Validate the selected item |
| `<C-s>` | Show artifact status |
| `<C-a>` | Archive the selected change (confirm) |
| `<C-n>` | Create a new change |

The right-hand preview pane shows the rendered `show` markdown for the highlighted item.

## Backends

The plugin resolves a backend per project by walking up from the current buffer:

- an `openspec/` directory → **OpenSpec**
- a `.specify/` directory (or a `specs/` directory holding numbered feature folders) →
  **spec-kit**

If both are found, the closer (deeper) one wins; ties go to OpenSpec. Force a single
backend with `provider = "openspec"` or `"speckit"` in `setup()`.

The same `:Specs` commands, dashboard, and pickers work against both. Because spec-kit's
model differs from OpenSpec's, some concepts are mapped and a few commands are repurposed:

| Concept / command | OpenSpec | spec-kit |
|---|---|---|
| "Changes" section | `openspec` changes | feature folders under `specs/NNN-*/` |
| Second section | capability **Specs** | **Constitution** + `.specify/memory/*.md` |
| Artifact status | `openspec status --change` | synthesized from file existence (`spec`→`plan`→`tasks`→…) |
| `tasks` checkboxes | tasks.md `- [ ]`/`- [x]` | tasks.md `- [ ]`/`- [x]` (identical) |
| `show` | `openspec show` | reads `spec.md` (or the memory doc) |
| `validate` | schema issues → quickfix | missing-artifact check → quickfix (`spec.md` error, `plan/tasks.md` warnings) |
| `new` | `openspec new change <name>` | `create-new-feature.sh --json "<desc>"` if present, else Lua-created `specs/NNN-slug/` |
| `diff` | proposed spec deltas vs current specs | `git diff` of the feature folder |
| `archive` | `openspec archive` | not supported (notifies; delete the folder manually) |
| `init` | `openspec init` | `specify init` |

spec-kit's actual authoring workflow runs through its AI-agent slash commands
(`/speckit.specify`, `/speckit.plan`, `/speckit.tasks`, …); this plugin surfaces and
navigates the artifacts those commands produce.

## Configuration

`setup()` is optional. Defaults:

```lua
require("specs").setup({
  provider = "auto",  -- "auto" (detect per project), "openspec", or "speckit"
  cmd = "openspec",   -- OpenSpec executable name or absolute path
  speckit = {
    cmd = "specify",         -- spec-kit CLI (only used by :Specs init)
    specs_dir = "specs",     -- feature folders live here, relative to the root
    memory_dir = ".specify/memory", -- constitution + memory docs
  },
  notify = true,      -- emit [specs] notifications
  picker = {
    mappings = {     -- in-picker action keymaps (insert + normal)
      validate = "<C-v>",
      status   = "<C-s>",
      archive  = "<C-a>",
      new      = "<C-n>",
    },
  },
  dashboard = {
    split = "topleft 40vsplit", -- window command hosting the tree panel
  },
})
```

## Health

```
:checkhealth specs
```

Reports the configured `provider` mode, whether the `openspec` and `specify` binaries are
found, whether telescope.nvim is available, and which backend the current directory
resolves to (OpenSpec or spec-kit) — including, for spec-kit, whether the
`create-new-feature.sh` helper is present.

## Lua API

```lua
local os_ = require("specs")
os_.changes()               -- open the changes picker
os_.specs()                 -- open the specs picker
os_.show("add-user-auth")   -- markdown detail
os_.validate("add-user-auth")
os_.status("add-user-auth")
os_.new_change("my-change")
os_.archive("add-user-auth")
```

## License

MIT
