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

--- Render validation results for one item, or --all.
--- @param name string|nil name, or "all"/nil for --all
function M.validate(name)
  local args = { "validate" }
  if not name or name == "" or name == "all" then
    table.insert(args, "--all")
  else
    table.insert(args, name)
  end

  cli.run_json(args, function(data, err)
    if err then
      return
    end
    -- The CLI shape varies (single vs --all); render defensively.
    local lines = { "# openspec validate", "" }
    local items = data.results or data.items or { data }
    local any_invalid = false
    for _, item in ipairs(items) do
      local ok = item.valid ~= false and item.isValid ~= false
      any_invalid = any_invalid or not ok
      local label = item.name or item.id or (name or "all")
      table.insert(lines, (ok and "✓ " or "✗ ") .. label)
      for _, issue in ipairs(item.issues or item.errors or {}) do
        local text = type(issue) == "string" and issue or (issue.message or vim.inspect(issue))
        table.insert(lines, "    • " .. text)
      end
    end
    if not any_invalid then
      ui.notify("Validation passed", vim.log.levels.INFO)
    end
    ui.open_scratch(lines, { title = "specs://validate", filetype = "markdown" })
  end)
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
