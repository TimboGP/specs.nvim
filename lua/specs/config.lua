--- Configuration defaults and merge logic for specs.nvim.
local M = {}

--- @class SpecsConfig
--- @field provider string      Backend to drive: "auto" (detect per project), "openspec", or "speckit".
--- @field cmd string           Executable name or absolute path to the openspec binary.
--- @field speckit table        spec-kit backend options (executable + project layout).
--- @field notify boolean       Whether to emit vim.notify messages.
--- @field picker table         Telescope picker options.
--- @field dashboard table      Options for the navigable changes/specs tree panel.
local defaults = {
  -- Which backend to drive. "auto" detects per project by walking up for an
  -- `openspec/` directory (OpenSpec) or a `.specify/`/numbered `specs/` layout
  -- (spec-kit). Force a single backend with "openspec" or "speckit".
  provider = "auto",

  -- Executable for the OpenSpec backend. Override to pin an absolute path.
  cmd = "openspec",

  -- spec-kit backend settings.
  speckit = {
    -- Executable used for `:Specs init`/`new` fallbacks (github/spec-kit's CLI).
    cmd = "specify",
    -- Directory (relative to the project root) holding feature folders.
    specs_dir = "specs",
    -- Directory (relative to root) holding the constitution and memory docs.
    memory_dir = ".specify/memory",
  },

  -- Set to false to silence all [specs] notifications.
  notify = true,

  picker = {
    -- In-picker action keymaps (insert + normal mode) for the changes/specs pickers.
    mappings = {
      validate = "<C-v>",
      status = "<C-s>",
      archive = "<C-a>",
      new = "<C-n>",
    },
  },

  dashboard = {
    -- Command used to create the window that hosts the changes/specs tree panel.
    split = "topleft 40vsplit",
  },
}

--- The active, merged configuration. Populated by setup(); defaults until then.
--- @type SpecsConfig
M.options = vim.deepcopy(defaults)

--- Merge user options over the defaults.
--- @param opts SpecsConfig|nil
--- @return SpecsConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.options
end

return M
