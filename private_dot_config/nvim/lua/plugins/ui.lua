-- Theme (Dracula, slightly higher contrast than stock)
require("dracula").setup({
  colors = {
    bg = "#1e2030",
    menu = "#181a26",
    fg = "#f5f5f0",
    comment = "#7282b8",
    selection = "#464a66",
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
