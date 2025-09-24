--- Tool implementation for testing clickable links functionality.

local schema = {
  description = "Test clickable links by generating various types of references",
  inputSchema = {
    type = "object",
    properties = {
      include_files = {
        type = "boolean",
        description = "Include file path references in the test output",
        default = true,
      },
      include_urls = {
        type = "boolean", 
        description = "Include URL references in the test output",
        default = true,
      },
      include_diagnostics = {
        type = "boolean",
        description = "Include diagnostic-style references in the test output", 
        default = true,
      },
    },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the testLinks tool invocation.
---Generates test output with various clickable reference types.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with test links
local function handler(params)
  local include_files = params.include_files ~= false -- default true
  local include_urls = params.include_urls ~= false -- default true  
  local include_diagnostics = params.include_diagnostics ~= false -- default true
  
  local test_output = {}
  
  table.insert(test_output, "=== Clickable Links Test Output ===\n")
  
  if include_files then
    table.insert(test_output, "📁 FILE REFERENCES:")
    table.insert(test_output, "• /workspace/lua/claudecode/init.lua")
    table.insert(test_output, "• /workspace/lua/claudecode/init.lua:42")
    table.insert(test_output, "• /workspace/lua/claudecode/init.lua:42:15")
    table.insert(test_output, "• ./lua/claudecode/links.lua")
    table.insert(test_output, "• ./lua/claudecode/links.lua:123")
    table.insert(test_output, "• config.lua:56:8")
    table.insert(test_output, "• README.md")
    table.insert(test_output, "")
  end
  
  if include_urls then
    table.insert(test_output, "🌐 URL REFERENCES:")
    table.insert(test_output, "• https://github.com/neovim/neovim")
    table.insert(test_output, "• https://claude.ai/chat")
    table.insert(test_output, "• file:///workspace/lua/claudecode/init.lua")
    table.insert(test_output, "")
  end
  
  if include_diagnostics then
    table.insert(test_output, "🔍 DIAGNOSTIC-STYLE REFERENCES:")
    table.insert(test_output, "[ERROR] /workspace/lua/claudecode/init.lua:42:15 - undefined variable 'foo'")
    table.insert(test_output, "[WARNING] ./src/main.lua:123:8 - unused variable 'bar'")
    table.insert(test_output, "[INFO] config.lua:56 - missing documentation")
    table.insert(test_output, "")
    
    table.insert(test_output, "🔤 SYMBOL/VARIABLE REFERENCES:")
    table.insert(test_output, "• The function `handle_link_click` is defined in the links module")
    table.insert(test_output, "• Variable `config` contains the configuration settings")
    table.insert(test_output, "• Check the `parse_file_reference` function implementation")
    table.insert(test_output, "• The `M.setup` method initializes the module")
    table.insert(test_output, "• Method call `vim.api.nvim_buf_get_lines` reads buffer content")
    table.insert(test_output, "• Object property `terminal.state.active` tracks status")
    table.insert(test_output, "• Class method `Logger.debug` outputs debug messages")
    table.insert(test_output, "")
  end
  
  table.insert(test_output, "💡 INSTRUCTIONS:")
  table.insert(test_output, "• Position cursor on any reference above")
  table.insert(test_output, "• Press <Enter> to open/navigate to the reference")
  table.insert(test_output, "• Press 'gp' to preview file references")
  table.insert(test_output, "• Press 'gd' to go to symbol definition")
  table.insert(test_output, "• File references should be clickable and highlighted")
  table.insert(test_output, "• URLs should open in your default browser")
  table.insert(test_output, "• Symbol references (in `backticks` or 'quotes') are searchable")
  table.insert(test_output, "")
  table.insert(test_output, "🎯 Try these commands:")
  table.insert(test_output, "• :ClaudeCodeLinksStatus - Check link status")
  table.insert(test_output, "• :ClaudeCodeLinksSetup - Setup links for current buffer")
  
  local output_text = table.concat(test_output, "\n")
  
  return {
    content = {
      {
        type = "text",
        text = output_text,
      },
    },
  }
end

return {
  name = "testLinks",
  schema = schema,
  handler = handler,
}