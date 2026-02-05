-- ============================================================================
-- GENERAL SETTINGS
-- ============================================================================

-- Set leader key to space for custom key bindings
vim.g.mapleader = " "

-- Display line numbers in the gutter
vim.opt.number = true

-- Enable mouse support in all modes
vim.opt.mouse = "a"

-- Use system clipboard for yank/paste operations
vim.opt.clipboard = "unnamedplus"

-- Preserve indentation when wrapping lines
vim.opt.breakindent = true

-- Save undo history to file for persistence across sessions
vim.opt.undofile = true

-- Case-insensitive search by default
vim.opt.ignorecase = true

-- Override ignorecase if search contains uppercase letters
vim.opt.smartcase = true

-- Always show sign column (prevents layout shift for git/diagnostic signs)
vim.opt.signcolumn = "yes"

-- Open vertical splits to the right of current window
vim.opt.splitright = true

-- Open horizontal splits below current window
vim.opt.splitbelow = true

-- Display whitespace characters
vim.opt.list = true

-- Define how whitespace characters are displayed (tabs, trailing spaces, nbsp)
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }

-- Show live preview of substitute commands in split window
vim.opt.inccommand = "split"

-- Highlight the line containing the cursor
vim.opt.cursorline = true

-- Keep 3 lines visible above/below cursor when scrolling
vim.opt.scrolloff = 3

-- Faster update time for better UX (affects CursorHold, swap file writes)
vim.opt.updatetime = 250

-- Time to wait for mapped sequence to complete (milliseconds)
vim.opt.timeoutlen = 300

-- Enable 24-bit RGB colors in the terminal
vim.opt.termguicolors = true

-- Prevent LSP completion from auto-selecting the first item
vim.opt.completeopt = { "menuone", "noselect", "popup" }

-- ============================================================================
-- PLUGINS
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

  -- GitHub-themed color schemes
  { src = "https://github.com/scottmckendry/cyberdream.nvim" },
  -- Tab/buffer line at the top
  { src = "https://github.com/akinsho/bufferline.nvim" },
  -- Status line at the bottom
  { src = "https://github.com/nvim-lualine/lualine.nvim" },
  -- Show available key bindings in popup
  { src = "https://github.com/folke/which-key.nvim" },

  --
  -- Syntax and language support
  --

  { src = "https://github.com/stevearc/aerial.nvim" },

  -- Modern syntax highlighting
  { src = "https://github.com/nvim-treesitter/nvim-treesitter" },

  --
  -- Git integration
  --

  -- Git commands within vim
  { src = "https://github.com/tpope/vim-fugitive" },
  { src = "https://github.com/tpope/vim-rhubarb", },
  -- Enhanced diff viewer
  { src = "https://github.com/sindrets/diffview.nvim" },
  -- Show git blame as virtual text
  { src = "https://github.com/f-person/git-blame.nvim" },
  -- Git diff signs in gutter
  { src = "https://github.com/lewis6991/gitsigns.nvim" },
  -- Git history
  { src = "https://github.com/aaronhallaert/advanced-git-search.nvim" },

  --
  -- File navigation and search
  --

  -- Lua utility library (dependency)
  { src = "https://github.com/nvim-lua/plenary.nvim" },
  -- Fuzzy finder (files, text, buffers)
  { src = "https://github.com/nvim-telescope/telescope.nvim" },
  -- File explorer tree view
  { src = "https://github.com/nvim-tree/nvim-tree.lua" },

  --
  -- LSP (Language Server Protocol)
  --

  -- LSP configuration presets
  { src = "https://github.com/neovim/nvim-lspconfig" },
  -- Language server installer
  { src = "https://github.com/mason-org/mason.nvim" },
  -- Bridge mason & lspconfig
  { src = "https://github.com/mason-org/mason-lspconfig.nvim" },
  -- Inline LSP diagnostics
  { src = "https://github.com/rachartier/tiny-inline-diagnostic.nvim" },
  -- Format-on-save with multiple formatters
  { src = "https://github.com/stevearc/conform.nvim" },
  { src = "https://github.com/j-hui/fidget.nvim" },

  --
  -- Code completion and AI
  --

  -- Completion engine
  { src = "https://github.com/Saghen/blink.cmp" },
  -- GitHub Copilot integration
  { src = "https://github.com/zbirenbaum/copilot.lua" },
  -- ClaudeCode integration
  { src = "https://github.com/folke/sidekick.nvim" },
})

-- ============================================================================
-- THEME
-- ============================================================================

-- Apply the carbonfox color scheme
vim.cmd("colorscheme cyberdream")

-- ============================================================================
-- PLUGIN CONFIGURATION
-- ============================================================================

