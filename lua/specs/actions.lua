--- Non-picker operations. Also invoked by the Telescope picker mappings and the
--- dashboard. Backend-agnostic: every function resolves the active provider
--- (`specs.provider`) and delegates the backend-specific work to it, keeping the
--- rendering (scratch buffers, quickfix, tab opening) here.
local provider = require("specs.provider")
local ui = require("specs.ui")

local M = {}

--- Resolve the backend for the current context, notifying if there is none.
--- @return SpecsProvider|nil
local function resolve()
  local p = provider.resolve()
  if not p then
    ui.notify("Not in a spec project (OpenSpec or spec-kit) — run :Specs init", vim.log.levels.WARN)
  end
  return p
end

--- Show a change/spec/feature as markdown in a scratch buffer.
--- @param name string
--- @param typ string|nil "change" | "spec"
function M.show(name, typ)
  if not name or name == "" then
    ui.notify("show: missing item name", vim.log.levels.WARN)
    return
  end
  local p = resolve()
  if not p then
    return
  end
  p.impl.show(p.root, name, typ, function(text, err)
    if err or not text then
      return
    end
    ui.open_scratch(ui.to_lines(text), {
      title = "specs://show/" .. name,
      filetype = "markdown",
    })
  end)
end

--- Fetch an item's markdown into a string (used by the picker/dashboard preview).
--- Resolves silently — the caller is already inside a resolved context.
--- @param name string
--- @param typ string|nil
--- @param cb fun(text: string|nil)
function M.show_text(name, typ, cb)
  local p = provider.resolve()
  if not p then
    cb(nil)
    return
  end
  p.impl.show(p.root, name, typ, function(text)
    cb(text)
  end)
end

--- Open a diff for a change/feature. What "diff" means is backend-specific
--- (OpenSpec: proposed spec deltas; spec-kit: git diff of the feature folder).
--- @param name string
function M.diff(name)
  if not name or name == "" then
    ui.notify("diff: missing change name", vim.log.levels.WARN)
    return
  end
  local p = resolve()
  if not p then
    return
  end
  if not p.caps.diff then
    ui.notify("diff is not supported by the " .. p.name .. " backend", vim.log.levels.INFO)
    return
  end
  p.impl.diff(p.root, name)
end

--- Validate one item, or all, and populate the quickfix list with the backend's
--- issues so `[q`/`]q`/`:cnext` navigate straight to the offending file/line.
--- @param name string|nil name, or "all"/nil for all
function M.validate(name)
  local p = resolve()
  if not p then
    return
  end
  p.impl.validate(p.root, name, function(qf, err)
    if err then
      return
    end
    if #qf == 0 then
      ui.notify("Validation passed", vim.log.levels.INFO)
      vim.fn.setqflist({}, "r", { title = "specs validate", items = {} })
      return
    end
    vim.fn.setqflist({}, " ", { title = "specs validate", items = qf })
    vim.cmd("copen")
  end)
end

--- Render artifact completion status for a change/feature.
--- @param name string
function M.status(name)
  if not name or name == "" then
    ui.notify("status: missing change name", vim.log.levels.WARN)
    return
  end
  local p = resolve()
  if not p then
    return
  end
  p.impl.status(p.root, name, function(data, err)
    if err or not data then
      return
    end
    local icons = { ready = "○", blocked = "⋯", complete = "✓", pending = "○", done = "✓" }
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

--- Open a freshly created change/feature's first artifact in a new tab, seeded
--- from its template. A tab keeps this safe to call from anywhere.
--- @param p SpecsProvider
--- @param name string
local function open_first_artifact(p, name)
  p.impl.first_artifact(p.root, name, function(artifact, err)
    if err or not artifact then
      return
    end
    vim.cmd("tabedit " .. vim.fn.fnameescape(artifact.path))
    p.impl.seed_template(p.root, vim.api.nvim_get_current_buf(), artifact)
  end)
end

--- Create a new change (OpenSpec) or feature (spec-kit). Prompts when no name/
--- description is given, using the backend's prompt hint.
--- @param name string|nil
--- @param on_done fun()|nil callback after successful creation (e.g. refresh)
function M.new_change(name, on_done)
  local p = resolve()
  if not p then
    return
  end
  local function create(input)
    if not input or input == "" then
      return
    end
    p.impl.new(p.root, input, function(created, err)
      if err or not created then
        return
      end
      provider.clear_cache()
      ui.notify("Created '" .. created .. "'", vim.log.levels.INFO)
      open_first_artifact(p, created)
      if on_done then
        on_done()
      end
    end)
  end

  if name and name ~= "" then
    create(name)
  else
    vim.ui.input({ prompt = p.caps.new_hint }, create)
  end
end

--- Archive a change after confirmation (OpenSpec). Backends without an archive
--- concept (spec-kit) surface a notice instead.
--- @param name string
--- @param on_done fun()|nil
function M.archive(name, on_done)
  if not name or name == "" then
    ui.notify("archive: missing change name", vim.log.levels.WARN)
    return
  end
  local p = resolve()
  if not p then
    return
  end
  if not p.caps.archive then
    -- The provider owns the "unsupported" notice.
    p.impl.archive(p.root, name, function() end)
    return
  end
  vim.ui.select({ "Yes", "No" }, {
    prompt = "Archive change '" .. name .. "'?",
  }, function(choice)
    if choice ~= "Yes" then
      return
    end
    p.impl.archive(p.root, name, function(ok, err)
      if err or not ok then
        return
      end
      provider.clear_cache()
      ui.notify("Archived '" .. name .. "'", vim.log.levels.INFO)
      if on_done then
        on_done()
      end
    end)
  end)
end

return M
