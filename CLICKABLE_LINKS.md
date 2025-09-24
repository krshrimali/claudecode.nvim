# Clickable Links in Claude Code

This document describes the clickable links feature that makes file references, URLs, and other references in Claude Code output interactive within Neovim.

## Overview

The clickable links feature automatically detects and highlights various types of references in Claude Code terminal output, making them interactive. You can click or press keys to open files, navigate to specific lines, or open URLs.

## Supported Link Types

### File References
- **Absolute paths**: `/path/to/file.ext`
- **Relative paths**: `./path/file.ext`, `../path/file.ext`, `path/file.ext`
- **Complex paths**: `project//subdir/file.ext` (handles double slashes)
- **With line numbers**: `file.ext:42` or `file.ext:42:15`
- **Diagnostic format**: `[ERROR] file.ext:42:15 - message`

### URLs
- **HTTP/HTTPS**: `https://example.com`
- **File URLs**: `file:///path/to/file`

### Symbols/Variables
- **Backtick format**: `function_name`, `variable_name`
- **Quote format**: 'variable_name', "function_name"
- **In context**: "The `handle_click` function processes events"

### Examples of Clickable References
```
/workspace/lua/claudecode/init.lua:42:15
./src/main.lua:123
project//subdir/service.py:100
config.lua:56
README.md
https://github.com/neovim/neovim
[ERROR] /workspace/lua/claudecode/init.lua:42:15 - undefined variable 'foo'
The function `handle_link_click` processes user interactions
Check the 'config' variable for settings
```

## Usage

### Automatic Setup
The clickable links feature is automatically enabled for Claude Code terminal buffers when you have the plugin configured.

### Manual Interaction
1. **Position cursor** on any highlighted link
2. **Press `<Enter>`** to open/navigate to the reference
3. **Press `gp`** to preview file references (opens in preview window)
4. **Press `gd`** to go to symbol definition (for symbol references)

### File References
- Opens the file in the main editor window
- If line number is specified, jumps to that line
- If column is specified, positions cursor at that column
- Centers the target line in the window for better visibility

### URL References
- Opens URLs in your default system browser
- Supports `http://`, `https://`, and `file://` protocols

### Symbol References
- Searches for symbol definitions in the current buffer first
- Falls back to LSP workspace symbol search if available
- Uses vim's built-in search as final fallback
- Supports function definitions, variable assignments, class definitions

## Configuration

The clickable links feature can be configured in your Claude Code setup:

```lua
require("claudecode").setup({
  terminal_links = {
    enabled = true,              -- Enable/disable the feature
    auto_setup_terminal = true,  -- Automatically setup for terminal buffers
    highlight_links = true,      -- Highlight detected links
    update_interval = 500,       -- Update highlighting every 500ms
    click_keymap = "<CR>",       -- Key to activate links
    preview_keymap = "gp",       -- Key to preview file links
    enable_symbol_links = true,  -- Enable symbol/variable link detection
    symbol_keymap = "gd",        -- Key for symbol go-to-definition
  }
})
```

## Commands

### `:ClaudeCodeLinksEnable`
Enable clickable links globally.

### `:ClaudeCodeLinksDisable`
Disable clickable links globally and clean up existing setups.

### `:ClaudeCodeLinksSetup`
Manually setup clickable links for the current terminal buffer.

### `:ClaudeCodeLinksStatus`
Show status information about active link setups.

### `:ClaudeCodeSetClickableContext`
Manually set context for Claude to generate clickable references.

### `:testLinks`
Generate test output with various clickable reference types (available as Claude tool).

### `:setClickableContext`
Tool that provides Claude with formatting guidance for clickable references.

## Technical Details

### Link Detection
The system uses pattern matching to identify potential links in text:
- File paths are validated for existence when possible
- Line and column numbers are parsed and converted appropriately
- URLs are detected by protocol prefix

### Highlighting
- Links are highlighted using the `ClaudeCodeLink` highlight group
- Updates occur periodically and on text changes
- Only visible portions of terminal buffers are processed for performance

### Integration
- Works with the existing `openFile` tool for consistent file opening
- Enhanced diagnostic output includes clickable references
- Tool responses are enhanced with clickable file references where appropriate

## Getting Variable References to Work

### The Problem
Claude doesn't automatically format variable references in a clickable way. You need to guide it.

### The Solution
1. **Auto-Context (Recommended)**: Set `auto_set_context = true` in config (default)
2. **Manual Context**: Run `:ClaudeCodeSetClickableContext` command
3. **Ask Claude**: Request "Use the setClickableContext tool to enable clickable references"

### Example Requests
Instead of asking:
> "What does the config variable do?"

Ask:
> "Please use backticks around variable names. What does the `config` variable do?"

Or:
> "Explain the `handle_request` function and how it uses the `settings` object."

## Troubleshooting

### Variable References Not Clickable
1. Run `:ClaudeCodeSetClickableContext` to set formatting context
2. Ask Claude to "use backticks around variable names like `variable_name`"
3. Use the `setClickableContext` tool in your requests

### Links Not Highlighting
1. Check if feature is enabled: `:ClaudeCodeLinksStatus`
2. Manually setup current buffer: `:ClaudeCodeLinksSetup`
3. Verify terminal buffer is detected as Claude Code terminal

### Links Not Opening
1. Ensure files exist and are readable
2. Check file paths are correct (relative to current working directory)
3. For URLs, verify system browser configuration

### Performance Issues
- Reduce `update_interval` in configuration
- Disable `highlight_links` if not needed
- Large terminal buffers may impact performance

## Examples

### Testing the Feature
Use the `testLinks` tool to generate test output:
```
Ask Claude: "Use the testLinks tool to show me clickable references"
```

This will generate various types of clickable references you can test with.

### Typical Workflow
1. Ask Claude to analyze files or show diagnostics
2. Claude's response includes clickable file references
3. Click on references to navigate directly to the relevant code
4. Use preview mode (`gp`) to quickly inspect files without losing context

## Integration with Other Tools

The clickable links feature enhances several existing tools:
- **getDiagnostics**: Shows clickable error/warning locations
- **openFile**: Provides clickable confirmation messages
- **testLinks**: Generates test cases for the feature

This makes the Claude Code experience more interactive and efficient for navigating codebases and following references.