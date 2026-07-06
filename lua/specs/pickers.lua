--- Telescope pickers — the visual, list-style core of specs.nvim.
--- Soft-depends on telescope.nvim: functions no-op with a notice if it's absent.
local provider = require("specs.provider")
local ui = require("specs.ui")
local actions_mod = require("specs.actions")
local config = require("specs.config")

local M = {}

--- Lazily require telescope pieces; returns nil (and notifies) when unavailable.
local function tele()
  local ok, _ = pcall(require, "telescope")
  if not ok then
    ui.notify("telescope.nvim is required for pickers", vim.log.levels.WARN)
    return nil
  end
  return {
    pickers = require("telescope.pickers"),
    finders = require("telescope.finders"),
    conf = require("telescope.config").values,
    previewers = require("telescope.previewers"),
    actions = require("telescope.actions"),
    action_state = require("telescope.actions.state"),
  }
end

-- Status glyph for a change entry.
local function change_icon(change)
  local by_status = {
    complete = "✓",
    ["in-progress"] = "◐",
    ["no-tasks"] = "○",
  }
  return by_status[change.status] or "•"
end

--- Build a buffer previewer that renders an item's `show` markdown.
--- @param t table telescope modules
--- @param typ string|nil item type for show
--- @param title string previewer title
local function show_previewer(t, typ, title)
  return t.previewers.new_buffer_previewer({
    title = title or "Preview",
    define_preview = function(self, entry)
      local buf = self.state.bufnr
      vim.bo[buf].filetype = "markdown"
      actions_mod.show_text(entry.value, typ, function(text)
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, ui.to_lines(text or "(no preview)"))
      end)
    end,
  })
end

--- Generic picker builder shared by changes() and specs().
--- @param cfg table { title, items, entry_maker, typ, refresh }
local function build(t, opts, cfg)
  opts = opts or {}
  local maps = config.options.picker.mappings

  local function refresh_picker(prompt_bufnr)
    t.actions.close(prompt_bufnr)
    cfg.refresh(opts)
  end

  t.pickers
    .new(opts, {
      prompt_title = cfg.title,
      finder = t.finders.new_table({
        results = cfg.items,
        entry_maker = cfg.entry_maker,
      }),
      sorter = t.conf.generic_sorter(opts),
      previewer = show_previewer(t, cfg.typ, cfg.preview_title),
      attach_mappings = function(prompt_bufnr, map)
        -- <CR>: open full markdown detail in a split.
        t.actions.select_default:replace(function()
          local entry = t.action_state.get_selected_entry()
          t.actions.close(prompt_bufnr)
          if entry then
            actions_mod.show(entry.value, cfg.typ)
          end
        end)

        local function selected()
          local entry = t.action_state.get_selected_entry()
          return entry and entry.value
        end

        map({ "i", "n" }, maps.validate, function()
          local name = selected()
          t.actions.close(prompt_bufnr)
          actions_mod.validate(name)
        end)
        map({ "i", "n" }, maps.status, function()
          local name = selected()
          t.actions.close(prompt_bufnr)
          actions_mod.status(name)
        end)
        map({ "i", "n" }, maps.archive, function()
          local name = selected()
          actions_mod.archive(name, function()
            refresh_picker(prompt_bufnr)
          end)
        end)
        map({ "i", "n" }, maps.new, function()
          actions_mod.new_change(nil, function()
            refresh_picker(prompt_bufnr)
          end)
        end)
        return true
      end,
    })
    :find()
end

--- Picker over active changes (OpenSpec) / features (spec-kit).
--- @param opts table|nil telescope opts
function M.changes(opts)
  local t = tele()
  if not t then
    return
  end
  local p = provider.resolve()
  if not p then
    ui.notify("Not in a spec project (OpenSpec or spec-kit) — run :Specs init", vim.log.levels.WARN)
    return
  end
  local titles = { openspec = "OpenSpec Changes", speckit = "spec-kit Features" }
  p.impl.list_changes(p.root, function(items, err)
    if err then
      return
    end
    items = items or {}
    if #items == 0 then
      ui.notify("No changes found", vim.log.levels.INFO)
      return
    end
    build(t, opts, {
      title = titles[p.name] or "Changes",
      preview_title = "Preview",
      typ = "change",
      items = items,
      refresh = M.changes,
      entry_maker = function(c)
        local counts = ("%d/%d"):format(c.completedTasks or 0, c.totalTasks or 0)
        return {
          value = c.name,
          ordinal = c.name,
          display = ("%s %-40s %s"):format(change_icon(c), c.name, counts),
        }
      end,
    })
  end)
end

--- Picker over specifications (OpenSpec) / constitution + memory docs (spec-kit).
--- @param opts table|nil telescope opts
function M.specs(opts)
  local t = tele()
  if not t then
    return
  end
  local p = provider.resolve()
  if not p then
    ui.notify("Not in a spec project (OpenSpec or spec-kit) — run :Specs init", vim.log.levels.WARN)
    return
  end
  p.impl.list_specs(p.root, function(items, err)
    if err then
      return
    end
    items = items or {}
    if #items == 0 then
      ui.notify("No " .. p.caps.specs_section:lower() .. " docs found", vim.log.levels.INFO)
      return
    end
    build(t, opts, {
      title = (p.name == "speckit") and ("spec-kit — " .. p.caps.specs_section) or "OpenSpec Specs",
      preview_title = "Preview",
      typ = "spec",
      items = items,
      refresh = M.specs,
      entry_maker = function(s)
        -- Specs may be plain strings or objects with a name/id.
        local name = type(s) == "string" and s or (s.name or s.id)
        return {
          value = name,
          ordinal = name,
          display = "▪ " .. name,
        }
      end,
    })
  end)
end

return M
