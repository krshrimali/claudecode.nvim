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
    table.insert(context_info, "🔗 FILE REFERENCES (ALWAYS CLICKABLE):")
    table.insert(context_info, "• Use full paths: `/path/to/file.py:42:15`")
    table.insert(context_info, "• Include line numbers when relevant: `config.lua:56`")
    table.insert(context_info, "• Support complex paths: `project//subdir/service.py`")
    table.insert(context_info, "")
    table.insert(context_info, "🔤 VARIABLE/FUNCTION REFERENCES (MAKE CLICKABLE WITH FULL PATHS):")
    table.insert(context_info, "⭐ CRITICAL: Always provide the FULL FILE PATH and LINE NUMBER for variables/functions!")
    table.insert(context_info, "• Instead of just `variable_name`, use `config.py:25` (clickable file location)")
    table.insert(context_info, "• Instead of just `function_name`, use `utils.py:150` (clickable file location)")
    table.insert(context_info, "• Format: `filename.ext:line_number` or `path/to/file.py:line:col`")
    table.insert(context_info, "")
    table.insert(context_info, "📍 ENHANCED EXAMPLES (EVERYTHING CLICKABLE):")
    table.insert(context_info, "  - \"The `handle_request` function is defined in `server.py:45`\"")
    table.insert(context_info, "  - \"Check the `debug_mode` variable in `config.py:12`\"")
    table.insert(context_info, "  - \"The `M.setup` method is in `init.lua:320`\"")
    table.insert(context_info, "  - \"Variable `user_data` is initialized in `models/user.py:28`\"")
    table.insert(context_info, "  - \"Function `parse_request` at `utils/parser.py:67` handles parsing\"")
    table.insert(context_info, "")
    table.insert(context_info, "🌐 URL REFERENCES:")
    table.insert(context_info, "• Use full URLs: `https://example.com/docs`")
    table.insert(context_info, "• File URLs: `file:///path/to/local/file`")
    table.insert(context_info, "")
    table.insert(context_info, "🔍 ERROR/DIAGNOSTIC REFERENCES:")
    table.insert(context_info, "• Format as: `[ERROR] file.py:42:15 - description`")
    table.insert(context_info, "• Include severity: `[WARNING] main.lua:100 - unused variable`")
    table.insert(context_info, "")
    table.insert(context_info, "💡 CLICKABILITY BENEFITS:")
    table.insert(context_info, "• Users can press <Enter> on ANY reference to navigate directly")
    table.insert(context_info, "• File references (like `config.py:25`) open in editor at exact line")
    table.insert(context_info, "• Variable/function locations become instantly navigable")
    table.insert(context_info, "• URLs open in browser")
    table.insert(context_info, "• Everything becomes interactive - maximize clickability!")
    table.insert(context_info, "")
    table.insert(context_info, "🎯 REMEMBER: ALWAYS include file paths and line numbers!")
    table.insert(context_info, "🎯 MAKE EVERYTHING CLICKABLE wherever possible!")
    table.insert(context_info, "")
    table.insert(context_info, "This context is now active. Please format ALL references with full paths for maximum clickability!")
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