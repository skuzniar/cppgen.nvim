# cppgen.nvim Agent Guidelines

## Build/Lint/Test Commands
- **No build system**: Pure Lua Neovim plugin, no compilation required
- **No lint command**: No linter configured
- **No test command**: No test framework or test files present
- **Single test execution**: N/A - no tests exist

## Code Style Guidelines

### Imports
- Use `local module = require('path')` for all imports
- Group related imports together at the top of files
- Follow existing module naming patterns (e.g., `cppgen.log`, `cppgen.ast`)

### Formatting
- Use 4 spaces for indentation (consistent with codebase)
- Line length: No strict limit, but keep lines readable
- Use consistent spacing around operators and after commas

### Types
- Dynamic typing - no explicit type annotations
- Use `local` for all variable declarations
- Return tables from modules for public interfaces

### Naming Conventions
- **Functions**: snake_case (e.g., `shift_snippet`, `labels_and_values`)
- **Variables**: snake_case (e.g., `max_lab_len`, `P.specifier`)
- **Modules**: lowercase with dots (e.g., `cppgen.generators.class`)
- **Constants**: UPPERCASE (e.g., `G`, `P` for global/private parameter tables)
- **CamelCase**: Used sparingly for specific contexts (e.g., function parameters)

### Error Handling
- Use logging for errors and debugging (`log.error`, `log.debug`)
- Return `nil` or empty tables for optional operations
- Check for `nil` values before operations
- Use assertions sparingly, prefer graceful degradation

### Code Structure
- Module pattern: Functions return a table `M` with public interface
- Separate private functions from public API
- Use parameter tables (`G` for globals, `P` for private) for configuration
- Group related functionality in dedicated modules

### Neovim Integration
- Use `vim.api` for Neovim API calls
- Follow LSP integration patterns for AST processing
- Use completion source registration with nvim-cmp
- Handle buffer and client lifecycle events properly