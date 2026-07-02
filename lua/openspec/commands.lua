--- :OpenSpec subcommand dispatch + completion.
local cli = require("openspec.cli")
local ui = require("openspec.ui")

local M = {}

-- Lazy accessors so plugin/ load stays cheap and telescope stays optional.
local function pickers()
  return require("openspec.pickers")
end
local function actions()
  return require("openspec.actions")
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
    -- Support both `:OpenSpec new demo` and `:OpenSpec new change demo`.
    local name = args[1] == "change" and args[2] or args[1]
    actions().new_change(name)
  end,
  archive = function(args)
    actions().archive(args[1])
  end,
  view = function()
    ui.view()
  end,
  init = function(args)
    -- Pass through to `openspec init`; may require --tools, so surface stdout.
    local passthrough = { "init" }
    vim.list_extend(passthrough, args)
    cli.run(passthrough, { require_root = false }, function(res, err)
      if not err and res then
        cli.clear_cache()
        ui.notify("openspec init complete", vim.log.levels.INFO)
      end
    end)
  end,
}

local subcommands = vim.tbl_keys(handlers)
table.sort(subcommands)

--- Entry point for the :OpenSpec user command.
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

--- Completion for :OpenSpec.
--- @param arg_lead string
--- @param cmd_line string
--- @return string[]
function M.complete(arg_lead, cmd_line)
  local parts = vim.split(vim.trim(cmd_line), "%s+")
  -- parts[1] == "OpenSpec"; completing the subcommand itself.
  if #parts <= 2 then
    return vim.tbl_filter(function(s)
      return s:find(arg_lead, 1, true) == 1
    end, subcommands)
  end

  -- Second-argument completion: item names for name-taking subcommands.
  local sub = parts[2]
  local wants_names = { show = "list", validate = "list", status = "list", archive = "list" }
  if not wants_names[sub] then
    return {}
  end

  -- Synchronous best-effort name lookup for completion.
  local root = cli.root()
  if not root then
    return {}
  end
  local res = vim.system({ require("openspec.config").options.cmd, "list", "--json" }, {
    cwd = root,
    text = true,
  }):wait()
  if res.code ~= 0 then
    return {}
  end
  local ok, data = pcall(vim.json.decode, res.stdout)
  if not ok or not data.changes then
    return {}
  end
  local names = {}
  for _, c in ipairs(data.changes) do
    if c.name:find(arg_lead, 1, true) == 1 then
      table.insert(names, c.name)
    end
  end
  return names
end

return M
