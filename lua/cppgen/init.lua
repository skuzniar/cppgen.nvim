local log = require('cppgen.log')
local opt = require("cppgen.options")
local cgn = require("cppgen.cppgen")

---------------------------------------------------------------------------------------------------
-- Bootstrap entry point. Configures code generation module using default and user options.
---------------------------------------------------------------------------------------------------
local M = {}

local cppgen = 'CppGen'
local csrcid = nil

--- LSP attach callback
local function attach(client, bufnr)
    log.info("Client", log.squoted(client.name), "attached to", log.squoted(vim.api.nvim_buf_get_name(bufnr)))

	cgn.attached(client, bufnr)

	local group = vim.api.nvim_create_augroup(cppgen, { clear = false })

	vim.api.nvim_clear_autocmds({
		group  = group,
		buffer = bufnr
	})

	vim.api.nvim_create_autocmd({ "InsertEnter" }, {
		callback = function(args)
			cgn.insert_enter(bufnr)
		end,
		group  = group,
		buffer = bufnr
	})
	vim.api.nvim_create_autocmd({ "InsertLeave" }, {
		callback = function(args)
			cgn.insert_leave(bufnr)
		end,
		group  = group,
		buffer = bufnr
	})
	vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		callback = function(args)
			cgn.after_write(bufnr)
		end,
		group  = group,
		buffer = bufnr
	})

    -- Add our source to cmp
    if not csrcid then
        log.info("Adding completion source", log.squoted(cppgen))
        csrcid = require('cmp').register_source(cppgen, cgn.source())
    end
end

--- Setup
function M.setup(opts)
    -- Combine default options with user options
    local options = opt.merge(opt.default, opts)

    log.new(options.log, true)

    cgn.setup(options)

	vim.api.nvim_create_autocmd("LspAttach", {
		callback = function(args)
            if vim.bo.filetype == "cpp" then
			    local client = vim.lsp.get_client_by_id(args.data.client_id)
                log.info("Attached:", log.squoted(client.name), "which", client.server_capabilities.astProvider and "is" or "is not", "capable of delivering AST data.")
	            if client.server_capabilities.astProvider then
				    attach(client, args.buf)
			    end
			end
		end,
	})
end

return M
