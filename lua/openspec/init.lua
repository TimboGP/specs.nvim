--- Public entry point for openspec.nvim.
local config = require("openspec.config")

local M = {}

--- Configure the plugin. Optional — sensible defaults apply without it.
--- @param opts OpenSpecConfig|nil
--- @return OpenSpecConfig
function M.setup(opts)
  return config.setup(opts)
end

-- Convenience re-exports of the public API surface.
setmetatable(M, {
  __index = function(_, key)
    if key == "changes" or key == "specs" then
      return require("openspec.pickers")[key]
    end
    local actions = require("openspec.actions")
    if actions[key] then
      return actions[key]
    end
    return nil
  end,
})

return M
