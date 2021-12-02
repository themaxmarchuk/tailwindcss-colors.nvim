-- Credits: contains some code snippets from https://github.com/norcalli/nvim-colorizer.lua
local colors = require("tailwindcss-colors.colors")

-- NOTE: should only create a namespace if it's not already created when attaching to a buffer
local NAMESPACE = vim.api.nvim_create_namespace("tailwindcss-colors")

-- Prefix ensures names do not collide with other plugins
local HIGHLIGHT_NAME_PREFIX = "tailwindcss_colors"
local HIGHLIGHT_MODE_NAMES = { background = "mb", foreground = "mf" }

-- This table is used to store the names of highlight colors that have already
-- been created, allowing us to reuse highlights even across multiple buffers,
-- cutting down on the the ammount of neovim command calls
local HIGHLIGHT_CACHE = {}

--- Make a deterministic name for a highlight given these attributes
-- NOTE: this looks like lsp_documentColor_mf_FFAAFF
-- NOTE: prefix may be redundant, see how other plugins do it
local function make_highlight_name(rgb, mode)
  return table.concat({ HIGHLIGHT_NAME_PREFIX, HIGHLIGHT_MODE_NAMES[mode], rgb }, "_")
end

local function create_highlight(rgb_hex, options)
  -- pull highlight from cache if it exists to avoid any neovim commands
  -- otherwise run the commands and stoore the name as a cache
  local mode = options.mode or "background"
  local cache_key = table.concat({ HIGHLIGHT_MODE_NAMES[mode], rgb_hex }, "_")
  local highlight_name = HIGHLIGHT_CACHE[cache_key]

  if highlight_name then
    return highlight_name
  end

  -- Create the highlight
  -- NOTE: our highlights are only goingt o be background highlights
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

-- Stores attached buffers that we are in the process of highlightings
local ATTACHED_BUFFERS = {}

-- Stores latest hashed color data received from the LSP for each buffer
-- hashing is done to save space and make comparisons faster
-- this allows us to limit updates to buffer highlights
--
-- since hashing is annoying due to the data being unordered
-- we can just create a string based on converted color data
-- this will still allow us to limit buffer highlight updates
-- but will require color reprocessing
--
-- once color info is converted, we can store packed data for comparisons
-- could also even hash this data if we wanted to save on memory space and speed
-- technically there is hasing going on already in the tables, so we use the computed data
-- as a key, however we also need a list of active buffers
local LSP_CACHE = {}
local LSP_CACHE_LENGTH = 0

-- Create a cache_key string using the data, so it can be used to lookup
-- existing_bufs cache entries
local function make_lsp_cache_key(lsp_data)
  return
    lsp_data.color.hex ..
    "ec" ..
    lsp_data.range["end"].character ..
    "el" ..
    lsp_data.range["end"].line ..
    "sc" ..
    lsp_data.range.start.character ..
    "sl" ..
    lsp_data.range.start.line
end

local function buf_set_highlights(bufnr, lsp_data, options)
  local cache_invalid = false
  -- add hex data to each entry color entry
  for _, color_range_info in ipairs(lsp_data) do
    color_range_info.color = colors.lsp_color_to_hex(color_range_info.color)
  end
  -- check the length of the cache compared to the length of lsp_data
  if LSP_CACHE_LENGTH ~= #lsp_data then
    cache_invalid = true
  else
    -- check to see if cache is valid, in which case we do nothing
    for _, color_range_info in ipairs(lsp_data) do
      -- compute cache key (string)
      local cache_key = make_lsp_cache_key(color_range_info)

      -- if the entry is missing, the cache is immediately considered invalid
      if not LSP_CACHE[cache_key] then
        cache_invalid = true
        break
      end
    end
  end

  -- if the cache is invalid, color data changed in some way, so it needs to be rebuilt
  if cache_invalid then
    print("cache invalidated resetting highlights")
    -- clear the exisiting cache
    LSP_CACHE = {}
    -- clear all existing highlights
    vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)

    -- rebuild highlights and cache
    for _, color_range_info in pairs(lsp_data) do
      -- add the cache entry
      LSP_CACHE[make_lsp_cache_key(color_range_info)] = true

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

  if not cache_invalid then
    print("validated cache, nothing to do")
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
  -- NOTE: do not update highlights if there's nothing to update, we can save the last
  -- results from the server as another cache, to speed things up and avoid nvim commands like
  -- the plauge
  vim.lsp.buf_request(bufnr, "textDocument/documentColor", params, function(err, result, _, _)
    -- if there were no errors, update highlights
    if err == nil and result ~= nil then
      buf_set_highlights(bufnr, result, options)
    end
  end)
end

-- This function attaches to a buffer and hooks for line changes
function M.buf_attach(bufnr, options)
  -- if bufnr is 0 or nil, use the current buffer
  bufnr = expand_bufnr(bufnr)

  -- if we have already attached to this buffer do nothing
  if ATTACHED_BUFFERS[bufnr] then
    return
  end

  ATTACHED_BUFFERS[bufnr] = true

  -- if we didn't get any options make it an empty table
  options = options or {}

  -- TODO: figure out the debouncing sititation, do we really need it?
  -- make a smart way to react, why debounce when we can just react and send a messages
  -- to the server anyways
  -- VSCode extension also does 200ms debouncing
  local trigger_update_highlight, timer = require("tailwindcss-colors.defer").debounce_trailing(
    M.update_highlight,
    options.debounce or 200,
    false
  )

  -- for the first request, the server needs some time before it's ready
  -- sometimes 200ms is not enough for this
  -- TODO: figure out when the first request can be send
  trigger_update_highlight(bufnr, options)

  -- setup a hook for any changes in the buffer
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      -- if the current buffer is not attached, then tell nvim to detach our function
      if not ATTACHED_BUFFERS[bufnr] then
        return true
      end
      -- trigger updates to the highlights
      -- NOTE: to make this fast AF we need to determine if there were actual changes in what
      -- we get back from the lsp before we tear down the highlights and rebuild them!
      trigger_update_highlight(bufnr, options)
    end,
    on_detach = function()
      -- close the timer (only need this for the debounce thing)
      timer:close()
      -- remove buffer from attached list
      ATTACHED_BUFFERS[bufnr] = nil
    end,
  })
end

-- Detaches from the buffer
function M.buf_detach(bufnr)
  -- if bufnr is 0 or nil, use the current buffer
  bufnr = expand_bufnr(bufnr)
  -- clear our namespace from the buffer
  -- we can assume that since we were attached, the buffer must have our namespace
  -- so there is no point to check (plus vim will handle the error for us :glasses:)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  ATTACHED_BUFFERS[bufnr] = nil
end

return M
