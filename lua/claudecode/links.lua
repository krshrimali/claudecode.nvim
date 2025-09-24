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
    -- Paths with double slashes: path//subpath/file.ext
    [[%w+[%w%._%-/]*//[%w%._%-/]+%.%w+:?%d*:?%d*]],
    -- Complex paths with multiple segments
    [[%w+[%w%._%-/]+%.%w+:?%d*:?%d*]],
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
  },
  -- Variable/symbol references (when surrounded by context indicators)
  symbol = {
    [[`[%w_][%w%._]*`]], -- `variable_name` or `function_name`
    [['[%w_][%w%._]*']], -- 'variable_name' 
    [["[%w_][%w%._]*"]], -- "variable_name"
    -- More flexible patterns for natural language
    [[`[%w_][%w%._%-]*[%w_]`]], -- `multi-word_variable`
    [['[%w_][%w%._%-]*[%w_]']], -- 'multi-word_variable'
    [["[%w_][%w%._%-]*[%w_]"]], -- "multi-word_variable"
    -- Method calls and object properties
    [[`[%w_]+%.[%w_]+`]], -- `object.method`
    [[`[%w_]+%.[%w_]+%(%)` ]], -- `function.call()`
    -- Common programming patterns
    [[`[%w_]+::[%w_]+`]], -- `namespace::function` (C++)
    [[`[%w_]+%->[%w_]+`]], -- `pointer->member` (C/C++)
  }
}

-- Configuration for link handling
local config = {
  enable_file_links = true,
  enable_url_links = true,
  enable_git_links = true,
  enable_symbol_links = true,
  auto_highlight = true,
  highlight_group = "Underlined",
  click_keymap = "<CR>",
  preview_keymap = "gp",
  symbol_keymap = "gd", -- Go to definition for symbols
}

