--- Telescope extension registration for specs.nvim.
--- Enables `:Telescope specs changes` and `:Telescope specs specs`.
local has_telescope, telescope = pcall(require, "telescope")
if not has_telescope then
  error("specs.nvim telescope extension requires telescope.nvim")
end

local pickers = require("specs.pickers")

return telescope.register_extension({
  setup = function(ext_config)
    -- Merge extension-level config into the plugin's picker config.
    if ext_config and next(ext_config) then
      require("specs.config").setup({ picker = ext_config })
    end
  end,
  exports = {
    changes = pickers.changes,
    specs = pickers.specs,
  },
})
