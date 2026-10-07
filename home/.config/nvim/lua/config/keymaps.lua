-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local reload_configuration = function()
  local vim_rc = os.getenv("MYVIMRC")
  print("Reloading configuration from: " .. vim_rc)
  vim.cmd.luafile(vim_rc)
end

local sidekick_toggle = function()
  require("sidekick.cli").toggle({ name = "pi", focus = true })
end

local themes = require("telescope.themes")

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

local function ivy_vertical(opts)
  opts = opts or {}
  return themes.get_ivy(vim.tbl_extend("force", {
    preview = true,
    hidden = true,
    layout_strategy = "vertical",
    layout_config = {
      height = vim.o.lines,
      width = vim.o.columns,
      prompt_position = "bottom",
      preview_height = 0.8,
    },
  }, opts))
end

local telescope_buffers = function()
  require("telescope.builtin").buffers(ivy_vertical({
    sort_lastused = true,
    ignore_current_buffer = false,
  }))
end

local telescope_rg = function()
  require("telescope.builtin").live_grep(ivy_vertical())
end

local telescope_git_history = function()
  require("telescope").extensions.advanced_git_search.search_log_content_file(ivy_vertical())
end

local telescope_aerial = function()
  require("telescope").extensions.aerial.aerial(ivy_vertical())
end

local cargo_expand_or_aerial = function()
  if not require("plugins.cargo_expand").toggle() then
    telescope_aerial()
  end
end

local telescope_lsp_refs = function()
  require("telescope.builtin").lsp_references(ivy_vertical())
end

-- ============================================================================
-- KEY MAPPINGS
-- ============================================================================

local wk = require("which-key")

wk.add({
  -- General editor shortcuts
  { "<Esc>",      "<cmd>nohlsearch<CR>",                desc = "Unhighlight search word",        mode = "n" },

  -- Window navigation (Ctrl + hjkl)
  { "<C-h>",      "<C-w><C-h>",                         desc = "Move focus to the left window",  mode = "n" },
  { "<C-l>",      "<C-w><C-l>",                         desc = "Move focus to the right window", mode = "n" },
  { "<C-j>",      "<C-w><C-j>",                         desc = "Move focus to the lower window", mode = "n" },
  { "<C-k>",      "<C-w><C-k>",                         desc = "Move focus to the upper window", mode = "n" },

  -- File and buffer navigation
  { "<C-a>",      "<cmd>NvimTreeFindFileToggle<CR>",    desc = "Toggle NvimTree",                mode = "n" },
  { "<C-p>",      telescope_files,                      desc = "Cmd+P",                          mode = "n" },
  { ";;",         telescope_buffers,                    desc = "List buffers",                   mode = "n" },

  -- Plugin management
  { "<F5>",       vim.pack.update,                      desc = "Update plugins",                 mode = "n" },

  -- AI assistants
  { "<C-\\>",     require("copilot.suggestion").accept, desc = "Accept Copilot suggestion",      mode = "i" },

  -- Leader key shortcuts (Space + ...)
  { "<leader>rg", telescope_rg,                         desc = "[R]ip[G]rep",                    mode = "n" },
  { "<leader>gd", vim.cmd.Gvdiffsplit,                  desc = "[G]it [D]iff",                   mode = "n" },
  { "<leader>rc", reload_configuration,                 desc = "Reload configuration",           mode = "n" },

  -- Git
  { "<leader>gh", telescope_git_history,                desc = "Git history",                    mode = "n" },

  -- LSP
  { "gd",         vim.lsp.buf.definition,               desc = "Go to definition",               mode = "n" },
  { "lr",         vim.lsp.buf.rename,                   desc = "Rename symbol",                  mode = "n" },
  { "gr",         telescope_lsp_refs,                   desc = "List references",                mode = "n" },
  { "<C-o>",      cargo_expand_or_aerial,               desc = "Expand Rust struct / symbols",  mode = "n" },

  -- sidekick
  { "<C-.>",      sidekick_toggle,                      desc = "Toggle Sidekick",                mode = { "i", "n", "t", "x" } },
})
