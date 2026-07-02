--- Public entry point for specs.nvim.
local config = require("specs.config")

local M = {}

--- Configure the plugin. Optional — sensible defaults apply without it.
--- @param opts SpecsConfig|nil
--- @return SpecsConfig
function M.setup(opts)
  return config.setup(opts)
end

-- Convenience re-exports of the public API surface.
setmetatable(M, {
  __index = function(_, key)
    if key == "changes" or key == "specs" then
      return require("specs.pickers")[key]
    end
    local actions = require("specs.actions")
    if actions[key] then
      return actions[key]
    end
    return nil
  end,
})

return M
