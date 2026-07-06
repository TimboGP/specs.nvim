--- spec-kit backend: github/spec-kit has no query CLI, so this provider reads the
--- project's filesystem directly. Feature folders under `specs/NNN-*/` map onto
--- OpenSpec "changes"; `.specify/memory/*.md` (constitution first) maps onto the
--- second "specs" section. `new` prefers spec-kit's own `create-new-feature.sh`
--- (for numbering + git branch), falling back to pure Lua.
local ui = require("specs.ui")
local config = require("specs.config")

local M = {}

-- Feature artifacts in lifecycle order. `requires` gates the "blocked" status so
-- an unwritten plan/tasks shows as waiting on its predecessor.
local ARTIFACTS = {
  { id = "spec", file = "spec.md" },
  { id = "plan", file = "plan.md", requires = "spec.md" },
  { id = "tasks", file = "tasks.md", requires = "plan.md" },
  { id = "research", file = "research.md", optional = true },
  { id = "data-model", file = "data-model.md", optional = true },
  { id = "quickstart", file = "quickstart.md", optional = true },
  { id = "contracts", file = "contracts", optional = true, dir = true },
}

--- @return table
function M.capabilities()
  return {
    specs_section = "Constitution",
    archive = false,
    diff = "git",
    validate = "prereq",
    new_hint = "New feature description: ",
  }
end

--- @param path string
--- @return boolean
local function exists(path)
  return vim.uv.fs_stat(path) ~= nil
end

--- @param path string
--- @return string|nil
local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return table.concat(lines, "\n")
end

local function specs_base(root)
  return root .. "/" .. config.options.speckit.specs_dir
end

--- Feature folder names under `specs/`, numeric-prefix sorted. A directory counts
--- as a feature when it has a numbered prefix or contains a spec.md.
--- @param root string
--- @return string[]
local function feature_dirs(root)
  local base = specs_base(root)
  local ok, iter = pcall(vim.fs.dir, base)
  local names = {}
  if ok then
    for name, typ in iter do
      if typ == "directory" and (name:match("^%d") or exists(base .. "/" .. name .. "/spec.md")) then
        table.insert(names, name)
      end
    end
  end
  table.sort(names, function(a, b)
    local na, nb = tonumber(a:match("^(%d+)")), tonumber(b:match("^(%d+)"))
    if na and nb and na ~= nb then
      return na < nb
    end
    return a < b
  end)
  return names
end

