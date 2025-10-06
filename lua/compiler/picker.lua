--- ### Picker frontend for compiler.nvim
-- Automatically detects and uses telescope.nvim or falls back to vim.ui.select

local M = {}

function M.show()
  local telescope_ok = pcall(require, "telescope")

  if telescope_ok then
    require("compiler.telescope").show()
  else
    -- Fallback to vim.ui.select implementation
    -- If working directory is home, don't open picker.
    if vim.loop.os_homedir() == vim.loop.cwd() then
      vim.notify(
        "You must :cd your project dir first.\nHome is not allowed as working dir.",
        vim.log.levels.WARN,
        {
          title = "Compiler.nvim",
        }
      )
      return
    end

    local utils = require("compiler.utils")
    local utils_bau = require("compiler.utils-bau")

    local buffer = vim.api.nvim_get_current_buf()
    local filetype =
      vim.api.nvim_get_option_value("filetype", { buf = buffer })

    -- POPULATE
    -- ========================================================================

    -- Programatically require the backend for the current language.
    local language = utils.require_language(filetype)

    -- On unsupported languages, default to make.
    if not language then language = utils.require_language("make") or {} end

    -- Also show options discovered on Makefile, Cmake... and other bau.
    if not language.bau_added then
      language.bau_added = true
      local bau_opts = utils_bau.get_bau_opts()

      -- Insert a separator for every bau.
      local last_bau_value = nil
      for _, item in ipairs(bau_opts) do
        if last_bau_value ~= item.bau then
          table.insert(language.options, { text = "", value = "separator" })
          last_bau_value = item.bau
        end
        table.insert(language.options, item)
      end
    end

    -- Add numbers in front of the options to display.
    local index_counter = 0
    for _, option in ipairs(language.options) do
      if option.value ~= "separator" then
        index_counter = index_counter + 1
        option.text = index_counter .. " - " .. option.text
      end
    end

    -- Create items for vim.ui.select (filter out separators)
    local items = {}
    local item_map = {}
    for _, option in ipairs(language.options) do
      if option.value ~= "separator" then
        table.insert(items, option.text)
        item_map[option.text] = { value = option.value, bau = option.bau }
      end
    end

    -- SHOW VIM.UI.SELECT
    -- ========================================================================
    vim.ui.select(items, {
      prompt = "Compiler: ",
    }, function(choice)
      if not choice then return end
      local selected = item_map[choice]
      if not selected or selected.value == "" then return end

      -- Do the selected option belong to a build automation utility?
      local bau = selected.bau
      if bau then -- call the bau backend.
        bau = utils_bau.require_bau(bau)
        if bau then bau.action(selected.value) end
        -- then
        -- clean redo (language)
        _G.compiler_redo_selection = nil
        -- save redo (bau)
        _G.compiler_redo_bau_selection = selected.value
        _G.compiler_redo_bau = bau
      else -- call the language backend.
        language.action(selected.value)
        -- then
        -- save redo (language)
        _G.compiler_redo_selection = selected.value
        _G.compiler_redo_filetype = filetype
        -- clean redo (bau)
        _G.compiler_redo_bau_selection = nil
        _G.compiler_redo_bau = nil
      end
    end)
  end
end

return M
