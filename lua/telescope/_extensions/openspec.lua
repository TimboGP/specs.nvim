--- Telescope extension registration for openspec.nvim.
--- Enables `:Telescope openspec changes` and `:Telescope openspec specs`.
local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("openspec.nvim telescope extension requires telescope.nvim")
end

local pickers = require("openspec.pickers")

return telescope.register_extension({
  setup = function(ext_config)
    -- Merge extension-level config into the plugin's picker config.
    if ext_config and next(ext_config) then
      require("openspec.config").setup({ picker = ext_config })
    end
  end,
  exports = {
    -- `:Telescope openspec` defaults to the changes picker.
    openspec = pickers.changes,
    changes = pickers.changes,
    specs = pickers.specs,
  },
})
