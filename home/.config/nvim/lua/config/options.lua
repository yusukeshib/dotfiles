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

-- Use OSC 52 for clipboard in remote/container environments (e.g. Docker, SSH).
-- Operator precedence note: `and` binds tighter than `or` in Lua. We want OSC52
-- whenever we are remote OR have no native clipboard tool available.
local _is_remote = os.getenv("SSH_TTY") ~= nil or os.getenv("container") ~= nil
local _no_native_clip = vim.fn.executable("pbcopy") == 0
  and vim.fn.executable("xclip") == 0
  and vim.fn.executable("wl-copy") == 0
-- Copy only: with clipboard=unnamedplus every `p` would otherwise send an
-- OSC 52 read request, which terminals block, prompt for, or time out on.
-- Paste returns Neovim's own unnamed register (see :h clipboard-osc52); paste
-- from the system clipboard with the terminal's paste instead.
if _is_remote or _no_native_clip then
  local osc52 = require("vim.ui.clipboard.osc52")
  local function paste_unnamed()
    return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
  end
  vim.g.clipboard = {
    name = "OSC 52 (copy only)",
    copy = {
      ["+"] = osc52.copy("+"),
      ["*"] = osc52.copy("*"),
    },
    paste = {
      ["+"] = paste_unnamed,
      ["*"] = paste_unnamed,
    },
  }
end

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
