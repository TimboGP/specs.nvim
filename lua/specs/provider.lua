--- Backend resolution: detect whether a directory belongs to an OpenSpec or a
--- spec-kit project and hand back the matching provider implementation. The rest
--- of the plugin talks to providers through this module and never assumes a
--- particular backend.
---
--- Every provider module (`specs.providers.openspec`, `specs.providers.speckit`)
--- implements the same interface. All methods take the project `root` as their
--- first argument so providers stay stateless; async ones use the existing
--- callback style, `cb(data, err)`.
---
---   capabilities()                 -> { specs_section, archive, diff, validate, new_hint }
---   list_changes(root, cb)         -> cb(list<{name,status,completedTasks,totalTasks}>, err)
---   list_specs(root, cb)           -> cb(list<{name}|string>, err)
---   names_sync(root)               -> string[]        (best-effort, for completion)
---   show(root, name, kind, cb)     -> cb(text|nil, err)
---   status(root, name, cb)         -> cb({schemaName,isComplete,changeName,
---                                         artifacts=<{id,status,path,missingDeps}>}, err)
---   validate(root, name, cb)       -> cb(qf_items<{filename,lnum,text,type}>, err)
---   new(root, input, cb)           -> cb(name|nil, err)
---   first_artifact(root, name, cb) -> cb({id,path,schema}|nil, err)
---   seed_template(root, bufnr, artifact)                (fills an empty buffer)
---   archive(root, name, cb)        -> cb(ok, err)
---   diff(root, name)                                   (owns its own tab/diff UI)
---   init(root, args, cb)           -> cb(ok, err)
local config = require("specs.config")

local M = {}

-- Cache of resolved backends keyed by the starting directory. `false` marks a
-- directory that resolved to no project (so we don't re-walk the tree each call).
local cache = {}

--- Nearest ancestor directory (inclusive) that contains a child directory `name`.
--- @param start string
--- @param name string
--- @return string|nil root the directory holding `name`
local function dir_with_child(start, name)
  local found = vim.fs.find(name, { path = start, upward = true, type = "directory", limit = 1 })[1]
  return found and vim.fs.dirname(found) or nil
end

--- Does `dir` contain at least one numbered feature folder (e.g. `001-foo`)?
--- @param dir string
--- @return boolean
local function has_numbered_child(dir)
  local ok, iter = pcall(vim.fs.dir, dir)
  if not ok then
    return false
  end
  for name, typ in iter do
    if typ == "directory" and name:match("^%d") then
      return true
    end
  end
  return false
end

--- Find a spec-kit project root by walking up from `start`. A `.specify/`
--- directory is the strong signal; failing that, a `specs/` dir that already
--- holds numbered feature folders counts too.
--- @param start string
--- @return string|nil
local function speckit_root(start)
  local specify = dir_with_child(start, ".specify")
  if specify then
    return specify
  end
  local specs_parent = dir_with_child(start, config.options.speckit.specs_dir)
  if specs_parent and has_numbered_child(specs_parent .. "/" .. config.options.speckit.specs_dir) then
    return specs_parent
  end
  return nil
end

--- Detect the backend for `start`, honoring a forced `config.provider`.
--- @param start string
--- @return string|nil kind "openspec" | "speckit"
--- @return string|nil root
local function detect(start)
  local forced = config.options.provider
  if forced == "openspec" then
    return "openspec", dir_with_child(start, "openspec")
  elseif forced == "speckit" then
    return "speckit", speckit_root(start)
  end

  local os_root = dir_with_child(start, "openspec")
  local sk_root = speckit_root(start)
  if os_root and sk_root then
    -- Nested projects: the deeper (longer path) root is the closer one; ties go
    -- to OpenSpec to preserve pre-spec-kit behavior.
    if #sk_root > #os_root then
      return "speckit", sk_root
    end
    return "openspec", os_root
  end
  if os_root then
    return "openspec", os_root
  end
  if sk_root then
    return "speckit", sk_root
  end
  return nil, nil
end

--- Starting directory for detection: the current buffer's dir, else cwd.
--- @param start string|nil
--- @return string
local function normalize_start(start)
  start = start or vim.fn.expand("%:p:h")
  if start == "" then
    start = vim.uv.cwd()
  end
  return start
end

--- @class SpecsProvider
--- @field name string        "openspec" | "speckit"
--- @field root string        absolute project root
--- @field impl table         the provider module
--- @field caps table         impl.capabilities()

--- Resolve the backend for `start`. Returns nil (once, quietly) when the
--- directory isn't inside any spec project — callers surface the message.
--- @param start string|nil
--- @return SpecsProvider|nil
function M.resolve(start)
  start = normalize_start(start)
  local cached = cache[start]
  if cached ~= nil then
    return cached or nil
  end

  local kind, root = detect(start)
  if not kind or not root then
    cache[start] = false
    return nil
  end

  local impl = require("specs.providers." .. kind)
  local resolved = { name = kind, root = root, impl = impl, caps = impl.capabilities() }
  cache[start] = resolved
  return resolved
end

--- The backend to initialize a *new* project with (no root exists yet). Uses the
--- forced provider, defaulting to OpenSpec under "auto" for backward compatibility.
--- @return SpecsProvider
function M.for_init()
  local kind = config.options.provider
  if kind ~= "openspec" and kind ~= "speckit" then
    kind = "openspec"
  end
  local impl = require("specs.providers." .. kind)
  return { name = kind, root = vim.uv.cwd(), impl = impl, caps = impl.capabilities() }
end

--- Clear the resolution cache (call after init/archive change the project layout).
function M.clear_cache()
  cache = {}
end

return M