-- Telescope: Fuzzy finder for files, text, buffers, etc.
local actions = require("telescope.actions")
require("telescope").setup({
  defaults = {
    mappings = {
      i = {
        ["<S-Down>"] = actions.cycle_history_next,
        ["<S-Up>"] = actions.cycle_history_prev,
      }
    }
  },
  extensions = {
    advanced_git_search = {},
    aerial = {
      -- Set the width of the first two columns (the second
      -- is relevant only when show_columns is set to 'both')
      col1_width = 4,
      col2_width = 30,
      -- How to format the symbols
      format_symbol = function(symbol_path, filetype)
        if filetype == "json" or filetype == "yaml" then
          return table.concat(symbol_path, ".")
        else
          return symbol_path[#symbol_path]
        end
      end,
      -- Available modes: symbols, lines, both
      show_columns = "both",
    },
  },
})

require("aerial").setup({})
require("telescope").load_extension("aerial")
require("telescope").load_extension("advanced_git_search")

-- NvimTree: File explorer
require("nvim-tree").setup({
  -- Sync tree root with current working directory
  sync_root_with_cwd = true,
  respect_buf_cwd = true,
  update_focused_file = {
    enable = true,
    -- Auto-update tree root when changing files
    update_root = true,
  },
  filters = {
    -- Show git ignored files
    git_ignored = false,
    -- Show dotfiles
    dotfiles = false,
  },
  view = {
    width = 50,
  },
})

-- NvimRooter: Auto-change working directory to project root
require("nvim-rooter").setup({})

-- Bufferline: Tab-like buffer list at top of window
require("bufferline").setup({})

-- Lualine: Status line at bottom of window
require("lualine").setup({})

require("fidget").setup({})

require('sidekick').setup({
  cli = {
    mux = {
      enabled = false,
    }
  },
  nes = {
    enabled = false,
  },
})

require("tiny-inline-diagnostic").setup({
  preset = "minimal",
  options = {
    virt_texts = {
      priority = 10240,
    },
  },
})
vim.diagnostic.config({ virtual_text = false })

-- ============================================================================
-- COPILOT & AI ASSISTANTS
-- ============================================================================

-- GitHub Copilot: AI code suggestions
require("copilot").setup({
  suggestion = {
    enabled = true,
    auto_trigger = true,
    accept = false,
  },
  nes = {
    enabled = false,
  },
  panel = {
    enabled = false,
  },
})

-- ============================================================================
-- LSP (LANGUAGE SERVER PROTOCOL)
-- ============================================================================

-- Configure Lua language server with nvim runtime path awareness
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      workspace = {
        -- Make language server aware of Neovim runtime files
        library = vim.api.nvim_get_runtime_file("", true),
      },
    },
  },
})

-- Mason: Install and manage language servers
require("mason").setup({})

-- Mason-LSPConfig: Bridge between Mason and LSP
require("mason-lspconfig").setup({
  -- Automatically install these language servers
  ensure_installed = { "lua_ls", "pyright", "ts_ls", "rust_analyzer" },
  -- Automatically enable LSP servers after installation
  automatic_enable = true,
})

-- ============================================================================
-- AUTO-COMPLETION
-- ============================================================================

-- Blink.cmp: Completion engine
require("blink.cmp").setup({
  completion = {
    accept = {
      -- Don't auto-insert brackets after accepting completion
      auto_brackets = { enabled = false },
    },
  },
  keymap = {
    preset = "default",
    -- Navigate completion menu with Tab/Shift-Tab
    ["<S-Tab>"] = { "select_prev", "fallback" },
    ["<Tab>"] = { "select_next", "fallback" },
    -- Accept completion with Enter
    ["<CR>"] = { "accept", "fallback" },
  },
  -- Use pure Lua fuzzy matching (faster)
  fuzzy = { implementation = "lua" },
})

-- ============================================================================
-- CODE FORMATTING
-- ============================================================================

-- Conform: Format code on save
require("conform").setup({
  -- Define formatters for each file type
  formatters_by_ft = {
    lua = { "stylua" },
    python = { "ruff" },
    javascript = { "eslint_d" },
    typescript = { "eslint_d" },
    javascriptreact = { "eslint_d" },
    typescriptreact = { "eslint_d" },
  },
  -- Automatically format on save
  format_on_save = {
    timeout_ms = 500,
    -- Use LSP formatter if conform formatter not available
    lsp_format = "fallback",
  },
})

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Reload Neovim configuration without restarting
local reload_configuration = function()
  local vim_rc = os.getenv("MYVIMRC")
  print("Reloading configuration from: " .. vim_rc)
  vim.cmd.luafile(vim_rc)
end


local sidekick_toggle = function()
  require("sidekick.cli").toggle({ name = "claude", focus = true })
end

