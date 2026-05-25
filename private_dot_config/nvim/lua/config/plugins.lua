-- ============================================================================
-- PLUGINS (declarations only; configuration lives in lua/plugins/*.lua)
-- ============================================================================

vim.pack.add({

  --
  -- Editor behavior
  --

  -- Auto-detect indentation (tabs/spaces)
  { src = "https://github.com/tpope/vim-sleuth" },
  -- Advanced search/replace with case variants
  { src = "https://github.com/tpope/vim-abolish" },
  -- Auto-change working directory to project root
  { src = "https://github.com/notjedi/nvim-rooter.lua" },

  -- File
  { src = "https://github.com/stevearc/oil.nvim" },

  --
  -- Theme and UI
  --

  { src = "https://github.com/akinsho/bufferline.nvim" },
  { src = "https://github.com/nvim-lualine/lualine.nvim" },
  { src = "https://github.com/folke/which-key.nvim" },

  --
  -- Syntax and language support
  --

  { src = "https://github.com/stevearc/aerial.nvim" },
  { src = "https://github.com/nvim-treesitter/nvim-treesitter" },

  --
  -- Git integration
  --

  { src = "https://github.com/tpope/vim-fugitive" },
  { src = "https://github.com/tpope/vim-rhubarb" },
  { src = "https://github.com/sindrets/diffview.nvim" },
  { src = "https://github.com/f-person/git-blame.nvim" },
  { src = "https://github.com/lewis6991/gitsigns.nvim" },
  { src = "https://github.com/aaronhallaert/advanced-git-search.nvim" },

  --
  -- File navigation and search
  --

  { src = "https://github.com/nvim-lua/plenary.nvim" },
  { src = "https://github.com/nvim-telescope/telescope.nvim" },
  { src = "https://github.com/nvim-tree/nvim-tree.lua" },

  --
  -- LSP (Language Server Protocol)
  --

  { src = "https://github.com/neovim/nvim-lspconfig" },
  { src = "https://github.com/mason-org/mason.nvim" },
  { src = "https://github.com/mason-org/mason-lspconfig.nvim" },
  { src = "https://github.com/rachartier/tiny-inline-diagnostic.nvim" },
  { src = "https://github.com/stevearc/conform.nvim" },
  { src = "https://github.com/j-hui/fidget.nvim" },

  --
  -- Code completion and AI
  --

  { src = "https://github.com/Saghen/blink.lib" },
  { src = "https://github.com/Saghen/blink.cmp" },
  { src = "https://github.com/zbirenbaum/copilot.lua" },
  { src = "https://github.com/folke/sidekick.nvim" },
})
