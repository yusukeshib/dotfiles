-- Entry point. Configuration is split under lua/config/ and lua/plugins/.
require("config.options")
require("config.plugins")
require("plugins.ui")
require("plugins.telescope")
require("plugins.lsp")
require("plugins.ai")
require("config.keymaps")
