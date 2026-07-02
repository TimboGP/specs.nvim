--- Configuration defaults and merge logic for openspec.nvim.
local M = {}

--- @class OpenSpecConfig
--- @field cmd string           Executable name or absolute path to the openspec binary.
--- @field notify boolean       Whether to emit vim.notify messages.
--- @field picker table         Telescope picker options.
--- @field view table           Options for the embedded `openspec view` terminal.
local defaults = {
  -- Executable used for every shelled-out call. Override to pin an absolute path.
  cmd = "openspec",

  -- Set to false to silence all [openspec] notifications.
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

  view = {
    -- Command used to create the window that hosts the `openspec view` terminal.
    split = "botright new",
  },
}

--- The active, merged configuration. Populated by setup(); defaults until then.
--- @type OpenSpecConfig
M.options = vim.deepcopy(defaults)

--- Merge user options over the defaults.
--- @param opts OpenSpecConfig|nil
--- @return OpenSpecConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.options
end

return M
