-- Credits: contains some code snippets from https://github.com/norcalli/nvim-colorizer.lua
local colors = require("tailwindcss-colors.colors")

-- NOTE: should only create a namespace if it's not already created when attaching to a buffer
local NAMESPACE = vim.api.nvim_create_namespace("lsp_documentColor")
-- NOTE: why do we need a prefix anyways? (to differenticate our highlights from other plugins?)
local HIGHLIGHT_NAME_PREFIX = "lsp_documentColor"
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

local ATTACHED_BUFFERS = {}

local function buf_set_highlights(bufnr, lsp_colors, options)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)

  for _, color_info in pairs(lsp_colors) do
    local rgb_hex = colors.lsp_color_to_hex(color_info.color)
    local highlight_name = create_highlight(rgb_hex, options)

    local range = color_info.range
    local line = range.start.line
    local start_col = range.start.character
    local end_col = options.single_column and start_col + 1 or range["end"].character

    vim.api.nvim_buf_add_highlight(bufnr, NAMESPACE, highlight_name, line, start_col, end_col)
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