--- :Specs subcommand dispatch + completion.
local provider = require("specs.provider")
local ui = require("specs.ui")

local M = {}

-- Lazy accessors so plugin/ load stays cheap and telescope stays optional.
local function pickers()
  return require("specs.pickers")
end
local function actions()
  return require("specs.actions")
end
local function dashboard()
  return require("specs.dashboard")
end

--- @type table<string, fun(args: string[])>
local handlers = {
  changes = function()
    pickers().changes()
  end,
  specs = function()
    pickers().specs()
  end,
  show = function(args)
    actions().show(args[1])
  end,
  validate = function(args)
    actions().validate(args[1])
  end,
  status = function(args)
    actions().status(args[1])
  end,
  new = function(args)
    -- Support both `:Specs new demo` and `:Specs new change demo`.
    local name = args[1] == "change" and args[2] or args[1]
    actions().new_change(name)
  end,
  archive = function(args)
    actions().archive(args[1])
  end,
  diff = function(args)
    actions().diff(args[1])
  end,
  view = function()
    dashboard().open()
  end,
  init = function(args)
    -- Initialize a project with the configured backend (OpenSpec by default under
    -- "auto"; spec-kit when `provider = "speckit"`).
    local p = provider.for_init()
    p.impl.init(p.root, args, function(ok)
      if ok then
        provider.clear_cache()
        ui.notify(p.name .. " init complete", vim.log.levels.INFO)
      end
    end)
  end,
}

local subcommands = vim.tbl_keys(handlers)
table.sort(subcommands)

--- Entry point for the :Specs user command.
--- @param opts table nvim_create_user_command callback opts
function M.dispatch(opts)
  local fargs = opts.fargs or {}
  local sub = fargs[1]
  if not sub then
    -- Default action: open the changes picker.
    handlers.changes({})
    return
  end
  local handler = handlers[sub]
  if not handler then
    ui.notify(
      "Unknown subcommand '" .. sub .. "'. Available: " .. table.concat(subcommands, ", "),
      vim.log.levels.WARN
    )
    return
  end
  handler(vim.list_slice(fargs, 2))
end

--- Completion for :Specs.
--- @param arg_lead string
--- @param cmd_line string
--- @return string[]
function M.complete(arg_lead, cmd_line)
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  -- parts[1] == "Specs"; completing the subcommand itself.
  if #parts <= 2 then
    return vim.tbl_filter(function(s)
      return s:find(arg_lead, 1, true) == 1
    end, subcommands)
  end

  -- Second-argument completion: item names for name-taking subcommands.
  local sub = parts[2]
  local wants_names = { show = true, validate = true, status = true, archive = true, diff = true }
  if not wants_names[sub] then
    return {}
  end

  -- Synchronous best-effort name lookup from the active backend for completion.
  local p = provider.resolve()
  if not p then
    return {}
  end
  return vim.tbl_filter(function(name)
    return name:find(arg_lead, 1, true) == 1
  end, p.impl.names_sync(p.root))
end

return M
