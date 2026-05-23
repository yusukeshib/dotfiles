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

require("sidekick").setup({
  cli = {
    mux = {
      enabled = false,
    },
  },
  nes = {
    enabled = false,
  },
})
