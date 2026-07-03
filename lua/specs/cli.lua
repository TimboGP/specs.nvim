--- The single boundary that shells out to the `openspec` CLI.
--- Everything async (vim.system); JSON decoding and project-root detection live here.
local config = require("specs.config")
local ui = require("specs.ui")

local M = {}

-- Cache of resolved project roots keyed by starting directory.
local root_cache = {}

--- Find the OpenSpec project root by walking up from `start` looking for an
--- `openspec/` directory. Returns nil if none is found.
--- @param start string|nil directory to start from (default: buffer dir, then cwd)
--- @return string|nil root
function M.root(start)
  start = start or vim.fn.expand("%:p:h")
  if start == "" then
    start = vim.uv.cwd()
  end
  if root_cache[start] ~= nil then
    return root_cache[start] or nil
  end

  local found = vim.fs.find("openspec", {
    path = start,
    upward = true,
    type = "directory",
    limit = 1,
  })[1]

  local root = found and vim.fs.dirname(found) or false
  root_cache[start] = root
  return root or nil
end

--- Clear the root cache (call after `init`/`archive` change the project layout).
function M.clear_cache()
  root_cache = {}
end

--- Run an openspec command asynchronously.
--- @param args string[] arguments after the executable (e.g. { "list" })
--- @param opts table|nil { cwd?, require_root? (default true), ok_codes? (default {0}) }
--- @param cb fun(result: { code: integer, stdout: string, stderr: string }|nil, err: string|nil)
function M.run(args, opts, cb)
  opts = opts or {}
  local cmd = config.options.cmd

  local cwd = opts.cwd
  if cwd == nil and opts.require_root ~= false then
    cwd = M.root()
    if not cwd then
      local err = "Not in an OpenSpec project — run :Specs init"
      ui.notify(err, vim.log.levels.ERROR)
      cb(nil, err)
      return
    end
  end

  local full = { cmd }
  vim.list_extend(full, args)

  local ok_codes = opts.ok_codes or { 0 }
  vim.system(full, { cwd = cwd, text = true }, function(res)
    vim.schedule(function()
      if not vim.list_contains(ok_codes, res.code) then
        local err = (res.stderr ~= "" and res.stderr) or ("openspec exited with code " .. res.code)
        ui.notify(vim.trim(err), vim.log.levels.ERROR)
        cb(res, err)
        return
      end
      cb(res, nil)
    end)
  end)
end

--- Run an openspec command with `--json` and decode stdout. When `opts.ok_codes`
--- widens the accepted exit codes (e.g. `validate`'s "issues found" exit 1),
--- stdout is still checked for real JSON before trusting that exit code: a
--- widened code with non-JSON stdout (e.g. an "Unknown item" message) is
--- reported as an error rather than silently swallowed.
--- @param args string[]
--- @param cb fun(data: table|nil, err: string|nil)
--- @param opts table|nil forwarded to M.run
function M.run_json(args, cb, opts)
  local json_args = vim.deepcopy(args)
  table.insert(json_args, "--json")
  M.run(json_args, opts, function(res, err)
    if not res then
      cb(nil, err)
      return
    end
    local trimmed = vim.trim(res.stdout)
    if trimmed:match("^[%[{]") then
      local ok, decoded = pcall(vim.json.decode, trimmed)
      if ok then
        cb(decoded, nil)
        return
      end
      local msg = "Failed to parse openspec JSON output"
      ui.notify(msg, vim.log.levels.ERROR)
      cb(nil, msg)
      return
    end
    if err then
      cb(nil, err)
      return
    end
    if res.code ~= 0 then
      local msg = (res.stderr ~= "" and vim.trim(res.stderr)) or ("openspec exited with code " .. res.code)
      ui.notify(msg, vim.log.levels.ERROR)
      cb(nil, msg)
      return
    end
    -- Some subcommands (e.g. `list --specs`) print a plain "None found"
    -- message instead of JSON when the result set is empty, even with --json.
    cb({}, nil)
  end)
end

return M
