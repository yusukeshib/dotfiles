-- Configure Lua language server with nvim runtime path awareness
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      workspace = {
        library = vim.api.nvim_get_runtime_file("", true),
      },
    },
  },
})

require("mason").setup({})

require("mason-lspconfig").setup({
  ensure_installed = { "lua_ls", "pyright", "ts_ls", "rust_analyzer" },
  automatic_enable = true,
})

-- Blink.cmp: Completion engine
require("blink.cmp").setup({
  completion = {
    accept = {
      auto_brackets = { enabled = false },
    },
  },
  keymap = {
    preset = "default",
    ["<S-Tab>"] = { "select_prev", "fallback" },
    ["<Tab>"] = { "select_next", "fallback" },
    ["<CR>"] = { "accept", "fallback" },
  },
  fuzzy = { implementation = "lua" },
})

-- Conform: Format code on save
require("conform").setup({
  formatters_by_ft = {
    lua = { "stylua" },
    python = { "ruff" },
    javascript = { "prettierd", "prettier", stop_after_first = true },
    typescript = { "prettierd", "prettier", stop_after_first = true },
    javascriptreact = { "prettierd", "prettier", stop_after_first = true },
    typescriptreact = { "prettierd", "prettier", stop_after_first = true },
    json = { "prettierd", "prettier", stop_after_first = true },
    css = { "prettierd", "prettier", stop_after_first = true },
    html = { "prettierd", "prettier", stop_after_first = true },
    markdown = { "prettierd", "prettier", stop_after_first = true },
  },
  format_on_save = {
    timeout_ms = 500,
    lsp_format = "fallback",
  },
})
