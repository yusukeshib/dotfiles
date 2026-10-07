-- nvim-treesitter (main branch API; the legacy `nvim-treesitter.configs`
-- module no longer exists). Parsers are installed explicitly and features
-- (highlight + indent) are enabled per-buffer via a FileType autocmd, since
-- the main branch does NOT auto-enable anything.
-- Requires the tree-sitter CLI + a C compiler to build parsers.

local ok, ts = pcall(require, "nvim-treesitter")
if not ok then
  return
end

local langs = {
  "bash", "c", "css", "diff", "dockerfile", "gitignore", "go", "html",
  "javascript", "json", "lua", "luadoc", "markdown",
  "markdown_inline", "python", "query", "regex", "rust", "toml", "tsx",
  "typescript", "vim", "vimdoc", "yaml",
}

-- Install missing parsers asynchronously (no-op for already-installed ones).
pcall(function()
  ts.install(langs)
end)

-- Enable highlighting + treesitter indentation for buffers whose filetype
-- maps to an available parser.
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("treesitter_start", { clear = true }),
  callback = function(args)
    local ft = vim.bo[args.buf].filetype
    local lang = vim.treesitter.language.get_lang(ft)
    if not lang then
      return
    end
    if pcall(vim.treesitter.start, args.buf, lang) then
      vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
    end
  end,
})
