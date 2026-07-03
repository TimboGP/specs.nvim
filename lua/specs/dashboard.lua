--- Native, navigable dashboard: a persistent, collapsible tree of changes and
--- specs (undotree-style) with a jump-to preview pane. Replaces shelling out to
--- the external `openspec view` terminal, which was a one-shot, non-interactive
--- printout that vanished with the job.
local cli = require("specs.cli")
local ui = require("specs.ui")
local actions = require("specs.actions")
local config = require("specs.config")

local M = {}

local ICON_EXPANDED = "▾"
local ICON_COLLAPSED = "▸"
local ICON_LEAF = " "

-- One entry per open dashboard buffer: { tree, line_map, expanded, win, preview_win, preview_buf }
local state = {}

local function change_icon(status)
  local by_status = { complete = "✓", ["in-progress"] = "◐", ["no-tasks"] = "○" }
  return by_status[status] or "•"
end

local function artifact_icon(status)
  local by_status = { ready = "✓", blocked = "⋯", complete = "✓", pending = "○" }
  return by_status[status] or "•"
end

--- Fetch and shape a change's artifact checklist into leaf nodes (lazy child loader).
--- @param node table the change node being expanded
--- @param cb fun() called once node.children is populated
local function load_change_children(node, cb)
  cli.run_json({ "status", "--change", node.name }, function(data, err)
    local kids = {}
    if err or not data then
      kids[1] = { key = node.key .. ":err", kind = "info", label = "(status unavailable)", expandable = false }
    else
      for _, a in ipairs(data.artifacts or {}) do
        local line = ("%s %-10s %s"):format(artifact_icon(a.status), a.status, a.id)
        if a.missingDeps and #a.missingDeps > 0 then
          line = line .. "  (needs: " .. table.concat(a.missingDeps, ", ") .. ")"
        end
        table.insert(kids, { key = node.key .. ":" .. a.id, kind = "artifact", label = line, expandable = false })
      end
      if #kids == 0 then
        kids[1] = { key = node.key .. ":none", kind = "info", label = "(no artifacts)", expandable = false }
      end
    end
    node.children = kids
    node.loaded = true
    cb()
  end)
end

