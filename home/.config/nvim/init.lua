-- Entry point. Configuration is split under lua/config/ and lua/plugins/.

-- Disable unused built-in plugins (nvim-tree replaces netrw for directories).
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.g.loaded_gzip = 1
vim.g.loaded_zipPlugin = 1
vim.g.loaded_tarPlugin = 1

require("config.options")
require("config.plugins")
require("plugins.ui")
require("plugins.review")
require("plugins.treesitter")
require("plugins.telescope")
require("plugins.lsp")
require("plugins.ai")
require("config.keymaps")
