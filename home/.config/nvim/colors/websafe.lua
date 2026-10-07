-- websafe: pure web-safe palette, matches pi-coding-agent ~/.pi/agent/themes/websafe.json
vim.cmd("hi clear")
if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end
vim.o.background = "dark"
vim.g.colors_name = "websafe"

local c = {
  bg       = "#000000",
  bgAlt    = "#000033",
  bgSel    = "#003399",
  bgErr    = "#330000",
  bgOk     = "#003300",
  fg       = "#ffffff",
  grey     = "#999999",
  dimGrey  = "#666666",
  black    = "#000000",
  red      = "#ff0000",
  green    = "#00ff00",
  yellow   = "#ffff00",
  blue     = "#0066ff",
  magenta  = "#ff00ff",
  cyan     = "#00ffff",
  brRed    = "#ff0000",
  brGreen  = "#00ff00",
  brYellow = "#ffff00",
  brBlue   = "#66ccff",
  brMag    = "#ff00ff",
  brCyan   = "#00ffff",
  white    = "#ffffff",
  white7   = "#cccccc",
  orange   = "#ff9900",
  pink     = "#ff66cc",
}

local function hi(group, opts) vim.api.nvim_set_hl(0, group, opts) end

-- UI
hi("Normal",        { fg = c.fg, bg = c.bg })
hi("NormalFloat",   { fg = c.fg, bg = c.bgAlt })
hi("FloatBorder",   { fg = c.brCyan, bg = c.bgAlt })
hi("ColorColumn",   { bg = c.bgAlt })
hi("Cursor",        { fg = c.bg, bg = c.white })
hi("CursorLine",    { bg = c.bgAlt })
hi("CursorLineNr",  { fg = c.brYellow, bold = true })
hi("LineNr",        { fg = c.dimGrey })
hi("SignColumn",    { bg = c.bg })
hi("VertSplit",     { fg = c.dimGrey })
hi("WinSeparator",  { fg = c.dimGrey })
hi("StatusLine",    { fg = c.fg, bg = c.bgAlt })
hi("StatusLineNC",  { fg = c.grey, bg = c.bg })
hi("TabLine",       { fg = c.grey, bg = c.bgAlt })
hi("TabLineSel",    { fg = c.brBlue, bg = c.bg, bold = true })
hi("TabLineFill",   { bg = c.bg })
hi("Pmenu",         { fg = c.fg, bg = c.bgAlt })
hi("PmenuSel",      { fg = c.white, bg = c.bgSel, bold = true })
hi("PmenuSbar",     { bg = c.bgAlt })
hi("PmenuThumb",    { bg = c.brCyan })
hi("Visual",        { bg = c.bgSel })
hi("Search",        { fg = c.black, bg = c.brYellow })
hi("IncSearch",     { fg = c.black, bg = c.brMag })
hi("CurSearch",     { fg = c.black, bg = c.brMag, bold = true })
hi("MatchParen",    { fg = c.brYellow, bold = true, underline = true })
hi("Folded",        { fg = c.grey, bg = c.bgAlt })
hi("NonText",       { fg = c.dimGrey })
hi("Whitespace",    { fg = c.dimGrey })
hi("SpecialKey",    { fg = c.dimGrey })
hi("Conceal",       { fg = c.dimGrey })
hi("Directory",     { fg = c.brCyan, bold = true })
hi("Title",         { fg = c.brYellow, bold = true })
hi("Question",      { fg = c.brGreen })
hi("ModeMsg",       { fg = c.brYellow, bold = true })
hi("MoreMsg",       { fg = c.brGreen })
hi("ErrorMsg",      { fg = c.white, bg = c.red, bold = true })
hi("WarningMsg",    { fg = c.brYellow, bold = true })
hi("WinBar",        { fg = c.fg, bg = c.bgAlt })
hi("WinBarNC",      { fg = c.grey, bg = c.bg })

-- sidekick.nvim: keep the CLI/terminal pane black (default links to NormalFloat = navy)
hi("SidekickChat",  { fg = c.fg, bg = c.bg })

-- Syntax
hi("Comment",       { fg = c.dimGrey, italic = true })
hi("Constant",      { fg = c.orange })
hi("String",        { fg = c.brGreen })
hi("Character",     { fg = c.brGreen })
hi("Number",        { fg = c.orange })
hi("Boolean",       { fg = c.orange, bold = true })
hi("Float",         { fg = c.orange })
hi("Identifier",    { fg = c.fg })
hi("Function",      { fg = c.brBlue, bold = true })
hi("Statement",     { fg = c.brMag, bold = true })
hi("Conditional",   { fg = c.brMag, bold = true })
hi("Repeat",        { fg = c.brMag, bold = true })
hi("Label",         { fg = c.brMag })
hi("Operator",      { fg = c.pink })
hi("Keyword",       { fg = c.brMag, bold = true })
hi("Exception",     { fg = c.brRed, bold = true })
hi("PreProc",       { fg = c.brCyan })
hi("Include",       { fg = c.brCyan })
hi("Define",        { fg = c.brCyan })
hi("Macro",         { fg = c.brCyan })
hi("Type",          { fg = c.brCyan, bold = true })
hi("StorageClass",  { fg = c.brCyan })
hi("Structure",     { fg = c.brCyan })
hi("Typedef",       { fg = c.brCyan })
hi("Special",       { fg = c.brYellow })
hi("SpecialChar",   { fg = c.brYellow })
hi("Tag",           { fg = c.brCyan })
hi("Delimiter",     { fg = c.grey })
hi("SpecialComment",{ fg = c.brCyan, italic = true })
hi("Underlined",    { fg = c.brCyan, underline = true })
hi("Error",         { fg = c.white, bg = c.red })
hi("Todo",          { fg = c.black, bg = c.brYellow, bold = true })

