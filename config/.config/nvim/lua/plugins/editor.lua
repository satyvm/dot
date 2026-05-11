-- lua/plugins/editor.lua — editing: telescope, treesitter, git, sessions
return {
  "nvim-lua/plenary.nvim",
  "christoomey/vim-tmux-navigator",

  -- ── Telescope ────────────────────────────────────────────────────────────
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      local telescope = require("telescope")
      local actions   = require("telescope.actions")
      telescope.setup({
        defaults = {
          path_display = { "smart" },
          mappings = {
            i = {
              ["<C-k>"] = actions.move_selection_previous,
              ["<C-j>"] = actions.move_selection_next,
              ["<C-q>"] = actions.send_selected_to_qflist + actions.open_qflist,
            },
          },
        },
      })
      telescope.load_extension("fzf")
      local map = vim.keymap.set
      map("n", "<leader>ff", "<cmd>Telescope find_files<CR>",  { desc = "Find files" })
      map("n", "<leader>fr", "<cmd>Telescope oldfiles<CR>",    { desc = "Recent files" })
      map("n", "<leader>fs", "<cmd>Telescope live_grep<CR>",   { desc = "Find string" })
      map("n", "<leader>fc", "<cmd>Telescope grep_string<CR>", { desc = "Cursor word" })
      map("n", "<leader>ft", "<cmd>TodoTelescope<CR>",         { desc = "TODOs" })
    end,
  },

  -- ── Treesitter ───────────────────────────────────────────────────────────
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPre", "BufNewFile" },
    build = ":TSUpdate",
    dependencies = { "windwp/nvim-ts-autotag" },
    config = function()
      require("nvim-treesitter.configs").setup({
        highlight = { enable = true },
        indent    = { enable = true },
        autotag   = { enable = true },
        incremental_selection = {
          enable  = true,
          keymaps = { init_selection = "<C-space>", node_incremental = "<C-space>", node_decremental = "<bs>" },
        },
        ensure_installed = {
          "lua", "vim", "vimdoc", "python", "go", "rust", "c", "bash",
          "javascript", "typescript", "tsx", "json", "yaml", "toml",
          "html", "css", "markdown", "markdown_inline",
          "dockerfile", "gitignore", "svelte", "graphql",
        },
      })
    end,
  },

  -- ── Autopairs ────────────────────────────────────────────────────────────
  {
    "windwp/nvim-autopairs",
    event = "InsertEnter",
    dependencies = { "hrsh7th/nvim-cmp" },
    config = function()
      require("nvim-autopairs").setup({ check_ts = true })
      require("cmp").event:on("confirm_done", require("nvim-autopairs.completion.cmp").on_confirm_done())
    end,
  },

  -- ── Surround / Substitute ────────────────────────────────────────────────
  { "kylechui/nvim-surround", event = { "BufReadPre", "BufNewFile" }, version = "*", config = true },
  {
    "gbprod/substitute.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local sub = require("substitute")
      sub.setup()
      vim.keymap.set("n", "s",  sub.operator, { desc = "Substitute" })
      vim.keymap.set("n", "ss", sub.line,     { desc = "Substitute line" })
      vim.keymap.set("n", "S",  sub.eol,      { desc = "Substitute EOL" })
      vim.keymap.set("x", "s",  sub.visual,   { desc = "Substitute visual" })
    end,
  },

  -- ── Comments ─────────────────────────────────────────────────────────────
  {
    "numToStr/Comment.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "JoosepAlviste/nvim-ts-context-commentstring" },
    config = function()
      require("Comment").setup({
        pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),
      })
    end,
  },

  -- ── TODO / Trouble ───────────────────────────────────────────────────────
  {
    "folke/todo-comments.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      local tc = require("todo-comments")
      tc.setup()
      vim.keymap.set("n", "]t", tc.jump_next, { desc = "Next TODO" })
      vim.keymap.set("n", "[t", tc.jump_prev, { desc = "Prev TODO" })
    end,
  },
  {
    "folke/trouble.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons", "folke/todo-comments.nvim" },
    opts = { focus = true },
    cmd  = "Trouble",
    keys = {
      { "<leader>xw", "<cmd>Trouble diagnostics toggle<CR>",              desc = "Workspace diag" },
      { "<leader>xd", "<cmd>Trouble diagnostics toggle filter.buf=0<CR>", desc = "Buffer diag" },
      { "<leader>xq", "<cmd>Trouble quickfix toggle<CR>",                 desc = "Quickfix" },
      { "<leader>xt", "<cmd>Trouble todo toggle<CR>",                     desc = "TODOs" },
    },
  },

  -- ── Session ──────────────────────────────────────────────────────────────
  {
    "rmagatti/auto-session",
    config = function()
      require("auto-session").setup({ auto_restore_enabled = false })
      vim.keymap.set("n", "<leader>wr", "<cmd>SessionRestore<CR>", { desc = "Restore session" })
      vim.keymap.set("n", "<leader>ws", "<cmd>SessionSave<CR>",    { desc = "Save session" })
    end,
  },

  -- ── Which-key ────────────────────────────────────────────────────────────
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },
}
