--- Tool implementation for setting context about clickable references.

local schema = {
  description = "Set context for generating clickable references in responses",
  inputSchema = {
    type = "object",
    properties = {
      enable_hints = {
        type = "boolean",
        description = "Whether to enable clickable reference formatting hints",
        default = true,
      },
    },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the setClickableContext tool invocation.
---Provides context about how to format references for clickability.
---@param params table The input parameters for the tool
---@return table MCP-compliant response with context information
local function handler(params)
  local enable_hints = params.enable_hints ~= false -- default true
  
  local context_info = {}
  
  if enable_hints then
    table.insert(context_info, "📋 CLICKABLE REFERENCE FORMATTING GUIDE")
    table.insert(context_info, "")
    table.insert(context_info, "To make your responses more interactive in Neovim, please format references as follows:")
    table.insert(context_info, "")
    table.insert(context_info, "🔗 FILE REFERENCES:")
    table.insert(context_info, "• Use full paths: `/path/to/file.py:42:15`")
    table.insert(context_info, "• Include line numbers when relevant: `config.lua:56`")
    table.insert(context_info, "• Support complex paths: `project//subdir/service.py`")
    table.insert(context_info, "")
    table.insert(context_info, "🔤 VARIABLE/FUNCTION REFERENCES:")
    table.insert(context_info, "• Wrap in backticks: `variable_name`, `function_name`")
    table.insert(context_info, "• Use quotes for emphasis: 'config_setting', \"method_call\"")
    table.insert(context_info, "• Examples:")
    table.insert(context_info, "  - \"The `handle_request` function processes incoming data\"")
    table.insert(context_info, "  - \"Check the 'debug_mode' variable in your config\"")
    table.insert(context_info, "  - \"The `M.setup` method initializes the module\"")
    table.insert(context_info, "")
    table.insert(context_info, "🌐 URL REFERENCES:")
    table.insert(context_info, "• Use full URLs: `https://example.com/docs`")
    table.insert(context_info, "• File URLs: `file:///path/to/local/file`")
    table.insert(context_info, "")
    table.insert(context_info, "🔍 ERROR/DIAGNOSTIC REFERENCES:")
    table.insert(context_info, "• Format as: `[ERROR] file.py:42:15 - description`")
    table.insert(context_info, "• Include severity: `[WARNING] main.lua:100 - unused variable`")
    table.insert(context_info, "")
    table.insert(context_info, "💡 BENEFITS:")
    table.insert(context_info, "• Users can press <Enter> on any reference to navigate")
    table.insert(context_info, "• File references open in editor with line positioning")
    table.insert(context_info, "• Variable references search for definitions")
    table.insert(context_info, "• URLs open in browser")
    table.insert(context_info, "")
    table.insert(context_info, "This context is now active. Please format your references accordingly!")
  else
    table.insert(context_info, "Clickable reference formatting hints disabled.")
  end
  
  local output_text = table.concat(context_info, "\n")
  
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
  name = "setClickableContext",
  schema = schema,
  handler = handler,
}