---Setup the links module with user configuration
---@param user_config table? Optional configuration overrides
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end
  
  -- Create highlight groups if they don't exist
  if config.auto_highlight then
    vim.api.nvim_set_hl(0, "ClaudeCodeLink", {
      fg = "#569cd6", -- Light blue
      underline = true,
      default = true
    })
    vim.api.nvim_set_hl(0, "ClaudeCodeFileLink", {
      fg = "#569cd6", -- Light blue  
      underline = true,
      default = true
    })
    vim.api.nvim_set_hl(0, "ClaudeCodeUrlLink", {
      fg = "#4ec9b0", -- Teal
      underline = true,
      default = true
    })
    vim.api.nvim_set_hl(0, "ClaudeCodeSymbolLink", {
      fg = "#dcdcaa", -- Yellow
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
    -- Try various path resolution strategies
    local candidates = {
      vim.fn.getcwd() .. "/" .. file_path,  -- Relative to CWD
      file_path:gsub("//", "/"),            -- Normalize double slashes
      vim.fn.getcwd() .. "/" .. file_path:gsub("//", "/"), -- CWD + normalized
    }
    
    -- Try to find the file by searching in common directories
    local workspace_root = vim.fn.getcwd()
    if file_path:match("^%w+//") then
      -- For patterns like "desco_llm//doclab/ui/semantic_search/service.py"
      local parts = vim.split(file_path, "//", {plain = true})
      if #parts >= 2 then
        -- Try workspace_root/parts[2]
        table.insert(candidates, workspace_root .. "/" .. parts[2])
        -- Try just parts[2] (relative)
        table.insert(candidates, parts[2])
      end
    end
    
    expanded_path = nil
    for _, candidate in ipairs(candidates) do
      if file_exists(candidate) then
        expanded_path = candidate
        break
      end
    end
    
    if not expanded_path then
      logger.warn("links", "File not found: " .. file_path)
      logger.debug("links", "Tried candidates: " .. vim.inspect(candidates))
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

---Handle symbol/variable reference by searching for definition
---@param symbol_name string The symbol name to search for
---@return boolean success True if symbol was found/handled
local function handle_symbol_reference(symbol_name)
  -- Remove surrounding quotes/backticks
  symbol_name = symbol_name:gsub("^[`'\"]", ""):gsub("[`'\"]$", "")
  
  logger.debug("links", "Searching for symbol: " .. symbol_name)
  
  -- Try LSP go-to-definition first if available
  if vim.lsp.buf.definition then
    -- Search for the symbol in the current buffer first
    local current_buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(current_buf, 0, -1, false)
    
    for line_num, line in ipairs(lines) do
      -- Look for symbol definitions (function, variable declarations, etc.)
      local patterns = {
        "def%s+" .. symbol_name .. "%s*%(", -- Python function
        "function%s+" .. symbol_name .. "%s*%(", -- JavaScript/Lua function
        "class%s+" .. symbol_name .. "%s*[%({]", -- Class definition
        symbol_name .. "%s*=%s*", -- Variable assignment
        "let%s+" .. symbol_name .. "%s*=", -- Let assignment
        "const%s+" .. symbol_name .. "%s*=", -- Const assignment
        "var%s+" .. symbol_name .. "%s*=", -- Var assignment
      }
      
      for _, pattern in ipairs(patterns) do
        if line:match(pattern) then
          -- Found a potential definition, jump to it
          vim.api.nvim_win_set_cursor(0, {line_num, 0})
          vim.cmd("normal! zz") -- Center the line
          vim.notify("Found definition of: " .. symbol_name, vim.log.levels.INFO)
          return true
        end
      end
    end
    
    -- If not found in current buffer, try LSP workspace symbol search
    if vim.lsp.buf.workspace_symbol then
      vim.lsp.buf.workspace_symbol(symbol_name)
      return true
    end
  end
  
  -- Fallback: use vim's built-in search
  local search_pattern = "\\<" .. symbol_name .. "\\>"
  vim.fn.search(search_pattern)
  vim.notify("Searched for symbol: " .. symbol_name, vim.log.levels.INFO)
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
  
  if config.enable_symbol_links then
    -- Detect symbols/variables
    for _, pattern in ipairs(PATTERNS.symbol) do
      local start_pos = 1
      while true do
        local match_start, match_end = text:find(pattern, start_pos)
        if not match_start then break end
        
        local match_text = text:sub(match_start, match_end)
        table.insert(links, {
          type = "symbol",
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
  elseif link.type == "symbol" then
    return handle_symbol_reference(link.text)
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
  
  -- Set up symbol navigation keymap (alternative to Enter for symbols)
  vim.keymap.set("n", config.symbol_keymap, function()
    local link = M.get_link_under_cursor()
    if link and link.type == "symbol" then
      M.handle_link_click(link)
    else
      -- Fallback to LSP go-to-definition if available
      if vim.lsp.buf.definition then
        vim.lsp.buf.definition()
      else
        vim.notify("No symbol under cursor or LSP not available", vim.log.levels.WARN)
      end
    end
  end, {
    buffer = bufnr,
    desc = "Go to definition of symbol under cursor"
  })
  
  -- Set up preview keymap (for file links only)
  vim.keymap.set("n", config.preview_keymap, function()
    local link = M.get_link_under_cursor()
    if link and link.type == "file" then
      -- Open in preview window
      local ref = link.ref
      local expanded_path = vim.fn.expand(ref.file)
      
      -- Check if file exists before trying to preview
      if not file_exists(expanded_path) then
        -- Try relative to current working directory
        local cwd_path = vim.fn.getcwd() .. "/" .. ref.file
        if file_exists(cwd_path) then
          expanded_path = cwd_path
        else
          vim.notify("File not found for preview: " .. ref.file, vim.log.levels.WARN)
          return
        end
      end
      
      vim.cmd("pedit " .. vim.fn.fnameescape(expanded_path))
      if ref.line then
        vim.cmd("wincmd P") -- Go to preview window
        -- Safely set cursor position with bounds checking
        local line_count = vim.api.nvim_buf_line_count(0)
        local safe_line = math.min(ref.line, line_count)
        local safe_col = math.max(0, (ref.col or 1) - 1)
        
        pcall(vim.api.nvim_win_set_cursor, 0, {safe_line, safe_col})
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