--- Module for enabling clickable links in Claude Code terminal output
--- @module 'claudecode.terminal_links'

local M = {}

local logger = require("claudecode.logger")
local links = require("claudecode.links")

-- Configuration
local config = {
  enabled = true,
  auto_setup_terminal = true,
  highlight_links = true,
  update_interval = 500, -- ms
}

-- State tracking
local setup_buffers = {}
local update_timers = {}

---Setup the terminal links module
---@param user_config table? Optional configuration overrides
function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", config, user_config)
  end
  
  -- Initialize the links module
  links.setup({
    enable_file_links = true,
    enable_url_links = true,
    auto_highlight = config.highlight_links,
    click_keymap = "<CR>",
    preview_keymap = "gp",
  })
  
  if config.auto_setup_terminal then
    M.setup_terminal_autocmds()
  end
end

---Set up autocommands to detect and enhance terminal buffers
function M.setup_terminal_autocmds()
  local group = vim.api.nvim_create_augroup("ClaudeCodeTerminalLinks", { clear = true })
  
  -- Set up links when terminal buffer is created or entered
  vim.api.nvim_create_autocmd({"TermOpen", "BufEnter"}, {
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
      
      if buftype == "terminal" then
        -- Check if this might be a Claude Code terminal
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname:match("claude") or M.is_claude_terminal(bufnr) then
          M.setup_terminal_buffer(bufnr)
        end
      end
    end,
    desc = "Setup links for Claude Code terminal buffers"
  })
  
  -- Clean up when buffer is deleted
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      M.cleanup_buffer(bufnr)
    end,
    desc = "Cleanup terminal links on buffer delete"
  })
end

---Check if a buffer is likely a Claude Code terminal
---@param bufnr number The buffer number to check
---@return boolean is_claude_terminal True if this appears to be a Claude Code terminal
function M.is_claude_terminal(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  
  if buftype ~= "terminal" then
    return false
  end
  
  -- Check if buffer name contains claude-related terms
  if bufname:lower():match("claude") then
    return true
  end
  
  -- Check if this is managed by the terminal module
  local terminal_module_ok, terminal_module = pcall(require, "claudecode.terminal")
  if terminal_module_ok then
    local active_bufnr = terminal_module.get_active_terminal_bufnr()
    if active_bufnr == bufnr then
      return true
    end
  end
  
  return false
end

---Set up link detection and handling for a terminal buffer
---@param bufnr number The terminal buffer number
function M.setup_terminal_buffer(bufnr)
  if not config.enabled then return end
  
  if setup_buffers[bufnr] then
    return -- Already set up
  end
  
  logger.debug("terminal_links", "Setting up links for terminal buffer: " .. bufnr)
  
  -- Set up keybindings for link interaction
  links.setup_buffer_keybindings(bufnr)
  
  -- Mark as set up
  setup_buffers[bufnr] = true
  
  -- Start periodic highlighting updates
  M.start_highlighting_updates(bufnr)
  
  -- Auto-set clickable context if enabled
  if config.auto_set_context then
    M.auto_set_clickable_context(bufnr)
  end
  
  -- Set up buffer-local autocommands for text changes
  local group = vim.api.nvim_create_augroup("ClaudeCodeTerminalLinks_" .. bufnr, { clear = true })
  
  vim.api.nvim_create_autocmd({"TextChanged", "TextChangedI"}, {
    group = group,
    buffer = bufnr,
    callback = function()
      -- Debounce highlighting updates
      M.schedule_highlighting_update(bufnr)
    end,
    desc = "Update link highlighting on text change"
  })
end

---Start periodic highlighting updates for a terminal buffer
---@param bufnr number The buffer number
function M.start_highlighting_updates(bufnr)
  if not config.highlight_links then return end
  
  -- Stop existing timer if any
  if update_timers[bufnr] then
    update_timers[bufnr]:stop()
    update_timers[bufnr]:close()
  end
  
  -- Create new timer for periodic updates
  local timer = vim.loop.new_timer()
  update_timers[bufnr] = timer
  
  timer:start(config.update_interval, config.update_interval, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.update_buffer_highlighting(bufnr)
    else
      -- Buffer no longer valid, clean up
      M.cleanup_buffer(bufnr)
    end
  end))
end

---Schedule a highlighting update for a buffer (debounced)
---@param bufnr number The buffer number
function M.schedule_highlighting_update(bufnr)
  if not config.highlight_links then return end
  
  -- Simple debouncing: delay the update
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      M.update_buffer_highlighting(bufnr)
    end
  end, 100) -- 100ms delay
end

---Update link highlighting for a buffer
---@param bufnr number The buffer number
function M.update_buffer_highlighting(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  
  -- Only highlight visible portion to avoid performance issues
  local windows = vim.fn.win_findbuf(bufnr)
  if #windows == 0 then
    return -- Buffer not visible
  end
  
  local winid = windows[1]
  local win_info = vim.fn.getwininfo(winid)[1]
  if not win_info then return end
  
  local start_line = math.max(0, win_info.topline - 10) -- Add some buffer
  local end_line = math.min(vim.api.nvim_buf_line_count(bufnr), win_info.botline + 10)
  
  -- Clear existing highlights in the visible range
  vim.api.nvim_buf_clear_namespace(bufnr, -1, start_line, end_line)
  
  -- Get lines in the visible range
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, end_line, false)
  
  -- Highlight links in each line
  for i, line in ipairs(lines) do
    local line_num = start_line + i - 1
    local detected_links = links.detect_links(line)
    
    for _, link in ipairs(detected_links) do
      -- Choose highlight group based on link type
      local hl_group = "ClaudeCodeLink" -- default
      if link.type == "file" then
        hl_group = "ClaudeCodeFileLink"
      elseif link.type == "url" then
        hl_group = "ClaudeCodeUrlLink"
      elseif link.type == "symbol" then
        hl_group = "ClaudeCodeSymbolLink"
      end
      
      vim.api.nvim_buf_add_highlight(
        bufnr,
        -1, -- use default namespace
        hl_group,
        line_num,
        link.start_pos - 1, -- 0-based column start
        link.end_pos -- 0-based column end
      )
    end
  end
