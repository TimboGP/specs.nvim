--- Command registration. Kept minimal so the plugin is lazy-load friendly:
--- real work is require()'d only when a command runs.
if vim.g.loaded_specs then
  return
end
vim.g.loaded_specs = true

if vim.fn.has("nvim-0.10") ~= 1 then
  vim.notify("specs.nvim requires Neovim >= 0.10", vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command("Specs", function(opts)
  require("specs.commands").dispatch(opts)
end, {
  nargs = "*",
  desc = "Specs: browse changes/specs, validate, status, new, archive, view",
  complete = function(arg_lead, cmd_line)
    return require("specs.commands").complete(arg_lead, cmd_line)
  end,
})
