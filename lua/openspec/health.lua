--- :checkhealth openspec
local config = require("openspec.config")
local cli = require("openspec.cli")

local M = {}

-- Support both the modern (vim.health.start) and legacy (report_*) APIs.
local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

function M.check()
  start("openspec.nvim")

  local cmd = config.options.cmd
  if vim.fn.executable(cmd) == 1 then
    local res = vim.system({ cmd, "--version" }, { text = true }):wait()
    local version = res.code == 0 and vim.trim(res.stdout) or "unknown version"
    ok(("`%s` found (%s)"):format(cmd, version))
  else
    error(("`%s` not found on PATH"):format(cmd), {
      "Install OpenSpec: https://github.com/Fission-AI/OpenSpec",
      "Or set `cmd` to an absolute path in setup{}",
    })
  end

  if pcall(require, "telescope") then
    ok("telescope.nvim is installed (pickers enabled)")
  else
    warn("telescope.nvim not found — :OpenSpec changes/specs pickers are unavailable", {
      "Install nvim-telescope/telescope.nvim to enable the visual list UI",
    })
  end

  local root = cli.root(vim.uv.cwd())
  if root then
    ok("Inside an OpenSpec project: " .. root)
  else
    warn("Current directory is not inside an OpenSpec project", {
      "Run `:OpenSpec init` to initialize one",
    })
  end
end

return M
