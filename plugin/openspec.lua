--- Command registration. Kept minimal so the plugin is lazy-load friendly:
--- real work is require()'d only when a command runs.
if vim.g.loaded_openspec then
  return
end
vim.g.loaded_openspec = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("openspec.nvim requires Neovim >= 0.10", vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command("OpenSpec", function(opts)
  require("openspec.commands").dispatch(opts)
end, {
  nargs = "*",
  desc = "OpenSpec: browse changes/specs, validate, status, new, archive, view",
  complete = function(arg_lead, cmd_line)
    return require("openspec.commands").complete(arg_lead, cmd_line)
  end,
})
