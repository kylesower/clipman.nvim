local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local previewers = require "telescope.previewers"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local conf = require "telescope.config".values
local themes = require "telescope.themes"
local M = {}
M._config = {}
M._telescope_opts = {}

local join_lines = function(lines)
    local val = ""
    for _, line in pairs(lines) do
        if val == "" then
            val = line
        else
            val = val .. "\n" .. line
        end
    end
    return val
end

local split_lines = function(input)
    local lines = {}
    for line in input:gmatch("([^\n]+)") do
        table.insert(lines, line)
    end
    return lines
end

local dash_pattern = "^[%s]*[-][-]"
-- Gets name, value, and split lines from clip file
local get_lines_and_groups = function(input)
    local current_lines = {}
    local groups = {}
    for _, line in pairs(split_lines(input)) do
        if not line:match(dash_pattern) then
            table.insert(current_lines, line)
        elseif line:match(dash_pattern) and #current_lines > 0 then
            local name, val = current_lines[1]:gmatch("(.-)::(.*)")()
            print(name, current_lines[1])
            current_lines[1] = val
            table.insert(groups,
                { name = name, lines = current_lines, value = join_lines(current_lines) })
            current_lines = {}
        end
    end
    local name, val = current_lines[1]:gmatch("(.-)::(.*)")()
    current_lines[1] = val
    table.insert(groups,
        { name = name, lines = current_lines, value = join_lines(current_lines) })
    return groups
end

local make_results = function(config)
    -- Clips should be
    -- { {"clip name", "clip value"}, {"clip name", "clip value"} }
    -- The path should point to a file which is formatted like
    -- clip name::clip value
    -- clip value part 2
    -- --
    -- clip name2::clip value2
    --
    -- Basically, names and values are separated by a double colon, and pairs
    -- are separated by a double dash (lines starting with -- are ignored).
    config = config or {}
    local clips = config.clips or {}
    local clip_file = config.path or ""
    assert((next(clips) == nil) ~= (clip_file == ""), "must pass in only table of clips or path to clip file, not both")
    if clip_file == "" then
        local formatted_clips = {}
        for _, pair in pairs(clips) do
            assert(#pair == 2, "all clip inputs should have two elements")
            local value = pair[2]
            table.insert(formatted_clips, { name = pair[1], value = value, lines = split_lines(value) })
        end
        return formatted_clips
    end
    local command = { 'cat', clip_file }
    local output = vim.fn.system(command)
    local groups = get_lines_and_groups(output)
    return groups
end

local table_contains = function(t, val)
    for _, v in pairs(t) do
        if t == val then
            return true
        end
    end
    return false
end

M.setup = function(config, telescope_opts) --, telescope_opts)
    M._config = config or {}
    M._config = vim.tbl_deep_extend("force", {
            path = "~/.config/clipman.nvim/clips",
            register = "+",
            copy_with_surrounding_newlines = false,
        },
        M._config)
    M._telescope_opts = telescope_opts or {}
    if M._config.copy_with_surrounding_newlines then
        if M._config.register == "+" then
            -- idk why this one behaves special. Other registers could be weird.
            -- Only tested + and "
            M._copy_command = '%y +'
        else
            M._copy_command = '%y "' .. M._config.register
        end
    else
        M._copy_command = 'norm gg^vG$"' .. M._config.register .. 'y'
    end
end

M.copy = function(opts)
    local preview_bufnr
    opts = opts or {}
    opts = vim.tbl_deep_extend("force", themes.get_cursor({}), opts)

    pickers.new(opts, {
        prompt_title = "Entries", -- optional
        finder = finders.new_table {
            results = make_results(M._config),
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry["name"],
                    ordinal = entry["name"] .. entry["value"],
                }
            end,
        },
        previewer = previewers.new_buffer_previewer({
            -- TODO: Don't rely on preview buffer for copying.
            -- As it is, it only works when the preview is visible, so it
            -- depends on themes and whatnot.
            define_preview = function(self, entry)
                preview_bufnr = self.state.bufnr
                vim.api.nvim_buf_set_lines(preview_bufnr, 0, #entry.value["lines"], false, entry.value["lines"])
            end,
            title = function(self)
                return "Command"
            end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                vim.api.nvim_buf_call(preview_bufnr, function()
                    vim.api.nvim_exec2(M._copy_command, { output = false })
                end)
                actions.close(prompt_bufnr)
            end)
            return true
        end,
    }):find()
end

M.paste = function(opts)
    local preview_bufnr
    opts = opts or {}
    opts = vim.tbl_deep_extend("force", themes.get_cursor({}), opts)
    pickers.new(opts, {
        prompt_title = "Entries", -- optional
        finder = finders.new_table {
            results = make_results(M._config),
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry["name"],
                    ordinal = entry["name"] .. entry["value"],
                }
            end,
        },
        previewer = previewers.new_buffer_previewer({
            -- TODO: Don't rely on preview buffer for copying.
            -- As it is, it only works when the preview is visible, so it
            -- depends on themes and whatnot.
            define_preview = function(self, entry)
                preview_bufnr = self.state.bufnr
                vim.api.nvim_buf_set_lines(preview_bufnr, 0, #entry.value["lines"], false, entry.value["lines"])
            end,
            title = function(self)
                return "Command"
            end,
        }),
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                -- TODO: Paste without disturbing the clipboard
                vim.api.nvim_buf_call(preview_bufnr, function()
                    vim.api.nvim_exec2(M._copy_command, { output = false })
                end)
                actions.close(prompt_bufnr)
                vim.api.nvim_exec2("norm p", { output = false })
            end)
            return true
        end,
    }):find()
end

M.setup()
return M
