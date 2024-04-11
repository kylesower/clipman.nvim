return require("telescope").register_extension({
    setup = function(ext_config, config)
        require("clipman").setup(ext_config)
    end,
    exports = {
        copy = require("clipman").copy,
        paste = require("clipman").paste,
    }
})
