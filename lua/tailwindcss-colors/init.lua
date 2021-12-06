-- Credits: contains some code snippets from https://github.com/norcalli/nvim-colorizer.lua
local colors = require("tailwindcss-colors.colors")

-- TODO: Update README with config/install stuff

local NAMESPACE = vim.api.nvim_create_namespace("tailwindcss-colors")

local HIGHLIGHT_NAME_PREFIX = "TailwindCssColor"

-- This table is used to store the names of highlight colors that have already
-- been created, allowing us to reuse highlights even across multiple buffers,
-- cutting down on the the amount of neovim command calls
local HIGHLIGHT_CACHE = {}

-- Default user configuration
local user_config = {
  colors = {
    dark = "#000000",  -- dark text color
    light = "#FFFFFF", -- light text color
  },
  commands = true -- should add commands
}

-- Creates highlights if they don't already exist
local function create_highlight(color)
  -- pull highlight from cache if it exists to avoid neovim highlight commands
  -- otherwise create the highlight and store the name (computed from the color)
  -- in the cache
  local highlight_name = HIGHLIGHT_CACHE[color.hex]

  if highlight_name then
    return highlight_name
  end


  -- determine which foreground color to use (dark or light)
  local fg_color
  if colors.color_is_bright(color) then
    fg_color = user_config.colors.dark
  else
    fg_color = user_config.colors.light
  end

  highlight_name = table.concat({ HIGHLIGHT_NAME_PREFIX, color.hex }, "_")

  -- create the highlight
  vim.api.nvim_command(string.format("highlight %s guifg=%s guibg=#%s", highlight_name, fg_color, color.hex))

  -- add the highlight to the cache to skip work next time
  HIGHLIGHT_CACHE[color.hex] = highlight_name

  return highlight_name
end

-- Stores attached buffers
local ATTACHED_BUFFERS = {}

-- Stores latest color data received from the LSP for each buffer
-- since lua tables use hashing under the hood, lookups should be fast
--
-- The layout looks like this: (the keys correspond to buffer numbers)
-- LSP_CACHE = {
--   [1] = { len = 1, data = {... CACHE HASH TABLE ...} },
--   [2] = { len = 5, data = {... CACHE HASH TABLE ...} },
-- }
local LSP_CACHE = {}

-- Create a cache_key string using the data, so it can be used to lookup
-- existing_bufs cache entries
local function make_lsp_cache_key(lsp_data)
  return
    lsp_data.color.hex ..
    lsp_data.range["end"].character ..
    lsp_data.range["end"].line ..
    lsp_data.range.start.character ..
    lsp_data.range.start.line
end

-- Updates the highlights in a buffer with the given lsp_data
-- checks cache to see if updates are required
local function buf_set_highlights(bufnr, lsp_data)
  -- add hex data to each color entry
  for _, color_range_info in ipairs(lsp_data) do
    color_range_info.color = colors.lsp_color_add_hex(color_range_info.color)
  end

  local cache = LSP_CACHE[bufnr]
  local cache_invalid = false

  -- check to see if cache exists
  if cache then
    -- if it does, try to validate the cache
    -- check the length of the cache compared to the length of lsp_data
    if cache.len ~= #lsp_data then
      cache_invalid = true
    else
      -- loop through the lsp_data and see if the cache contains the same data
      for _, color_range_info in ipairs(lsp_data) do
        -- compute cache key (string)
        local cache_key = make_lsp_cache_key(color_range_info)

        -- if the entry is missing, the cache is immediately considered invalid
        if not cache.data[cache_key] then
          cache_invalid = true
          break
        end
      end
    end
  else
    -- otherwise empty cache is "invalid"
    cache_invalid = true
  end

  -- if the cache is invalid, it must be rebuilt, and the highlights should be updated
  if cache_invalid then
    -- clear all existing highlights in the namespace
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)

    -- create a new cache table
    LSP_CACHE[bufnr] = { len = 0, data = {} }
    -- update the reference
    cache = LSP_CACHE[bufnr]

    -- loop through lsp_data
    for _, color_range_info in pairs(lsp_data) do
      -- add the cache entry
      cache.data[make_lsp_cache_key(color_range_info)] = true
      cache.len = cache.len + 1

      -- create the highlight
      local highlight_name = create_highlight(color_range_info.color)

      -- extract range data
      local range = color_range_info.range
      local line = range.start.line
      local start_col = range.start.character
      local end_col = range["end"].character

      -- add the highlight to the namespace
      vim.api.nvim_buf_add_highlight(bufnr, NAMESPACE, highlight_name, line, start_col, end_col)
    end
  end
