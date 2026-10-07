-- Telescope: Fuzzy finder for files, text, buffers, etc.
local actions = require("telescope.actions")
require("telescope").setup({
  defaults = {
    mappings = {
      i = {
        ["<S-Down>"] = actions.cycle_history_next,
        ["<S-Up>"] = actions.cycle_history_prev,
      },
    },
  },
  extensions = {
    advanced_git_search = {},
    aerial = {
      col1_width = 4,
      col2_width = 30,
      format_symbol = function(symbol_path, filetype)
        if filetype == "json" or filetype == "yaml" then
          return table.concat(symbol_path, ".")
        else
          return symbol_path[#symbol_path]
        end
      end,
      show_columns = "both",
    },
  },
})

require("aerial").setup({})
require("telescope").load_extension("aerial")
require("telescope").load_extension("advanced_git_search")

-- NvimTree: File explorer
require("nvim-tree").setup({
  sync_root_with_cwd = true,
  respect_buf_cwd = true,
  update_focused_file = {
    enable = true,
    update_root = true,
  },
  filters = {
    git_ignored = false,
    dotfiles = false,
  },
  view = {
    width = 50,
  },
})

require("nvim-rooter").setup({})
