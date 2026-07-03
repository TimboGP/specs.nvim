# specs.nvim

A Neovim wrapper for the [OpenSpec](https://github.com/Fission-AI/OpenSpec) CLI — drive
spec-driven development without leaving your editor. Browse changes and specs in
visual [Telescope](https://github.com/nvim-telescope/telescope.nvim) pickers or a
persistent, undotree-style navigable dashboard, validate and inspect artifact status,
and create and archive changes.

The plugin is a thin wrapper: it shells out to `openspec`, parses its `--json` output, and
renders it. It owns no spec logic of its own.

## Requirements

- Neovim **≥ 0.10** (uses `vim.system`)
- The [`openspec`](https://github.com/Fission-AI/OpenSpec) CLI on your `PATH`
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
| `:Specs new [name]` | Create a change (prompts if no name), then open its first artifact |
| `:Specs archive <name>` | Archive a change (asks to confirm) |
| `:Specs diff <name>` | Diff a change's proposed spec deltas against the current specs |
| `:Specs view` | Open the navigable changes/specs dashboard |
| `:Specs init [args]` | Pass through to `openspec init` |

Subcommands and change names tab-complete.

`:Specs new` doesn't stop at creating the change directory: it opens the first
ready artifact (normally `proposal.md`) in a new tab, seeded from the active
schema's template (via `openspec templates`) so you land on a filled-in skeleton
instead of a blank file.

`:Specs diff <name>` opens one tab per capability the change touches, each a
Neovim diff (`vert diffsplit`) between the current `openspec/specs/<capability>/spec.md`
and the change's proposed `openspec/changes/<name>/specs/<capability>/spec.md`. A
capability that doesn't exist yet just diffs against an empty buffer, showing the
whole delta as added.

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

Expanding a change lazily fetches its artifact checklist (`openspec status --change`).
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

The right-hand preview pane shows the rendered `openspec show` markdown for the highlighted item.

## Configuration

`setup()` is optional. Defaults:

```lua
require("specs").setup({
  cmd = "openspec",  -- executable name or absolute path
  notify = true,     -- emit [openspec] notifications
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

Reports whether the `openspec` binary is found (and its version), whether telescope.nvim is
available, and whether the current directory is inside an OpenSpec project (an `openspec/`
directory found by walking up from the current buffer).

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
