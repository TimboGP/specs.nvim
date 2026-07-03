--- Non-picker operations. Also invoked by the Telescope picker mappings.
local cli = require("specs.cli")
local ui = require("specs.ui")

local M = {}

--- Show a change or spec as markdown in a scratch buffer.
--- @param name string
--- @param typ string|nil "change" | "spec" (passed as --type when given)
function M.show(name, typ)
  if not name or name == "" then
    ui.notify("show: missing item name", vim.log.levels.WARN)
    return
  end
  local args = { "show", name }
  if typ then
    vim.list_extend(args, { "--type", typ })
  end
  cli.run(args, nil, function(res, err)
    if err or not res then
      return
    end
    ui.open_scratch(ui.to_lines(res.stdout), {
      title = "specs://show/" .. name,
      filetype = "markdown",
    })
  end)
end

--- Fetch a change/spec's markdown into a string (used by the picker previewer).
--- @param name string
--- @param typ string|nil
--- @param cb fun(text: string|nil)
function M.show_text(name, typ, cb)
  local args = { "show", name }
  if typ then
    vim.list_extend(args, { "--type", typ })
  end
  cli.run(args, nil, function(res, err)
    cb((not err and res) and res.stdout or nil)
  end)
end

--- Open a diff of a change's proposed spec deltas against the current top-level
--- spec they touch, one tab per capability. We don't reconstruct the merged
--- result ourselves — that's `openspec archive`'s job — we just diff the two
--- real files (Neovim's diff engine handles a missing "before" file, for a
--- brand-new capability, as entirely-added content).
--- @param name string change name
function M.diff(name)
  if not name or name == "" then
    ui.notify("diff: missing change name", vim.log.levels.WARN)
    return
  end
  cli.run_json({ "show", name, "--type", "change", "--deltas-only" }, function(data, err)
    if err or not data then
      return
    end
    local deltas = data.deltas or {}
    if #deltas == 0 then
      ui.notify("No spec deltas found for '" .. name .. "'", vim.log.levels.INFO)
      return
    end
    local root = cli.root()
    if not root then
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
  end)
end

--- Line number of the Nth (0-indexed) "### Requirement:" heading in a spec file,
--- matching the `requirements.<N>.text` issue paths the CLI emits for specs.
--- @param file string
--- @param n integer
--- @return integer|nil
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

--- Best-effort file + line for a validate issue, using whatever location detail
--- the CLI's `issue.path` provides: `requirements.<N>.text` for specs (mapped to
--- the Nth requirement heading), a delta spec's relative path for changes, or
--- just the item's root artifact when the issue is file-wide (`path == "file"`).
--- @param item table one entry from `data.items`
--- @param issue table|string
--- @param root string project root
--- @return string file, integer lnum, string message
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

--- Validate one item, or --all, and populate the quickfix list with its issues
--- so `[q`/`]q`/`:cnext` navigate straight to the offending file and (when the
--- CLI's issue path resolves to one) line.
--- @param name string|nil name, or "all"/nil for --all
function M.validate(name)
  local args = { "validate" }
  if not name or name == "" or name == "all" then
    table.insert(args, "--all")
  else
    table.insert(args, name)
  end

  -- `openspec validate` exits 1 when any item is invalid — that's the normal,
  -- expected outcome we're here to report, not a tool failure.
  cli.run_json(args, function(data, err)
    if err then
      return
    end
    local root = cli.root() or ""
    local items = (data and data.items) or {}
    local qf = {}
    for _, item in ipairs(items) do
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

    if #qf == 0 then
      ui.notify("Validation passed", vim.log.levels.INFO)
      vim.fn.setqflist({}, "r", { title = "openspec validate", items = {} })
      return
    end

    vim.fn.setqflist({}, " ", { title = "openspec validate", items = qf })
    vim.cmd("copen")
  end, { ok_codes = { 0, 1 } })
end

--- Render artifact completion status for a change.
--- @param name string
function M.status(name)
  if not name or name == "" then
    ui.notify("status: missing change name", vim.log.levels.WARN)
    return
  end
  cli.run_json({ "status", "--change", name }, function(data, err)
    if err then
      return
    end
    local icons = { ready = "✓", blocked = "⋯", complete = "✓", pending = "○" }
    local lines = {
      "# status: " .. (data.changeName or name),
      "",
      "schema: " .. (data.schemaName or "?"),
      "complete: " .. tostring(data.isComplete),
      "",
      "## artifacts",
    }
    for _, a in ipairs(data.artifacts or {}) do
      local icon = icons[a.status] or "•"
      local line = ("%s %-10s %s"):format(icon, a.status, a.id)
      if a.missingDeps and #a.missingDeps > 0 then
        line = line .. "  (needs: " .. table.concat(a.missingDeps, ", ") .. ")"
      end
      table.insert(lines, line)
    end
    ui.open_scratch(lines, { title = "specs://status/" .. name, filetype = "markdown" })
  end)
end

--- Seed a freshly created, still-empty artifact buffer from its schema template.
--- No-ops if the buffer already has content, so it never clobbers real work.
--- @param bufnr integer
--- @param artifact_id string
--- @param schema string|nil
local function seed_from_template(bufnr, artifact_id, schema)
  local args = { "templates" }
  if schema then
    vim.list_extend(args, { "--schema", schema })
  end
  cli.run_json(args, function(data, err)
    if err or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local entry = data and data[artifact_id]
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
  end)
end

--- Open a freshly created change's first ready artifact (usually proposal.md) in
--- a new tab, seeded from its schema template. A tab keeps this safe to call from
--- anywhere — a Telescope prompt, the dashboard panel, or a plain buffer — without
--- clobbering whatever window/split the caller was using.
--- @param name string
local function open_first_artifact(name)
  cli.run_json({ "status", "--change", name }, function(data, err)
    if err or not data then
      return
    end
    local target
    for _, a in ipairs(data.artifacts or {}) do
      if a.status == "ready" and a.outputPath and not a.outputPath:find("*", 1, true) then
        target = a
        break
      end
    end
    if not target then
      return
    end
    local root = cli.root()
    if not root then
      return
    end
    local path = root .. "/openspec/changes/" .. name .. "/" .. target.outputPath
    vim.cmd("tabedit " .. vim.fn.fnameescape(path))
    seed_from_template(vim.api.nvim_get_current_buf(), target.id, data.schemaName)
  end)
end

--- Create a new change. Prompts for a name when none is given.
--- @param name string|nil
--- @param on_done fun()|nil callback after successful creation (e.g. refresh picker)
function M.new_change(name, on_done)
  local function create(n)
    if not n or n == "" then
      return
    end
    cli.run({ "new", "change", n }, nil, function(res, err)
      if err or not res then
        return
      end
      ui.notify("Created change '" .. n .. "'", vim.log.levels.INFO)
      open_first_artifact(n)
      if on_done then
        on_done()
      end
    end)
  end

  if name and name ~= "" then
    create(name)
  else
    vim.ui.input({ prompt = "New change name: " }, create)
  end
end

--- Archive a change after a confirmation prompt.
--- @param name string
--- @param on_done fun()|nil
function M.archive(name, on_done)
  if not name or name == "" then
    ui.notify("archive: missing change name", vim.log.levels.WARN)
    return
  end
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Archive change '" .. name .. "'?",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end
    cli.run({ "archive", name, "-y" }, nil, function(res, err)
      if err or not res then
        return
      end
      cli.clear_cache()
      ui.notify("Archived '" .. name .. "'", vim.log.levels.INFO)
      if on_done then
        on_done()
      end
    end)
  end)
end

return M
