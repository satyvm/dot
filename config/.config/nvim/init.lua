-- =============================================================================
-- init.lua — Neovim config (satyvm)
-- Structure: init.lua → lua/plugins/*.lua (one file per concern)
-- =============================================================================

-- ── Bootstrap lazy.nvim ───────────────────────────────────────────────────────
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- ── Leader (must be before lazy) ─────────────────────────────────────────────
vim.g.mapleader      = " "
vim.g.maplocalleader = " "

-- =============================================================================
-- OPTIONS
-- =============================================================================
local opt = vim.opt

opt.number         = true
opt.relativenumber = true
opt.signcolumn     = "yes"
opt.cursorline     = true

opt.tabstop        = 2
opt.shiftwidth     = 2
opt.expandtab      = true
opt.autoindent     = true

opt.wrap           = false
opt.scrolloff      = 8
opt.sidescrolloff  = 8

opt.ignorecase     = true
opt.smartcase      = true
opt.hlsearch       = false

opt.undofile       = true
opt.swapfile       = false
opt.backup         = false

opt.termguicolors  = true
opt.background     = "dark"
opt.showmode       = false
opt.timeoutlen     = 200
opt.updatetime     = 250
opt.completeopt    = "menu,menuone,preview,noselect"

opt.splitright     = true
opt.splitbelow     = true
opt.backspace      = "indent,eol,start"
opt.clipboard:append("unnamedplus") -- use system clipboard by default

-- Disable netrw (we use nvim-tree)
vim.g.loaded_netrw       = 1
vim.g.loaded_netrwPlugin = 1

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  callback = function() vim.highlight.on_yank() end,
})

-- Restore cursor position
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local line_count = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= line_count then
      vim.api.nvim_win_set_cursor(0, mark)
    end
  end,
})

-- =============================================================================
-- KEYMAPS
-- =============================================================================
local map = vim.keymap.set

-- Escape
map("i", "jk", "<ESC>", { desc = "Exit insert mode" })
map("n", "<leader>nh", ":nohl<CR>", { desc = "Clear search highlights" })

-- Increment / decrement
map("n", "<leader>+", "<C-a>", { desc = "Increment number" })
map("n", "<leader>-", "<C-x>", { desc = "Decrement number" })

-- Window splits
map("n", "<leader>sv", "<C-w>v",        { desc = "Split vertical" })
map("n", "<leader>sh", "<C-w>s",        { desc = "Split horizontal" })
map("n", "<leader>se", "<C-w>=",        { desc = "Equalise splits" })
map("n", "<leader>sx", "<cmd>close<CR>",{ desc = "Close split" })

-- Tabs
map("n", "<leader>to", "<cmd>tabnew<CR>",   { desc = "New tab" })
map("n", "<leader>tx", "<cmd>tabclose<CR>", { desc = "Close tab" })
map("n", "<leader>tn", "<cmd>tabn<CR>",     { desc = "Next tab" })
map("n", "<leader>tp", "<cmd>tabp<CR>",     { desc = "Previous tab" })
map("n", "<leader>tf", "<cmd>tabnew %<CR>", { desc = "Move buffer to tab" })

-- Clipboard (macOS-style)
map({ "n", "v" }, "<C-c>", '"+y',   { desc = "Copy to clipboard" })
map({ "n", "v" }, "<C-v>", '"+p',   { desc = "Paste from clipboard" })
map("n",          "<C-s>", "<cmd>w<CR>", { desc = "Save" })

-- Visual indent
map("v", "<Tab>",   ">gv", { noremap = true, silent = true })
map("v", "<S-Tab>", "<gv", { noremap = true, silent = true })

-- Buffer nav
map("n", "n", "<cmd>bnext<CR>",     { desc = "Next buffer" })
map("m", "m", "<cmd>bprevious<CR>", { desc = "Prev buffer" })

-- Maximize split
map("n", "<leader>sm", "<cmd>MaximizerToggle<CR>", { desc = "Maximize split" })

-- Word replace in file
map("n", "<leader>rw", function()
  local word = vim.fn.expand("<cword>")
  local new  = vim.fn.input('Replace "' .. word .. '" with: ')
  if new ~= "" then vim.cmd("%s/" .. word .. "/" .. new .. "/gc") end
end, { desc = "Replace word in file" })

-- LSP toggle
map("n", "<leader>L", function()
  local clients = vim.lsp.get_active_clients()
  if #clients == 0 then vim.cmd("LspStart"); vim.notify("LSP started")
  else vim.cmd("LspStop"); vim.notify("LSP stopped") end
end, { desc = "Toggle LSP" })

-- =============================================================================
-- PLUGINS  (each file in lua/plugins/ returns a lazy spec table)
-- =============================================================================
require("lazy").setup({ { import = "plugins" } }, {
  install  = { colorscheme = { "tokyonight" } },
  checker  = { enabled = true, notify = false, frequency = 86400 },
  ui       = { border = "rounded" },
  change_detection = { notify = false },
})