--- Build the two-section root tree from `list` data, restoring expand state by key.
--- @param changes table[]
--- @param specs table[]
--- @param expanded table<string, boolean>
local function build_tree(changes, specs, expanded)
  local change_nodes = {}
  for _, c in ipairs(changes) do
    local key = "change:" .. c.name
    table.insert(change_nodes, {
      key = key,
      kind = "change",
      name = c.name,
      label = ("%s %-40s %d/%d"):format(change_icon(c.status), c.name, c.completedTasks or 0, c.totalTasks or 0),
      expandable = true,
      expanded = expanded[key] or false,
      loaded = false,
      children = {},
      load = load_change_children,
    })
  end

  local spec_nodes = {}
  for _, s in ipairs(specs) do
    local name = type(s) == "string" and s or (s.name or s.id)
    table.insert(spec_nodes, {
      key = "spec:" .. name,
      kind = "spec",
      name = name,
      label = "▪ " .. name,
      expandable = false,
    })
  end

  return {
    {
      key = "section:changes",
      kind = "section",
      label = ("Changes (%d)"):format(#change_nodes),
      expandable = true,
      expanded = expanded["section:changes"] ~= false,
      loaded = true,
      children = change_nodes,
    },
    {
      key = "section:specs",
      kind = "section",
      label = ("Specs (%d)"):format(#spec_nodes),
      expandable = true,
      expanded = expanded["section:specs"] ~= false,
      loaded = true,
      children = spec_nodes,
    },
  }
end

local function render(buf)
  local st = state[buf]
  if not st then
    return
  end
  local lines, line_map = {}, {}

  local function walk(nodes, depth)
    for _, node in ipairs(nodes) do
      local indent = string.rep("  ", depth)
      local marker = node.expandable and (node.expanded and ICON_EXPANDED or ICON_COLLAPSED) or ICON_LEAF
      table.insert(lines, indent .. marker .. " " .. node.label)
      line_map[#lines] = node
      if node.expandable and node.expanded then
        if node.loaded then
          walk(node.children, depth + 1)
        else
          table.insert(lines, indent .. "    loading…")
        end
      end
    end
  end
  walk(st.tree, 0)

  st.line_map = line_map
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function node_at_cursor(buf, win)
  local st = state[buf]
  if not st or not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local line = vim.api.nvim_win_get_cursor(win)[1]
  return st.line_map[line]
end

local function ensure_preview_win(st)
  if st.preview_win and vim.api.nvim_win_is_valid(st.preview_win) then
    return st.preview_win
  end
  local current = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(st.win)
  vim.cmd("rightbelow vsplit")
  st.preview_win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.api.nvim_win_set_buf(st.preview_win, buf)
  st.preview_buf = buf
  if vim.api.nvim_win_is_valid(current) then
    vim.api.nvim_set_current_win(current)
  end
  return st.preview_win
end

local function preview_node(buf, node)
  local st = state[buf]
  ensure_preview_win(st)
  actions.show_text(node.name, node.kind, function(text)
    if not vim.api.nvim_buf_is_valid(st.preview_buf) then
      return
    end
    vim.bo[st.preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(st.preview_buf, 0, -1, false, ui.to_lines(text or "(no preview)"))
    vim.bo[st.preview_buf].modifiable = false
  end)
end

local function toggle_node(buf, win)
  local node = node_at_cursor(buf, win)
  if not node or not node.expandable then
    return
  end
  local st = state[buf]
  node.expanded = not node.expanded
  st.expanded[node.key] = node.expanded
  if node.expanded and not node.loaded then
    render(buf) -- show "loading…" immediately
    node.load(node, function()
      if vim.api.nvim_buf_is_valid(buf) then
        render(buf)
      end
    end)
    return
  end
  render(buf)
end

local function select_node(buf, win)
  local node = node_at_cursor(buf, win)
  if not node then
    return
  end
  if node.kind == "change" or node.kind == "spec" then
    preview_node(buf, node)
  elseif node.expandable then
    toggle_node(buf, win)
  end
end

local function run_action_on_node(buf, win, action)
  local node = node_at_cursor(buf, win)
  if not node or (node.kind ~= "change" and node.kind ~= "spec") then
    return
  end
  if action == "validate" then
    actions.validate(node.name)
  elseif action == "status" then
    actions.status(node.name)
  elseif action == "archive" then
    actions.archive(node.name, function()
      M.refresh(buf)
    end)
  end
end

--- Refresh a dashboard buffer's data from the CLI, preserving expand state.
--- @param buf integer
function M.refresh(buf)
  local st = state[buf]
  if not st then
    return
  end
  cli.run_json({ "list" }, function(cdata, cerr)
    local changes = (not cerr and cdata and cdata.changes) or {}
    cli.run_json({ "list", "--specs" }, function(sdata, serr)
      local specs = (not serr and sdata and sdata.specs) or {}
      if not state[buf] then
        return
      end
      st.tree = build_tree(changes, specs, st.expanded)
      render(buf)
    end)
  end)
end

--- Close a dashboard's window(s); the buffer wipes itself via BufWipeout.
--- @param buf integer
function M.close(buf)
  local st = state[buf]
  if not st then
    return
  end
  if st.preview_win and vim.api.nvim_win_is_valid(st.preview_win) then
    pcall(vim.api.nvim_win_close, st.preview_win, true)
  end
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    pcall(vim.api.nvim_win_close, st.win, true)
  end
end

--- Open the dashboard, or focus it if already open. Stays open — including across
--- expand/collapse and preview navigation — until the user closes it with `q`.
function M.open()
  for buf, st in pairs(state) do
    if st.win and vim.api.nvim_win_is_valid(st.win) then
      vim.api.nvim_set_current_win(st.win)
      return
    end
    state[buf] = nil
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "specs-dashboard"
  pcall(vim.api.nvim_buf_set_name, buf, "specs://dashboard")

  vim.cmd(config.options.dashboard.split)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap = false
  vim.wo[win].signcolumn = "no"

  state[buf] = { tree = {}, line_map = {}, expanded = {}, win = win }

  local function keymap(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end
  keymap("<CR>", function()
    select_node(buf, win)
  end)
  keymap("o", function()
    toggle_node(buf, win)
  end)
  keymap("<Tab>", function()
    toggle_node(buf, win)
  end)
  keymap("R", function()
    M.refresh(buf)
  end)
  keymap("q", function()
    M.close(buf)
  end)
  local maps = config.options.picker.mappings
  keymap(maps.validate, function()
    run_action_on_node(buf, win, "validate")
  end)
  keymap(maps.status, function()
    run_action_on_node(buf, win, "status")
  end)
  keymap(maps.archive, function()
    run_action_on_node(buf, win, "archive")
  end)
  keymap(maps.new, function()
    actions.new_change(nil, function()
      M.refresh(buf)
    end)
  end)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      local st = state[buf]
      state[buf] = nil
      if st and st.preview_win and vim.api.nvim_win_is_valid(st.preview_win) then
        pcall(vim.api.nvim_win_close, st.preview_win, true)
      end
    end,
  })

  M.refresh(buf)
end

return M
