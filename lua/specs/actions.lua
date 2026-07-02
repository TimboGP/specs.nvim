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
