-- Credits: contains some code snippets from https://github.com/norcalli/nvim-colorizer.lua
local colors = require("tailwindcss-colors.colors")

-- TODO: React to lsp ClearColors notification
-- TODO: Make it more efficient (don't bother validating cache if changed lines had no highlights)
-- TODO: Remove comments, clean things up
-- TODO: Improve function names and refactor
-- TODO: Add config options for (dark color, bright color, should inject commands)

-- NOTE: should only create a namespace if it's not already created when attaching to a buffer
local NAMESPACE = vim.api.nvim_create_namespace("tailwindcss-colors")

-- Prefix ensures names do not collide with other plugins
local HIGHLIGHT_NAME_PREFIX = "tailwindcss_colors"
local HIGHLIGHT_MODE_NAMES = { background = "mb", foreground = "mf" }

-- This table is used to store the names of highlight colors that have already
-- been created, allowing us to reuse highlights even across multiple buffers,
-- cutting down on the the amount of neovim command calls
local HIGHLIGHT_CACHE = {}

--- Make a deterministic name for a highlight given these attributes
-- NOTE: this looks like lsp_documentColor_mf_FFAAFF
-- NOTE: prefix may be redundant, see how other plugins do it
local function make_highlight_name(rgb, mode)
  return table.concat({ HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb }, "_")
end

local function create_highlight(rgb_hex, options)
  -- pull highlight from cache if it exists to avoid any neovim commands
  -- otherwise run the commands and store the name as a cache
  local mode = options.mode or "background"
  local cache_key = table.concat({ HIGHLIGHT_MODE_NAMES[mode], rgb_hex }, "_")
  local highlight_name = HIGHLIGHT_CACHE[cache_key]

  if highlight_name then
    return highlight_name
  end

  -- Create the highlight
  -- NOTE: our highlights are only going to be background highlights
  highlight_name = make_highlight_name(rgb_hex, mode)
  if mode == "foreground" then
    vim.api.nvim_command(string.format("highlight %s guifg=#%s", highlight_name, rgb_hex))
  else
    -- NOTE: we already had these numbers before, and are now converting back to them
    -- we should run this algorithm earlier and attach information about brightness
    local r, g, b = rgb_hex:sub(1, 2), rgb_hex:sub(3, 4), rgb_hex:sub(5, 6)
    r, g, b = tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)
    local fg_color
    if colors.color_is_bright(r, g, b) then
      fg_color = "Black"
    else
      fg_color = "White"
    end
    vim.api.nvim_command(string.format("highlight %s guifg=%s guibg=#%s", highlight_name, fg_color, rgb_hex))
  end
  HIGHLIGHT_CACHE[cache_key] = highlight_name

  return highlight_name
end

-- Stores attached buffers
local ATTACHED_BUFFERS = {}

-- Stores latest hashed color data received from the LSP for each buffer
-- hashing is done to save space and make comparisons faster
-- this allows us to limit updates to buffer highlights
--
-- since hashing entire objects is annoying due to the data being unordered
-- we can just create a string based on converted color data
-- this will still allow us to limit buffer highlight updates
-- but will require color reprocessing (hex strings) and string concatenation
--
-- once color info is converted, we can store packed data for comparisons
-- could also even hash this data if we wanted to save on memory space and speed
-- technically there is hashing going on already in the tables, so we use the computed data
-- as a key, however we also need a list of active buffers
--
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

local function buf_set_highlights(bufnr, lsp_data, options)
  -- add hex data to each color entry
  for _, color_range_info in ipairs(lsp_data) do
    color_range_info.color = colors.lsp_color_add_hex(color_range_info.color)
  end

  local cache = LSP_CACHE[bufnr]
  local cache_invalid = false

  -- check to see if cache exists
  if not cache then
    cache_invalid = true
  else
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
      local highlight_name = create_highlight(color_range_info.color.hex, options)

      -- extract range data
      local range = color_range_info.range
      local line = range.start.line
      local start_col = range.start.character
      local end_col = options.single_column and start_col + 1 or range["end"].character

      -- add the highlight to the namespace
      vim.api.nvim_buf_add_highlight(bufnr, NAMESPACE, highlight_name, line, start_col, end_col)
    end
  end
end

local M = {}

-- Returns current buffer if we find a 0 or nil
local function expand_bufnr(bufnr)
  if bufnr == 0 or bufnr == nil then
    return vim.api.nvim_get_current_buf()
  else
    return bufnr
  end
end

--- Can be called to manually update the color highlighting
function M.update_highlight(bufnr, options)
  -- make_text_document_params will get us the current document uri
  local params = { textDocument = vim.lsp.util.make_text_document_params() }
  -- send this to the lsp, and setup a callback that will trigger a highlight update
  vim.lsp.buf_request(bufnr, "textDocument/documentColor", params, function(err, result, _, _)
    -- if there were no errors, update highlights
    if err == nil and result ~= nil then
      buf_set_highlights(bufnr, result, options)
    end
  end)
end

-- This function attaches to a buffer and reacts to changes in buffer state
function M.buf_attach(bufnr, options)
  -- if bufnr is 0 or nil, use the current buffer
  bufnr = expand_bufnr(bufnr)

  -- if we have already attached to this buffer do nothing
  if ATTACHED_BUFFERS[bufnr] then
    return
  end

  ATTACHED_BUFFERS[bufnr] = true

  options = options or {}

  -- TODO: server ready time may vary
  -- so try sending a bunch of documentColor requests until it responds
  -- without an error, or a timeout is reached?
  -- NOTE: try logging in the clearColors handler to see when it's sent (maybe when the server is ready?)
  vim.defer_fn(function()
    M.update_highlight(bufnr, options)
  end, 300)

  -- setup a hook for any changes in the buffer
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      -- if the current buffer is not attached, then tell nvim to detach our function
      if not ATTACHED_BUFFERS[bufnr] then
        return true
      end
      M.update_highlight(bufnr, options)
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
      M.update_highlight(bufnr, options)
    end
  })
end

-- for debug only
function M.print_status()
  print(vim.inspect({ LSP_CACHE, ATTACHED_BUFFERS }))
end

-- Detaches from the buffer
function M.buf_detach(bufnr)
  -- if bufnr is 0 or nil, use the current buffer
  bufnr = expand_bufnr(bufnr)
  -- clear highlights
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  -- remove from attached list
  ATTACHED_BUFFERS[bufnr] = nil
  -- delete the cache
  LSP_CACHE[bufnr] = nil
end

return M