end


-- Returns current buffer if 0 or nil
local function expand_bufnr(bufnr)
  if bufnr == 0 or bufnr == nil then
    return vim.api.nvim_get_current_buf()
  else
    return bufnr
  end
end

-- merges tables together
local function merge(...)
  local res = {}
  for i = 1,select("#", ...) do
    local o = select(i, ...)
    for k,v in pairs(o) do
      res[k] = v
    end
  end
  return res
end

local M = {}

-- Takes an optional plugin_config and adds commands if they are enabled
-- otherwise default settings are used, and calling the function is only necessary
-- if you want to add commands
function M.setup(plugin_config)
  -- merge passed in settings with defaults
  user_config = merge(user_config, plugin_config or {})

  -- remove commands if they should be disabled
  if not user_config.commands then
    vim.cmd("delcommand TailwindColorsAttach")
    vim.cmd("delcommand TailwindColorsDetach")
    vim.cmd("delcommand TailwindColorsRefresh")
    vim.cmd("delcommand TailwindColorsToggle")
  end
end

-- Updates the highlights in a buffer if the lsp responds with valid color data
function M.update_highlight(bufnr)
  -- get document uri
  local params = { textDocument = vim.lsp.util.make_text_document_params() }
  -- send this to the lsp
  vim.lsp.buf_request(bufnr, "textDocument/documentColor", params, function(err, result, _, _)
    -- if there were no errors, update highlights
    if err == nil and result ~= nil then
      buf_set_highlights(bufnr, result)
    end
  end)
end

-- This function attaches to a buffer, updating highlights on change
function M.buf_attach(bufnr)
  bufnr = expand_bufnr(bufnr)

  -- if we have already attached to this buffer do nothing
  if ATTACHED_BUFFERS[bufnr] then
    return
  end

  ATTACHED_BUFFERS[bufnr] = true

  -- 200ms debounce workaround, the server needs some time go get ready
  -- not deferring for 200ms results in the server not responding at all
  vim.defer_fn(function()
    M.update_highlight(bufnr)
  end, 200)

  -- setup a hook for any changes in the buffer
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      -- if the current buffer is not attached, then tell nvim to detach our function
      -- see :help nvim_buf_attach (on_lines section)
      if not ATTACHED_BUFFERS[bufnr] then
        return true
      end
      M.update_highlight(bufnr)
    end,
    on_detach = function()
      -- remove buffer from attached list
      ATTACHED_BUFFERS[bufnr] = nil
      -- delete the cache
      LSP_CACHE[bufnr] = nil
    end,
    on_reload = function ()
      -- invalidate the cache
      LSP_CACHE[bufnr] = nil
      -- trigger an update highlight
      M.update_highlight(bufnr)
    end
  })
end

-- Detaches from the buffer
function M.buf_detach(bufnr)
  bufnr = expand_bufnr(bufnr)
  -- clear highlights
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  -- remove from attached list
  ATTACHED_BUFFERS[bufnr] = nil
  -- delete the cache
  LSP_CACHE[bufnr] = nil
end

-- Attaches or detaches from the current buffer
function M.buf_toggle()
  local bufnr = expand_bufnr(0)

  if ATTACHED_BUFFERS[bufnr] then
    M.buf_detach(bufnr)
    return
  end

  M.buf_attach(bufnr)
end

return M