-- Diagnostics
hi("DiagnosticError",      { fg = c.brRed })
hi("DiagnosticWarn",       { fg = c.brYellow })
hi("DiagnosticInfo",       { fg = c.brCyan })
hi("DiagnosticHint",       { fg = c.brGreen })
hi("DiagnosticOk",         { fg = c.brGreen })
hi("DiagnosticUnderlineError", { undercurl = true, sp = c.brRed })
hi("DiagnosticUnderlineWarn",  { undercurl = true, sp = c.brYellow })
hi("DiagnosticUnderlineInfo",  { undercurl = true, sp = c.brCyan })
hi("DiagnosticUnderlineHint",  { undercurl = true, sp = c.brGreen })

-- Diff
hi("DiffAdd",       { fg = c.brGreen, bg = c.bgOk })
hi("DiffChange",    { fg = c.brYellow, bg = c.bgAlt })
hi("DiffDelete",    { fg = c.brRed,   bg = c.bgErr })
hi("DiffText",      { fg = c.white,   bg = c.bgSel, bold = true })

-- Git signs
hi("GitSignsAdd",    { fg = c.brGreen })
hi("GitSignsChange", { fg = c.brYellow })
hi("GitSignsDelete", { fg = c.brRed })

-- Treesitter
hi("@variable",         { fg = c.fg })
hi("@variable.builtin", { fg = c.orange, italic = true })
hi("@parameter",        { fg = c.fg })
hi("@property",         { fg = c.brCyan })
hi("@field",            { fg = c.brCyan })
hi("@constructor",      { fg = c.brCyan, bold = true })
hi("@constant",         { fg = c.orange })
hi("@constant.builtin", { fg = c.orange, bold = true })
hi("@string",           { link = "String" })
hi("@number",           { link = "Number" })
hi("@function",         { link = "Function" })
hi("@function.builtin", { fg = c.brBlue, italic = true })
hi("@function.call",    { fg = c.brBlue })
hi("@method",           { fg = c.brBlue })
hi("@keyword",          { link = "Keyword" })
hi("@keyword.return",   { fg = c.brMag, bold = true })
hi("@type",             { link = "Type" })
hi("@type.builtin",     { fg = c.brCyan, italic = true })
hi("@tag",              { fg = c.brCyan })
hi("@tag.attribute",    { fg = c.brYellow })
hi("@punctuation",      { fg = c.grey })
hi("@punctuation.bracket", { fg = c.grey })
hi("@comment",          { link = "Comment" })

-- LSP semantic tokens
hi("@lsp.type.variable",  { fg = c.fg })
hi("@lsp.type.function",  { link = "Function" })
hi("@lsp.type.method",    { fg = c.brBlue })
hi("@lsp.type.parameter", { fg = c.fg })
hi("@lsp.type.property",  { fg = c.brCyan })
hi("@lsp.type.type",      { link = "Type" })
hi("@lsp.type.keyword",   { link = "Keyword" })
hi("@lsp.type.string",    { link = "String" })
hi("@lsp.type.number",    { link = "Number" })
hi("@lsp.type.comment",   { link = "Comment" })

-- Markdown
hi("@markup.heading",         { fg = c.brYellow, bold = true })
hi("@markup.heading.1",       { fg = c.brYellow, bold = true })
hi("@markup.heading.2",       { fg = c.brMag,    bold = true })
hi("@markup.heading.3",       { fg = c.brCyan,   bold = true })
hi("@markup.link",            { fg = c.brCyan, underline = true })
hi("@markup.link.url",        { fg = c.grey, underline = true })
hi("@markup.raw",             { fg = c.orange })
hi("@markup.list",            { fg = c.pink })
hi("@markup.quote",           { fg = c.grey, italic = true })
hi("@markup.strong",          { bold = true })
hi("@markup.italic",          { italic = true })

-- Terminal ANSI palette
vim.g.terminal_color_0  = c.black
vim.g.terminal_color_1  = c.red
vim.g.terminal_color_2  = c.green
vim.g.terminal_color_3  = c.yellow
vim.g.terminal_color_4  = c.blue
vim.g.terminal_color_5  = c.magenta
vim.g.terminal_color_6  = c.cyan
vim.g.terminal_color_7  = c.white7
vim.g.terminal_color_8  = c.grey
vim.g.terminal_color_9  = c.brRed
vim.g.terminal_color_10 = c.brGreen
vim.g.terminal_color_11 = c.brYellow
vim.g.terminal_color_12 = c.brBlue
vim.g.terminal_color_13 = c.brMag
vim.g.terminal_color_14 = c.brCyan
vim.g.terminal_color_15 = c.white