--- Count `- [ ]`/`- [x]` checkboxes in a tasks.md.
--- @param path string
--- @return integer completed, integer total
local function count_tasks(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return 0, 0
  end
  local completed, total = 0, 0
  for _, line in ipairs(lines) do
    local mark = line:match("^%s*%-%s%[([ xX])%]")
    if mark then
      total = total + 1
      if mark ~= " " then
        completed = completed + 1
      end
    end
  end
  return completed, total
end

--- @param root string
--- @param cb fun(changes: table[], err: string|nil)
function M.list_changes(root, cb)
  local changes = {}
  for _, name in ipairs(feature_dirs(root)) do
    local tasks = specs_base(root) .. "/" .. name .. "/tasks.md"
    local completed, total = count_tasks(tasks)
    local status
    if total == 0 then
      status = "no-tasks"
    elseif completed >= total then
      status = "complete"
    else
      status = "in-progress"
    end
    table.insert(changes, {
      name = name,
      status = status,
      completedTasks = completed,
      totalTasks = total,
    })
  end
  cb(changes, nil)
end

--- Memory docs (constitution first) shown as the second section.
--- @param root string
--- @param cb fun(specs: table[], err: string|nil)
function M.list_specs(root, cb)
  local base = root .. "/" .. config.options.speckit.memory_dir
  local ok, iter = pcall(vim.fs.dir, base)
  local names = {}
  if ok then
    for name, typ in iter do
      if typ == "file" and name:match("%.md$") then
        table.insert(names, (name:gsub("%.md$", "")))
      end
    end
  end
  table.sort(names, function(a, b)
    if a == "constitution" then
      return true
    end
    if b == "constitution" then
      return false
    end
    return a < b
  end)
  local specs = {}
  for _, name in ipairs(names) do
    table.insert(specs, { name = name })
  end
  cb(specs, nil)
end

--- @param root string
--- @return string[]
function M.names_sync(root)
  return feature_dirs(root)
end

--- @param root string
--- @param name string
--- @param kind string|nil "change" (feature) | "spec" (memory doc)
--- @param cb fun(text: string|nil, err: string|nil)
function M.show(root, name, kind, cb)
  local path
  if kind == "spec" then
    path = root .. "/" .. config.options.speckit.memory_dir .. "/" .. name .. ".md"
  else
    path = specs_base(root) .. "/" .. name .. "/spec.md"
  end
  local text = read_file(path)
  cb(text or ("*(not found: " .. vim.fn.fnamemodify(path, ":.") .. ")*"), nil)
end

--- Synthesize a change's artifact checklist from file existence.
--- @param root string
--- @param name string
--- @param cb fun(data: table|nil, err: string|nil)
function M.status(root, name, cb)
  local dir = specs_base(root) .. "/" .. name
  local artifacts, all_core_done = {}, true
  for _, a in ipairs(ARTIFACTS) do
    local path = dir .. "/" .. a.file
    local present = exists(path)
    local status, missing
    if present then
      status = "done"
    elseif a.requires and not exists(dir .. "/" .. a.requires) then
      status = "blocked"
      missing = { a.requires:gsub("%.md$", "") }
    else
      status = "ready"
    end
    if not a.optional and status ~= "done" then
      all_core_done = false
    end
    table.insert(artifacts, {
      id = a.id,
      status = status,
      path = (not a.dir) and path or nil,
      missingDeps = missing,
    })
  end
  cb({
    schemaName = "spec-kit",
    isComplete = all_core_done,
    changeName = name,
    artifacts = artifacts,
  }, nil)
end

--- Repurposed validate: report missing artifacts as quickfix entries. spec.md is
--- an error; plan.md/tasks.md are warnings (later lifecycle phases).
--- @param root string
--- @param name string|nil a feature, or nil/"all" for every feature
--- @param cb fun(qf: table[], err: string|nil)
function M.validate(root, name, cb)
  local targets
  if not name or name == "" or name == "all" then
    targets = feature_dirs(root)
  else
    targets = { name }
  end
  local checks = {
    { file = "spec.md", type = "E" },
    { file = "plan.md", type = "W" },
    { file = "tasks.md", type = "W" },
  }
  local qf = {}
  for _, feature in ipairs(targets) do
    local dir = specs_base(root) .. "/" .. feature
    for _, c in ipairs(checks) do
      local path = dir .. "/" .. c.file
      if not exists(path) then
        table.insert(qf, {
          filename = path,
          lnum = 1,
          text = ("[%s] missing %s"):format(feature, c.file),
          type = c.type,
        })
      end
    end
  end
  cb(qf, nil)
end

--- Turn a description into a filesystem-safe slug (Lua fallback only).
local function slugify(input)
  local slug = input:lower():gsub("[^%w]+", "-"):gsub("^-+", ""):gsub("-+$", "")
  -- Keep it to the first few words, as spec-kit's own script does.
  local words = vim.split(slug, "-", { plain = true, trimempty = true })
  return table.concat(vim.list_slice(words, 1, math.min(#words, 4)), "-")
end

--- Next zero-padded feature number.
local function next_number(root)
  local max = 0
  for _, name in ipairs(feature_dirs(root)) do
    local n = tonumber(name:match("^(%d+)"))
    if n and n > max then
      max = n
    end
  end
  return ("%03d"):format(max + 1)
end

--- Create a feature. Prefers spec-kit's create-new-feature.sh (numbering + git
--- branch); falls back to a pure-Lua mkdir + template seed.
--- @param root string
--- @param input string feature description
--- @param cb fun(name: string|nil, err: string|nil)
function M.new(root, input, cb)
  local script = root .. "/.specify/scripts/bash/create-new-feature.sh"
  if exists(script) then
    vim.system(
      { "bash", script, "--json", input },
      { cwd = root, text = true },
      vim.schedule_wrap(function(res)
        if res.code ~= 0 then
          local err = vim.trim(res.stderr ~= "" and res.stderr or "create-new-feature.sh failed")
          ui.notify(err, vim.log.levels.ERROR)
          cb(nil, err)
          return
        end
        local ok, data = pcall(vim.json.decode, vim.trim(res.stdout))
        if not ok or not data.SPEC_FILE then
          ui.notify("Could not parse create-new-feature.sh output", vim.log.levels.ERROR)
          cb(nil, "parse error")
          return
        end
        -- SPEC_FILE is specs/<feature>/spec.md — the feature is its parent dir.
        local feature = vim.fn.fnamemodify(data.SPEC_FILE, ":h:t")
        cb(feature, nil)
      end)
    )
    return
  end

  -- Pure-Lua fallback: no git branch, just the numbered folder + seeded spec.md.
  local name = next_number(root) .. "-" .. slugify(input)
  local dir = specs_base(root) .. "/" .. name
  if vim.fn.mkdir(dir, "p") ~= 1 then
    local err = "Failed to create " .. dir
    ui.notify(err, vim.log.levels.ERROR)
    cb(nil, err)
    return
  end
  local template = read_file(root .. "/.specify/templates/spec-template.md")
  local body = template or ("# " .. name .. "\n")
  pcall(vim.fn.writefile, vim.split(body, "\n", { plain = true }), dir .. "/spec.md")
  cb(name, nil)
end

--- A feature's primary artifact to open on create: its spec.md.
--- @param root string
--- @param name string
--- @param cb fun(artifact: table|nil, err: string|nil)
function M.first_artifact(root, name, cb)
  cb({ id = "spec", path = specs_base(root) .. "/" .. name .. "/spec.md", schema = nil }, nil)
end

--- Fill an empty artifact buffer from `.specify/templates/<id>-template.md`.
--- @param root string
--- @param bufnr integer
--- @param artifact table { id }
function M.seed_template(root, bufnr, artifact)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local existing = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #existing > 1 or existing[1] ~= "" then
    return
  end
  local template = read_file(root .. "/.specify/templates/" .. artifact.id .. "-template.md")
  if not template then
    return
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(template, "\n", { plain = true }))
  pcall(vim.api.nvim_win_set_cursor, 0, { 1, 0 })
end

--- spec-kit has no archive concept — features live in `specs/` until removed.
--- @param root string
--- @param name string
--- @param cb fun(ok: boolean, err: string|nil)
function M.archive(root, name, cb)
  ui.notify("spec-kit has no archive — delete the specs/ folder manually to remove it", vim.log.levels.WARN)
  cb(false, nil)
end

--- Diff a feature folder against its committed state (`git diff`).
--- @param root string
--- @param name string
function M.diff(root, name)
  local rel = config.options.speckit.specs_dir .. "/" .. name
  vim.system(
    { "git", "-C", root, "diff", "--", rel },
    { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        ui.notify(vim.trim(res.stderr ~= "" and res.stderr or "git diff failed"), vim.log.levels.ERROR)
        return
      end
      local out = vim.trim(res.stdout)
      if out == "" then
        ui.notify("No tracked changes for '" .. name .. "' (it may be untracked)", vim.log.levels.INFO)
        return
      end
      ui.open_scratch(ui.to_lines(res.stdout), { title = "specs://diff/" .. name, filetype = "diff" })
    end)
  )
end

--- Bootstrap a spec-kit project with `specify init`.
--- @param root string
--- @param args string[] passthrough args
--- @param cb fun(ok: boolean, err: string|nil)
function M.init(root, args, cb)
  local cmd = { config.options.speckit.cmd, "init" }
  vim.list_extend(cmd, args)
  vim.system(
    cmd,
    { cwd = root, text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        ui.notify(vim.trim(res.stderr ~= "" and res.stderr or "specify init failed"), vim.log.levels.ERROR)
        cb(false, "init failed")
        return
      end
      cb(true, nil)
    end)
  )
end

return M