end

---Clean up resources for a buffer
---@param bufnr number The buffer number
function M.cleanup_buffer(bufnr)
  setup_buffers[bufnr] = nil
  
  if update_timers[bufnr] then
    update_timers[bufnr]:stop()
    update_timers[bufnr]:close()
    update_timers[bufnr] = nil
  end
  
  -- Clear autocommand group
  pcall(vim.api.nvim_del_augroup_by_name, "ClaudeCodeTerminalLinks_" .. bufnr)
  
  logger.debug("terminal_links", "Cleaned up terminal buffer: " .. bufnr)
end

---Manually set up links for the current buffer (if it's a terminal)
function M.setup_current_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local buftype = vim.api.nvim_buf_get_option(bufnr, "buftype")
  
  if buftype == "terminal" then
    M.setup_terminal_buffer(bufnr)
    vim.notify("Enabled clickable links for this terminal", vim.log.levels.INFO)
  else
    vim.notify("Current buffer is not a terminal", vim.log.levels.WARN)
  end
end

---Enable terminal links globally
function M.enable()
  config.enabled = true
  logger.info("terminal_links", "Terminal links enabled")
end

---Disable terminal links globally
function M.disable()
  config.enabled = false
  
  -- Clean up all existing setups
  for bufnr in pairs(setup_buffers) do
    M.cleanup_buffer(bufnr)
  end
  
  logger.info("terminal_links", "Terminal links disabled")
end

---Automatically set clickable context for Claude
---@param bufnr number The terminal buffer number
function M.auto_set_clickable_context(bufnr)
  -- Delay the context setting to allow terminal to fully initialize
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    
    logger.debug("terminal_links", "Auto-setting clickable context for buffer: " .. bufnr)
    
    -- Send an actual message to Claude about clickable formatting
    local context_message = [[Please format all variable and function references with their full file paths for maximum clickability in Neovim. 

CRITICAL FORMATTING RULES:
• Instead of just `variable_name`, use `file.py:line` (clickable!)
• Instead of just `function_name`, use `utils.py:150` (clickable!)
• Always include file paths and line numbers when referencing code
• Format: `filename.ext:line_number` or `path/to/file.py:line:col`

Examples:
- "The `config` variable in `settings.py:25` controls..."
- "Check the `handle_request` function at `server.py:45`"
- "Error in `utils.py:150` - the validation logic needs updating"

This makes everything clickable for instant navigation! Please use this format in all your responses.]]

    -- Try to send this as an actual message to Claude via the @ mention system
    local claudecode_main_ok, claudecode_main = pcall(require, "claudecode")
    if claudecode_main_ok and claudecode_main.send_at_mention then
      -- Create a temporary file with the context message
      local temp_file = vim.fn.tempname() .. ".md"
      local file = io.open(temp_file, "w")
      if file then
        file:write("# Clickable Links Context\n\n")
        file:write(context_message)
        file:close()
        
        -- Send the context file as an @ mention
        local success, error_msg = claudecode_main.send_at_mention(temp_file, nil, nil, "auto_context")
        if success then
          logger.info("terminal_links", "Sent clickable context to Claude via @ mention")
          
          -- Clean up temp file after a delay
          vim.defer_fn(function()
            pcall(os.remove, temp_file)
          end, 5000)
        else
          logger.warn("terminal_links", "Failed to send context via @ mention: " .. (error_msg or "unknown"))
          -- Fall back to just showing in terminal
          M.show_context_in_terminal(bufnr)
        end
      else
        logger.warn("terminal_links", "Failed to create temp context file")
        M.show_context_in_terminal(bufnr)
      end
    else
      logger.warn("terminal_links", "claudecode main module not available for @ mention")
      M.show_context_in_terminal(bufnr)
    end
  end, 5000) -- Wait 5 seconds for terminal and server to be ready
end

---Show context visually in terminal (fallback method)
---@param bufnr number The terminal buffer number
function M.show_context_in_terminal(bufnr)
  local indicator_lines = {
    "",
    "# 🔗 CLICKABLE LINKS CONTEXT ACTIVATED",
    "# Claude should provide FULL FILE PATHS for maximum clickability:",
    "# ✅ Ask: 'Show me the config variable with its file path like `config.py:25`'",
    "# ✅ Request: 'Include full paths for all variables and functions'",
    "# ✅ Everything should be clickable with file paths!",
    ""
  }
  
  local current_lines = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, current_lines, current_lines, false, indicator_lines)
  
  logger.info("terminal_links", "Added clickable context visual indicator to terminal buffer: " .. bufnr)
end

---Get status information
---@return table status Status information about terminal links
function M.get_status()
  local active_buffers = {}
  for bufnr in pairs(setup_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      table.insert(active_buffers, bufnr)
    end
  end
  
  return {
    enabled = config.enabled,
    active_buffers = active_buffers,
    buffer_count = #active_buffers,
    auto_set_context = config.auto_set_context,
  }
end

return M