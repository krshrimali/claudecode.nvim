--- Tool implementation for getting diagnostics.

-- NOTE: Its important we don't tip off Claude that we're dealing with Neovim LSP diagnostics because it may adjust
-- line and col numbers by 1 on its own (since it knows nvim LSP diagnostics are 0-indexed). By calling these
-- "editor diagnostics" and converting to 1-indexed ourselves we (hopefully) avoid incorrect line and column numbers
-- in Claude's responses.
local schema = {
  description = "Get language diagnostics (errors, warnings) from the editor",
  inputSchema = {
    type = "object",
    properties = {
      uri = {
        type = "string",
        description = "Optional file URI to get diagnostics for. If not provided, gets diagnostics for all open files.",
      },
    },
    additionalProperties = false,
    ["$schema"] = "http://json-schema.org/draft-07/schema#",
  },
}

---Handles the getDiagnostics tool invocation.
---Retrieves diagnostics from Neovim's diagnostic system.
---@param params table The input parameters for the tool
---@return table diagnostics MCP-compliant response with diagnostics data
local function handler(params)
  if not vim.lsp or not vim.diagnostic or not vim.diagnostic.get then
    -- Returning an empty list or a specific status could be an alternative.
    -- For now, let's align with the error pattern for consistency if the feature is unavailable.
    error({
      code = -32000,
      message = "Feature unavailable",
      data = "Diagnostics not available in this editor version/configuration.",
    })
  end

  local logger = require("claudecode.logger")

  logger.debug("getDiagnostics handler called with params: " .. vim.inspect(params))

  -- Extract the uri parameter
  local diagnostics

  if not params.uri then
    -- Get diagnostics for all buffers
    logger.debug("Getting diagnostics for all open buffers")
    diagnostics = vim.diagnostic.get(nil)
  else
    local uri = params.uri
    -- Strips the file:// scheme
    local filepath = vim.uri_to_fname(uri)

    -- Get buffer number for the specific file
    local bufnr = vim.fn.bufnr(filepath)
    if bufnr == -1 then
      -- File is not open in any buffer, throw an error
      logger.debug("File buffer must be open to get diagnostics: " .. filepath)
      error({
        code = -32001,
        message = "File not open",
        data = "File must be open to retrieve diagnostics: " .. filepath,
      })
    else
      -- Get diagnostics for the specific buffer
      logger.debug("Getting diagnostics for bufnr: " .. bufnr)
      diagnostics = vim.diagnostic.get(bufnr)
    end
  end

  local formatted_diagnostics = {}
  for _, diagnostic in ipairs(diagnostics) do
    local file_path = vim.api.nvim_buf_get_name(diagnostic.bufnr)
    -- Ensure we only include diagnostics with valid file paths
    if file_path and file_path ~= "" then
      local line_num = diagnostic.lnum + 1 -- Convert to 1-indexed
      local char_num = diagnostic.col + 1 -- Convert to 1-indexed
      
      -- Create a clickable file reference
      local clickable_ref = file_path .. ":" .. line_num .. ":" .. char_num
      
      -- Create severity string for better display
      local severity_names = {
        [vim.diagnostic.severity.ERROR] = "ERROR",
        [vim.diagnostic.severity.WARN] = "WARNING", 
        [vim.diagnostic.severity.INFO] = "INFO",
        [vim.diagnostic.severity.HINT] = "HINT"
      }
      local severity_name = severity_names[diagnostic.severity] or "UNKNOWN"
      
      -- Format as both structured JSON and human-readable text
      local diagnostic_json = vim.json.encode({
        filePath = file_path,
        line = line_num,
        character = char_num,
        severity = diagnostic.severity,
        message = diagnostic.message,
        source = diagnostic.source,
      })
      
      local human_readable = string.format(
        "[%s] %s:%d:%d - %s%s",
        severity_name,
        clickable_ref,
        line_num,
        char_num,
        diagnostic.message,
        diagnostic.source and (" (" .. diagnostic.source .. ")") or ""
      )
      
      table.insert(formatted_diagnostics, {
        type = "text",
        text = human_readable .. "\n" .. diagnostic_json,
      })
    end
  end

  return {
    content = formatted_diagnostics,
  }
end

return {
  name = "getDiagnostics",
  schema = schema,
  handler = handler,
}