local themes = require('telescope.themes')

local telescope_files = function()
  require("telescope.builtin").find_files(themes.get_ivy({
    preview = false,
    hidden = true,
    layout_config = {
      width = { padding = 0 },
      height = 10,
    },
  }))
end

local telescope_buffers = function()
  require("telescope.builtin").buffers(themes.get_ivy({
    preview = true,
    hidden = true,
    layout_strategy = "vertical",
    layout_config = {
      height = vim.o.lines,  -- maximally available lines
      width = vim.o.columns, -- maximally available columns
      prompt_position = "bottom",
      preview_height = 0.8
    },
    sort_lastused = true,
    ignore_current_buffer = false,
  }))
end

local telescope_rg = function()
  require("telescope.builtin").live_grep(themes.get_ivy({
    preview = true,
    hidden = true,
    layout_strategy = "vertical",
    layout_config = {
      height = vim.o.lines,  -- maximally available lines
      width = vim.o.columns, -- maximally available columns
      prompt_position = "bottom",
      preview_height = 0.8
    },
  }))
end

local telescope_git_history = function()
  require("telescope").extensions.advanced_git_search.search_log_content_file(themes.get_ivy({
    preview = true,
    hidden = true,
    layout_strategy = "vertical",
    layout_config = {
      height = vim.o.lines,  -- maximally available lines
      width = vim.o.columns, -- maximally available columns
      prompt_position = "bottom",
      preview_height = 0.8
    },
  }))
end

local telescope_aerial = function()
  require("telescope").extensions.aerial.aerial(themes.get_ivy({
    preview = true,
    hidden = true,
    layout_strategy = "vertical",
    layout_config = {
      height = vim.o.lines,  -- maximally available lines
      width = vim.o.columns, -- maximally available columns
      prompt_position = "bottom",
      preview_height = 0.8
    },
  }))
end

local telescope_lsp_refs = function()
  require('telescope.builtin').lsp_references(themes.get_ivy({
    preview = true,
    hidden = true,
    layout_strategy = "vertical",
    layout_config = {
      height = vim.o.lines,  -- maximally available lines
      width = vim.o.columns, -- maximally available columns
      prompt_position = "bottom",
      preview_height = 0.8
    },
  }))
end

-- ============================================================================
-- KEY MAPPINGS
-- ============================================================================

local wk = require("which-key")

wk.add({
  -- General editor shortcuts
  { "<Esc>",      "<cmd>nohlsearch<CR>",                desc = "Unhighlight search word",        mode = "n", },

  -- Window navigation (Ctrl + hjkl)
  { "<C-h>",      "<C-w><C-h>",                         desc = "Move focus to the left window",  mode = "n", },
  { "<C-l>",      "<C-w><C-l>",                         desc = "Move focus to the right window", mode = "n", },
  { "<C-j>",      "<C-w><C-j>",                         desc = "Move focus to the lower window", mode = "n", },
  { "<C-k>",      "<C-w><C-k>",                         desc = "Move focus to the upper window", mode = "n", },

  -- File and buffer navigation
  { "<C-a>",      "<cmd>NvimTreeFindFileToggle<CR>",    desc = "Toggle NvimTree",                mode = "n", },
  { "<C-p>",      telescope_files,                      desc = "Cmd+P",                          mode = "n", },
  { ";;",         telescope_buffers,                    desc = "List buffers",                   mode = "n", },

  -- Plugin management
  { "<F5>",       vim.pack.update,                      desc = "Update plugins",                 mode = "n", },

  -- AI assistants
  { "<C-\\>",     require("copilot.suggestion").accept, desc = "Accept Copilot suggestion",      mode = "i", },

  -- Leader key shortcuts (Space + ...)
  { "<leader>rg", telescope_rg,                         desc = "[R]ip[G]rep",                    mode = "n", },
  { "<leader>gd", vim.cmd.Gvdiffsplit,                  desc = "[G]it [D]iff",                   mode = "n", },
  { "<leader>rc", reload_configuration,                 desc = "Reload configuration",           mode = "n", },

  -- Git
  { "<C-h>",      telescope_git_history,                desc = "Git history",                    mode = "n", },

  -- LSP
  { "gd",         vim.lsp.buf.definition,               desc = "Go to definition",               mode = "n", },
  { "lr",         vim.lsp.buf.rename,                   desc = "Rename symbol",                  mode = "n", },
  { "gr",         telescope_lsp_refs,                   desc = "List references",                mode = "n", },
  { "<C-o>",      telescope_aerial,                     desc = "List document symbols",          mode = "n", },

  -- sidekick
  { "<C-.>",      sidekick_toggle,                      desc = "Toggle Sidekick",                mode = { "i", "n", "t", "x" } },
})
