-- Copyright (c) 2025 Augment
-- MIT License - See LICENSE.md for full terms

local M = {}

-- Start the lsp client
M.start_client = function(command)
    local vim_version = tostring(vim.version())
    local plugin_version = vim.call('augment#version#Version')

    local id = vim.lsp.start_client({
        name = 'Augment Server',
        cmd = command,
        init_options = {
            editor = 'nvim',
            vimVersion = vim_version,
            pluginVersion = plugin_version,
        },
        on_exit = function(code, signal, client_id)
            -- We can not call vim functions directly from callback functions.
            -- Instead, we schedule the functions for async execution
            vim.schedule(function()
                vim.call('augment#client#NvimOnExit', code, signal, client_id)
            end)
        end,
        -- TODO(mpauly): setup handlers. could use log message as a case study
        -- TODO(mpauly): on_error
    })
    return id
end

-- Attach the lsp client to a buffer
M.open_buffer = function(client_id, bufnr)
    vim.lsp.buf_attach_client(bufnr, client_id)
end

-- Send a lsp notification
M.notify = function(client_id, method, params)
    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
        vim.call('augment#log#Error', 'No lsp client found for id: ' .. client_id)
        return
    end

    client.notify(method, params)
end

-- Send a lsp request
M.request = function(client_id, method, params)
    local client = vim.lsp.get_client_by_id(client_id)
    if not client then
        vim.call('augment#log#Error', 'No lsp client found for id: ' .. client_id)
        return
    end

    local _, id = client.request(method, params, function(err, result)
        vim.call('augment#client#NvimResponse', method, params, result, err)
    end)
    return id
end

return M
