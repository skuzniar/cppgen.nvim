cppgen.nvim is a Neovim plugin that provides context-sensitive C++ code generation through the completion engine. Here's how it works:

## Architecture Overview

The plugin acts as a completion source for nvim-cmp, generating C++ code snippets based on the current cursor context and AST (Abstract Syntax Tree) information from
LSP servers.

## Core Components

1. AST Processing (ast.lua): Handles parsing and traversing the AST provided by LSP servers to identify relevant code constructs like classes, enums, and functions.
2. Code Generators (generators/): Specialized modules that generate specific types of C++ code:
 • class.lua: Output stream operators, JSON serialization, cereal serialization
 • enum.lua: To-string functions, cast functions, switch statements
 • cereal.lua: Cereal library serialization functions
 • json.lua: JSON serialization functions
 • switch.lua: Switch statement generation
3. Completion Source (cmpsource.lua): The main completion engine that:
 • Registers with nvim-cmp
 • Requests AST data when entering insert mode
 • Analyzes cursor context to find relevant nodes
 • Generates completion items from code snippets
4. Generator Coordinator (generator.lua): Manages multiple generators and determines which ones are relevant for a given AST node.

## Workflow

1. Setup: Plugin initializes with user configuration and registers with nvim-cmp
2. LSP Attachment: When an LSP client attaches to a C++ buffer, the plugin sets up event handlers
3. Insert Mode Entry: When entering insert mode, the plugin:
 • Captures current cursor position
 • Requests AST data from the LSP server
4. AST Analysis: Upon receiving AST data, the plugin:
 • Finds "proximity nodes" (immediately preceding and smallest enclosing relevant nodes)
 • Optionally finds all preceding nodes for batch mode
 • Determines the scope (inside class vs. outside)
5. Code Generation: For each relevant node, specialized generators create code snippets
6. Completion Items: Generated snippets become completion items in nvim-cmp
7. User Selection: When user selects a completion, the generated code is inserted

## Key Features

• Context-Sensitive: Generates code based on cursor position and surrounding code structure
• Multiple Generators: Supports various C++ patterns (operators, serialization, casts, etc.)
• Batch Mode: Can generate code for all relevant constructs in a file
• LSP Integration: Uses clangd or other LSP servers for accurate AST information
• Customizable: Extensive configuration options for code style and behavior

## Example Usage

When editing a C++ class, typing "shift" near the class definition triggers completion items for output stream operators. The generated code includes proper field
formatting, null checks, and follows the configured style.

The plugin essentially automates the creation of boilerplate C++ code that would otherwise need to be written manually, making C++ development more efficient.

