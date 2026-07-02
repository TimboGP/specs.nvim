# openspec.nvim

A Neovim wrapper for the [OpenSpec](https://github.com/Fission-AI/OpenSpec) CLI — drive
spec-driven development without leaving your editor. Browse changes and specs in
visual [Telescope](https://github.com/nvim-telescope/telescope.nvim) pickers, validate and
inspect artifact status, create and archive changes, and pop the interactive `openspec view`
dashboard in a terminal split.

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
  "TimboGP/openspec.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" }, -- optional, enables the pickers
  cmd = "OpenSpec",
  keys = {
    { "<leader>oc", "<cmd>OpenSpec changes<cr>", desc = "OpenSpec: changes" },
    { "<leader>os", "<cmd>OpenSpec specs<cr>",   desc = "OpenSpec: specs" },
  },
  opts = {}, -- lazy calls require("openspec").setup(opts) for you
}
```

> `opts = {}` is enough — lazy runs `setup()` on the `openspec` module automatically.
> Telescope auto-loads the extension the first time you run `:Telescope openspec …`, so
> an explicit `require("telescope").load_extension("openspec")` is optional.

### packer.nvim

```lua
use({
  "TimboGP/openspec.nvim",
  requires = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("openspec").setup({})
    pcall(require("telescope").load_extension, "openspec")
  end,
})
```

## Usage

### `:OpenSpec` command

| Command | Action |
|---------|--------|
| `:OpenSpec` / `:OpenSpec changes` | Open the **changes** picker |
| `:OpenSpec specs` | Open the **specs** picker |
| `:OpenSpec show <name>` | Show a change/spec as markdown in a scratch buffer |
| `:OpenSpec validate [name\|all]` | Validate one item, or all with no arg |
| `:OpenSpec status <name>` | Artifact completion checklist for a change |
| `:OpenSpec new [name]` | Create a change (prompts if no name) |
| `:OpenSpec archive <name>` | Archive a change (asks to confirm) |
| `:OpenSpec view` | Open the interactive `openspec view` dashboard in a terminal |
| `:OpenSpec init [args]` | Pass through to `openspec init` |

Subcommands and change names tab-complete.

### Telescope

```
:Telescope openspec changes
:Telescope openspec specs
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
require("openspec").setup({
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
  view = {
    split = "botright new", -- window command hosting `openspec view`
  },
})
```

## Health

```
:checkhealth openspec
```

Reports whether the `openspec` binary is found (and its version), whether telescope.nvim is
available, and whether the current directory is inside an OpenSpec project (an `openspec/`
directory found by walking up from the current buffer).

## Lua API

```lua
local os_ = require("openspec")
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
