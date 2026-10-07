-- Theme
vim.cmd("colorscheme websafe")

-- Bufferline: Tab-like buffer list at top of window
require("bufferline").setup({})

-- Lualine: Status line at bottom of window
require("lualine").setup({})

require("fidget").setup({})

-- Gitsigns: gutter signs + inline current-line blame (replaces git-blame.nvim)
require("gitsigns").setup({
  current_line_blame = true,
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
