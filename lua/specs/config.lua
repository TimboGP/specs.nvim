--- Configuration defaults and merge logic for specs.nvim.
local M = {}

--- @class SpecsConfig
--- @field cmd string           Executable name or absolute path to the openspec binary.
--- @field notify boolean       Whether to emit vim.notify messages.
--- @field picker table         Telescope picker options.
--- @field dashboard table      Options for the navigable changes/specs tree panel.
local defaults = {
  -- Executable used for every shelled-out call. Override to pin an absolute path.
  cmd = "openspec",

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
