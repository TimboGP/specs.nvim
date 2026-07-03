--- Rendering + notification helpers. The only module that opens windows/buffers.
local config = require("specs.config")

local M = {}

--- Notify with a consistent title, respecting config.notify.
--- @param msg string
--- @param level integer|nil vim.log.levels.* (default INFO)
function M.notify(msg, level)
  if not config.options.notify then
    return
  end
  vim.notify(msg, level or vim.log.levels.INFO, { title = "specs" })
end

--- Open a scratch buffer with the given lines.
--- @param lines string[]
--- @param opts table|nil { title?, filetype?, split? }
--- @return integer bufnr
function M.open_scratch(lines, opts)
  opts = opts or {}
  vim.cmd(opts.split or "botright vnew")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = opts.filetype or "markdown"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  if opts.title then
    pcall(vim.api.nvim_buf_set_name, buf, opts.title)
  end
  -- q closes the scratch window quickly.
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, nowait = true, silent = true })
  return buf
end

--- Split a possibly multi-line string into a list of lines (handles nil/empty).
--- @param text string|nil
--- @return string[]
function M.to_lines(text)
  if not text or text == "" then
    return { "" }
  end
  return vim.split(text, "\n", { plain = true })
end

return M
