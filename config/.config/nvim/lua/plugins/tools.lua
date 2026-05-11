-- lua/plugins/tools.lua — file explorer, git, terminal, extras
return {
  -- ── File explorer (nvim-tree — matches josean's setup) ───────────────────
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = { width = 35 },
        renderer = { group_empty = true },
        filters = { dotfiles = false },
      })
      local map = vim.keymap.set
      map("n", "<leader>ee", "<cmd>NvimTreeToggle<CR>",         { desc = "Toggle explorer" })
      map("n", "<leader>ef", "<cmd>NvimTreeFindFileToggle<CR>", { desc = "Explorer on file" })
      map("n", "<leader>ec", "<cmd>NvimTreeCollapse<CR>",       { desc = "Collapse explorer" })
      map("n", "<leader>er", "<cmd>NvimTreeRefresh<CR>",        { desc = "Refresh explorer" })
    end,
  },

  -- ── Git ──────────────────────────────────────────────────────────────────
  "tpope/vim-fugitive",
  {
    "lewis6991/gitsigns.nvim",
    opts = {
      signs = {
        add    = { text = "+" },
        change = { text = "~" },
        delete = { text = "_" },
      },
    },
  },
  {
    "kdheepak/lazygit.nvim",
    cmd  = { "LazyGit", "LazyGitConfig", "LazyGitCurrentFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = { { "<leader>lg", "<cmd>LazyGit<CR>", desc = "LazyGit" } },
  },

  -- ── Terminal ─────────────────────────────────────────────────────────────
  {
    "akinsho/toggleterm.nvim",
    opts = { direction = "float" },
    keys = { { "<leader>t", "<cmd>ToggleTerm<CR>", desc = "Toggle terminal" } },
  },

  -- ── Copilot ──────────────────────────────────────────────────────────────
  "github/copilot.vim",

  -- ── Wakatime ─────────────────────────────────────────────────────────────
  "wakatime/vim-wakatime",
}
