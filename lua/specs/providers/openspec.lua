--- OpenSpec backend: a thin wrapper over the `openspec` CLI's `--json` surface.
--- This is the original behavior of the plugin, relocated behind the provider
--- interface (see `specs.provider`). All shelling out goes through `specs.cli`.
local cli = require("specs.cli")
local ui = require("specs.ui")
local config = require("specs.config")

local M = {}

--- @return table
function M.capabilities()
  return {
    specs_section = "Specs",
    archive = true,
    diff = "delta",
    validate = "issues",
    new_hint = "New change name: ",
  }
end

--- @param root string
--- @param cb fun(changes: table[], err: string|nil)
function M.list_changes(root, cb)
  cli.run_json({ "list" }, function(data, err)
    cb((not err and data and data.changes) or {}, err)
  end, { cwd = root })
end

--- @param root string
--- @param cb fun(specs: table[], err: string|nil)
function M.list_specs(root, cb)
  cli.run_json({ "list", "--specs" }, function(data, err)
    cb((not err and data and data.specs) or {}, err)
  end, { cwd = root })
end

--- Best-effort synchronous change-name list for command completion.
--- @param root string
--- @return string[]
function M.names_sync(root)
  local res = vim.system({ config.options.cmd, "list", "--json" }, { cwd = root, text = true }):wait()
  if res.code ~= 0 then
    return {}
  end
  local ok, data = pcall(vim.json.decode, res.stdout)
  if not ok or not data.changes then
    return {}
  end
  local names = {}
  for _, c in ipairs(data.changes) do
    table.insert(names, c.name)
  end
  return names
end

--- @param root string
--- @param name string
--- @param kind string|nil "change" | "spec"
--- @param cb fun(text: string|nil, err: string|nil)
function M.show(root, name, kind, cb)
  local args = { "show", name }
  if kind then
    vim.list_extend(args, { "--type", kind })
  end
  cli.run(args, { cwd = root }, function(res, err)
    cb((not err and res) and res.stdout or nil, err)
  end)
end

--- Normalize `openspec status --change` into the shared artifact shape, resolving
--- each artifact's absolute output path (skipping glob outputs).
--- @param root string
--- @param name string
--- @param cb fun(data: table|nil, err: string|nil)
function M.status(root, name, cb)
  cli.run_json({ "status", "--change", name }, function(data, err)
    if err or not data then
      cb(nil, err)
      return
    end
    local artifacts = {}
    for _, a in ipairs(data.artifacts or {}) do
      local path
      if a.outputPath and not a.outputPath:find("*", 1, true) then
        path = root .. "/openspec/changes/" .. name .. "/" .. a.outputPath
      end
      table.insert(artifacts, {
        id = a.id,
        status = a.status,
        path = path,
        missingDeps = a.missingDeps,
      })
    end
    cb({
      schemaName = data.schemaName,
      isComplete = data.isComplete,
      changeName = data.changeName or name,
      artifacts = artifacts,
    }, nil)
  end, { cwd = root })
end

-- Line number of the Nth (0-indexed) "### Requirement:" heading in a spec file,
-- matching the `requirements.<N>.text` issue paths the CLI emits for specs.
local function requirement_heading_line(file, n)
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok then
    return nil
  end
  local count = -1
  for i, line in ipairs(lines) do
    if line:match("^### Requirement:") then
      count = count + 1
      if count == n then
        return i
      end
    end
  end
  return nil
end

-- Best-effort file + line for a validate issue, using whatever location detail
-- the CLI's `issue.path` provides.
local function issue_location(item, issue, root)
  local msg = type(issue) == "string" and issue or (issue.message or vim.inspect(issue))
  local path = type(issue) == "table" and issue.path or nil
  local file, lnum

  if item.type == "spec" then
    file = root .. "/openspec/specs/" .. item.id .. "/spec.md"
    local n = path and path:match("^requirements%.(%d+)%.")
    lnum = n and requirement_heading_line(file, tonumber(n))
  elseif path and path ~= "file" and path:match("%.md$") then
    file = root .. "/openspec/changes/" .. item.id .. "/specs/" .. path
  else
    file = root .. "/openspec/changes/" .. item.id .. "/proposal.md"
  end

  return file, lnum or 1, msg
end

