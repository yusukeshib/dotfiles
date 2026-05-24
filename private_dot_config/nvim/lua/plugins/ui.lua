-- Theme (high-contrast Dracula)
require("dracula").setup({
  colors = {
    bg = "#16171f",
    menu = "#0e0f15",
    fg = "#ffffff",
    comment = "#7d8ac0",
    selection = "#4d5174",
  },
  italic_comment = true,
})
vim.cmd("colorscheme dracula")

-- Bufferline: Tab-like buffer list at top of window
require("bufferline").setup({})

-- Lualine: Status line at bottom of window
require("lualine").setup({})

require("fidget").setup({})

require("tiny-inline-diagnostic").setup({
  preset = "minimal",
  options = {
    virt_texts = {
      priority = 10240,
    },
  },
})
vim.diagnostic.config({ virtual_text = false })
