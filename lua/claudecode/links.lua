--- Module for detecting and handling clickable links in Claude Code output
--- @module 'claudecode.links'

local M = {}

local logger = require("claudecode.logger")

-- Patterns for detecting different types of references
local PATTERNS = {
  -- File paths (both absolute and relative)
  file_path = {
    -- Absolute paths: /path/to/file.ext or /path/to/file.ext:line:col
    [[/[%w%._%-/]+%.%w+:?%d*:?%d*]],
    -- Relative paths: ./path/file.ext or path/file.ext or ../path/file.ext
    [[%.?%.?/?[%w%._%-/]+%.%w+:?%d*:?%d*]],
    -- Simple filename with extension
    [[%w+%.%w+:?%d*:?%d*]],
  },
  -- URLs
  url = {
    [[https?://[%w%._%-/?#%%&=]+]],
    [[file://[%w%._%-/]+]],
  },
  -- Git references
  git_ref = {
    [[%w+/[%w%._%-]+#%d+]], -- owner/repo#123
    [[#%d+]], -- #123 (issue/PR number)
  },
  -- Line references in format file:line or file:line:col
  line_ref = {
    [[([%w%._%-/]+):(%d+):?(%d*)]],
  }
}

-- Configuration for link handling
local config = {
  enable_file_links = true,
  enable_url_links = true,
  enable_git_links = true,
  auto_highlight = true,
  highlight_group = "Underlined",
  click_keymap = "<CR>",
  preview_keymap = "gp",
}

---Setup the links module with user configuration
---@param user_config table? Optional configuration overrides
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end
  
  -- Create highlight group if it doesn't exist
  if config.auto_highlight then
    vim.api.nvim_set_hl(0, "ClaudeCodeLink", {
      fg = "#569cd6", -- Light blue
      underline = true,
      default = true
    })
  end
end

---Parse a file reference that might include line and column numbers
---@param text string The text to parse
---@return table? parsed_ref Table with file, line, col if valid reference found
local function parse_file_reference(text)
  -- Try to match file:line:col pattern
  local file, line, col = text:match("^(.+):(%d+):(%d+)$")
  if file and line and col then
    return {
      file = file,
      line = tonumber(line),
      col = tonumber(col)
    }
  end
  
  -- Try to match file:line pattern
  file, line = text:match("^(.+):(%d+)$")
  if file and line then
    return {
      file = file,
      line = tonumber(line),
      col = nil
    }
  end
  
  -- Just a file path
  if text:match("%.%w+$") then -- Has file extension
    return {
      file = text,
      line = nil,
      col = nil
    }
  end
  
  return nil
end

---Check if a file path exists and is readable
---@param file_path string The file path to check
---@return boolean exists True if file exists and is readable
local function file_exists(file_path)
  local expanded = vim.fn.expand(file_path)
  return vim.fn.filereadable(expanded) == 1
end

---Open a file reference in the editor
---@param ref table Parsed file reference with file, line, col
---@return boolean success True if file was opened successfully
local function open_file_reference(ref)
  local file_path = ref.file
  
  -- Expand the path
  local expanded_path = vim.fn.expand(file_path)
  
  -- Check if file exists
  if not file_exists(expanded_path) then
    -- Try relative to current working directory
    local cwd_path = vim.fn.getcwd() .. "/" .. file_path
    if file_exists(cwd_path) then
      expanded_path = cwd_path
    else
      logger.warn("links", "File not found: " .. file_path)
      vim.notify("File not found: " .. file_path, vim.log.levels.WARN)
      return false
    end
  end
  
  -- Use the openFile tool if available, otherwise fall back to vim commands
  local tools_ok, tools = pcall(require, "claudecode.tools.open_file")
  if tools_ok and tools.handler then
    local params = {
      filePath = expanded_path,
      makeFrontmost = true
    }
    
    if ref.line then
      params.startLine = ref.line
      if ref.col then
        -- For column positioning, we'll select just that position
        params.endLine = ref.line
      end
    end
    
    local success, result = pcall(tools.handler, params)
    if success then
      logger.debug("links", "Opened file via tool: " .. expanded_path)
      return true
    else
      logger.warn("links", "Failed to open file via tool: " .. tostring(result))
    end
  end
  
  -- Fallback to vim commands
  vim.cmd("edit " .. vim.fn.fnameescape(expanded_path))
  
  if ref.line then
    vim.api.nvim_win_set_cursor(0, {ref.line, (ref.col or 1) - 1})
    vim.cmd("normal! zz") -- Center the line in the window
  end
  
  logger.debug("links", "Opened file: " .. expanded_path)
  return true
end

---Open a URL in the default browser
---@param url string The URL to open
---@return boolean success True if URL was opened successfully
local function open_url(url)
  local cmd
  if vim.fn.has("mac") == 1 then
    cmd = "open"
  elseif vim.fn.has("unix") == 1 then
    cmd = "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    cmd = "start"
  else
    logger.warn("links", "Unsupported platform for opening URLs")
    return false
  end
  
  local full_cmd = cmd .. " '" .. url .. "'"
  vim.fn.system(full_cmd)
  logger.debug("links", "Opened URL: " .. url)
  return true
end

---Detect links in a given text
---@param text string The text to analyze
---@return table links Array of detected links with type, text, start_pos, end_pos
function M.detect_links(text)
  local links = {}
  
  if config.enable_file_links then
    -- Detect file paths
    for _, pattern in ipairs(PATTERNS.file_path) do
      local start_pos = 1
      while true do
        local match_start, match_end = text:find(pattern, start_pos)
        if not match_start then break end
        
        local match_text = text:sub(match_start, match_end)
        local ref = parse_file_reference(match_text)
        
        if ref then
          table.insert(links, {
            type = "file",
            text = match_text,
            start_pos = match_start,
            end_pos = match_end,
            ref = ref
          })
        end
        
        start_pos = match_end + 1
      end
    end
  end
  
  if config.enable_url_links then
    -- Detect URLs
    for _, pattern in ipairs(PATTERNS.url) do
      local start_pos = 1
      while true do
        local match_start, match_end = text:find(pattern, start_pos)
        if not match_start then break end
        
        local match_text = text:sub(match_start, match_end)
        table.insert(links, {
          type = "url",
          text = match_text,
          start_pos = match_start,
          end_pos = match_end
        })
        
        start_pos = match_end + 1
      end
    end
  end
  
  return links
end

---Handle clicking on a link
---@param link table The link object to handle
---@return boolean success True if link was handled successfully
function M.handle_link_click(link)
  if link.type == "file" then
    return open_file_reference(link.ref)
  elseif link.type == "url" then
    return open_url(link.text)
  else
    logger.warn("links", "Unknown link type: " .. (link.type or "nil"))
    return false
  end
end

---Get the link under the cursor in the current buffer
---@return table? link The link under cursor, or nil if none found
function M.get_link_under_cursor()
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local col_num = vim.api.nvim_win_get_cursor(0)[2]
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]
  
  if not line then return nil end
  
  local links = M.detect_links(line)
  
  -- Find link that contains the cursor position
  for _, link in ipairs(links) do
    if col_num >= link.start_pos - 1 and col_num < link.end_pos then
      return link
    end
  end
  
  return nil
end

---Set up link highlighting for a buffer
---@param bufnr number The buffer number to set up highlighting for
function M.setup_buffer_highlighting(bufnr)
  if not config.auto_highlight then return end
  
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(bufnr, -1, 0, -1)
  
  -- Get all lines in the buffer
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  
  -- Highlight links in each line
  for line_num, line in ipairs(lines) do
    local links = M.detect_links(line)
    for _, link in ipairs(links) do
      vim.api.nvim_buf_add_highlight(
        bufnr,
        -1, -- use default namespace
        "ClaudeCodeLink",
        line_num - 1, -- 0-based line number
        link.start_pos - 1, -- 0-based column start
        link.end_pos -- 0-based column end
      )
    end
  end
end

---Set up keybindings for link interaction in a buffer
---@param bufnr number The buffer number to set up keybindings for
function M.setup_buffer_keybindings(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  
  -- Set up click keymap
  vim.keymap.set("n", config.click_keymap, function()
    local link = M.get_link_under_cursor()
    if link then
      M.handle_link_click(link)
    else
      -- Fallback to default behavior
      vim.api.nvim_feedkeys(config.click_keymap, "n", false)
    end
  end, {
    buffer = bufnr,
    desc = "Open link under cursor or default action"
  })
  
  -- Set up preview keymap (for file links only)
  vim.keymap.set("n", config.preview_keymap, function()
    local link = M.get_link_under_cursor()
    if link and link.type == "file" then
      -- Open in preview window
      local ref = link.ref
      vim.cmd("pedit " .. vim.fn.fnameescape(ref.file))
      if ref.line then
        vim.cmd("wincmd P") -- Go to preview window
        vim.api.nvim_win_set_cursor(0, {ref.line, (ref.col or 1) - 1})
        vim.cmd("normal! zz")
        vim.cmd("wincmd p") -- Return to original window
      end
    end
  end, {
    buffer = bufnr,
    desc = "Preview file link under cursor"
  })
end

---Set up link detection and handling for a buffer (convenience function)
---@param bufnr number? The buffer number (defaults to current buffer)
function M.setup_buffer(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  M.setup_buffer_highlighting(bufnr)
  M.setup_buffer_keybindings(bufnr)
end

---Enhanced text output that includes clickable links
---@param text string The text to process
---@return string processed_text The text with enhanced link formatting
function M.enhance_output_text(text)
  if not text then return text end
  
  local links = M.detect_links(text)
  if #links == 0 then return text end
  
  -- For now, just return the original text
  -- In the future, we could add special markers or formatting
  return text
end

return M