--- Validate one item (or all), returning quickfix-ready entries. `openspec
--- validate` exits 1 when an item is invalid — the normal outcome we report.
--- @param root string
--- @param name string|nil name, or nil/"all" for --all
--- @param cb fun(qf: table[], err: string|nil)
function M.validate(root, name, cb)
  local args = { "validate" }
  if not name or name == "" or name == "all" then
    table.insert(args, "--all")
  else
    table.insert(args, name)
  end
  cli.run_json(args, function(data, err)
    if err then
      cb(nil, err)
      return
    end
    local qf = {}
    for _, item in ipairs((data and data.items) or {}) do
      for _, issue in ipairs(item.issues or {}) do
        local file, lnum, msg = issue_location(item, issue, root)
        local level = type(issue) == "table" and issue.level or nil
        table.insert(qf, {
          filename = file,
          lnum = lnum,
          text = ("[%s] %s"):format(item.id or name or "?", msg),
          type = (level and level:match("^WARN")) and "W" or "E",
        })
      end
    end
    cb(qf, nil)
  end, { cwd = root, ok_codes = { 0, 1 } })
end

--- @param root string
--- @param input string change name
--- @param cb fun(name: string|nil, err: string|nil)
function M.new(root, input, cb)
  cli.run({ "new", "change", input }, { cwd = root }, function(res, err)
    cb((not err and res) and input or nil, err)
  end)
end

--- First ready artifact of a change (usually proposal.md), for opening on create.
--- @param root string
--- @param name string
--- @param cb fun(artifact: table|nil, err: string|nil)
function M.first_artifact(root, name, cb)
  M.status(root, name, function(data, err)
    if err or not data then
      cb(nil, err)
      return
    end
    for _, a in ipairs(data.artifacts) do
      if a.status == "ready" and a.path then
        cb({ id = a.id, path = a.path, schema = data.schemaName }, nil)
        return
      end
    end
    cb(nil, nil)
  end)
end

--- Fill an empty artifact buffer from its schema template (via `openspec templates`).
--- @param root string
--- @param bufnr integer
--- @param artifact table { id, schema }
function M.seed_template(root, bufnr, artifact)
  local args = { "templates" }
  if artifact.schema then
    vim.list_extend(args, { "--schema", artifact.schema })
  end
  cli.run_json(args, function(data, err)
    if err or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local entry = data and data[artifact.id]
    if not entry or not entry.path then
      return
    end
    local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    if #existing > 1 or existing[1] ~= "" then
      return
    end
    local ok, template_lines = pcall(vim.fn.readfile, entry.path)
    if not ok then
      return
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, template_lines)
    pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
  end, { cwd = root })
end

--- @param root string
--- @param name string
--- @param cb fun(ok: boolean, err: string|nil)
function M.archive(root, name, cb)
  cli.run({ "archive", name, "-y" }, { cwd = root }, function(res, err)
    cb((not err and res) and true or false, err)
  end)
end

--- Diff a change's proposed spec deltas against the current specs, one tab per
--- capability (Neovim's diff engine treats a missing "before" as all-added).
--- @param root string
--- @param name string
function M.diff(root, name)
  cli.run_json({ "show", name, "--type", "change", "--deltas-only" }, function(data, err)
    if err or not data then
      return
    end
    local deltas = data.deltas or {}
    if #deltas == 0 then
      ui.notify("No spec deltas found for '" .. name .. "'", vim.log.levels.INFO)
      return
    end
    local seen, capabilities = {}, {}
    for _, d in ipairs(deltas) do
      if d.spec and not seen[d.spec] then
        seen[d.spec] = true
        table.insert(capabilities, d.spec)
      end
    end
    for _, capability in ipairs(capabilities) do
      local before = root .. "/openspec/specs/" .. capability .. "/spec.md"
      local after = root .. "/openspec/changes/" .. name .. "/specs/" .. capability .. "/spec.md"
      vim.cmd("tabedit " .. vim.fn.fnameescape(after))
      vim.cmd("vert diffsplit " .. vim.fn.fnameescape(before))
    end
  end, { cwd = root })
end

--- @param root string
--- @param args string[] passthrough args for `openspec init`
--- @param cb fun(ok: boolean, err: string|nil)
function M.init(root, args, cb)
  local passthrough = { "init" }
  vim.list_extend(passthrough, args)
  cli.run(passthrough, { cwd = root, require_root = false }, function(res, err)
    cb((not err and res) and true or false, err)
  end)
end

return M
