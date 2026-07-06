--- :checkhealth specs
local config = require("specs.config")
local provider = require("specs.provider")

local M = {}

-- Support both the modern (vim.health.start) and legacy (report_*) APIs.
local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn

function M.check()
  start("specs.nvim")

  ok("provider mode: " .. config.options.provider)

  -- OpenSpec CLI (drives the OpenSpec backend).
  local os_cmd = config.options.cmd
  if vim.fn.executable(os_cmd) == 1 then
    local res = vim.system({ os_cmd, "--version" }, { text = true }):wait()
    local version = res.code == 0 and vim.trim(res.stdout) or "unknown version"
    ok(("`%s` (OpenSpec CLI) found (%s)"):format(os_cmd, version))
  else
    warn(("`%s` (OpenSpec CLI) not found on PATH"):format(os_cmd), {
      "Only needed for OpenSpec projects",
      "Install OpenSpec: https://github.com/Fission-AI/OpenSpec",
      "Or set `cmd` to an absolute path in setup{}",
    })
  end

  -- spec-kit CLI (optional — only used by `:Specs init`/`new` fallbacks).
  local sk_cmd = config.options.speckit.cmd
  if vim.fn.executable(sk_cmd) == 1 then
    ok(("`%s` (spec-kit CLI) found"):format(sk_cmd))
  else
    warn(("`%s` (spec-kit CLI) not found on PATH"):format(sk_cmd), {
      "Only needed for `:Specs init` in spec-kit projects (reads are pure filesystem)",
      "Install spec-kit: https://github.com/github/spec-kit",
    })
  end

  if pcall(require, "telescope") then
    ok("telescope.nvim is installed (pickers enabled)")
  else
    warn("telescope.nvim not found — :Specs changes/specs pickers are unavailable", {
      "Install nvim-telescope/telescope.nvim to enable the visual list UI",
    })
  end

  local p = provider.resolve(vim.uv.cwd())
  if p then
    ok(("Inside a %s project: %s"):format(p.name, p.root))
    if p.name == "speckit" then
      local script = p.root .. "/.specify/scripts/bash/create-new-feature.sh"
      if vim.uv.fs_stat(script) then
        ok("spec-kit helper scripts present (`:Specs new` will use create-new-feature.sh)")
      else
        warn("spec-kit helper scripts not found under .specify/scripts/bash/", {
          "`:Specs new` falls back to a pure-Lua folder create (no git branch)",
        })
      end
    end
  else
    warn("Current directory is not inside a spec project (OpenSpec or spec-kit)", {
      "Run `:Specs init` to initialize one",
    })
  end
end

return M
