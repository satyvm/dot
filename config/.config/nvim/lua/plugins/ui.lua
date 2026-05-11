-- lua/plugins/ui.lua — colorscheme, statusline, dashboard, UI polish
return {
  -- ── Colorscheme ────────────────────────────────────────────────────────────
  {
    "folke/tokyonight.nvim",
    lazy     = false,
    priority = 1000,
    config = function()
      require("tokyonight").setup({
        style       = "night",
        transparent = false,
        on_colors = function(c)
          c.bg           = "#011628"
          c.bg_dark      = "#011423"
          c.bg_highlight = "#143652"
          c.bg_search    = "#0A64AC"
          c.bg_visual    = "#275378"
          c.fg           = "#CBE0F0"
          c.fg_dark      = "#B4D0E9"
          c.fg_gutter    = "#627E97"
          c.border       = "#547998"
        end,
      })
      vim.cmd.colorscheme("tokyonight")
    end,
  },

  -- ── Statusline ─────────────────────────────────────────────────────────────
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      local lazy_status = require("lazy.status")
      require("lualine").setup({
        options = {
          theme = {
            normal   = { a = { bg = "#65D1FF", fg = "#112638", gui = "bold" }, b = { bg = "#112638", fg = "#c3ccdc" }, c = { bg = "#112638", fg = "#c3ccdc" } },
            insert   = { a = { bg = "#3EFFDC", fg = "#112638", gui = "bold" }, b = { bg = "#112638", fg = "#c3ccdc" }, c = { bg = "#112638", fg = "#c3ccdc" } },
            visual   = { a = { bg = "#FF61EF", fg = "#112638", gui = "bold" }, b = { bg = "#112638", fg = "#c3ccdc" }, c = { bg = "#112638", fg = "#c3ccdc" } },
            command  = { a = { bg = "#FFDA7B", fg = "#112638", gui = "bold" }, b = { bg = "#112638", fg = "#c3ccdc" }, c = { bg = "#112638", fg = "#c3ccdc" } },
            replace  = { a = { bg = "#FF4A4A", fg = "#112638", gui = "bold" }, b = { bg = "#112638", fg = "#c3ccdc" }, c = { bg = "#112638", fg = "#c3ccdc" } },
            inactive = { a = { bg = "#2c3043", fg = "#c3ccdc", gui = "bold" }, b = { bg = "#2c3043", fg = "#c3ccdc" }, c = { bg = "#2c3043", fg = "#c3ccdc" } },
          },
          globalstatus           = true,
          component_separators   = { left = "", right = "" },
          section_separators     = { left = "", right = "" },
        },
        sections = {
          lualine_a = { "mode" },
          lualine_b = { "branch", "diff", "diagnostics" },
          lualine_c = { { "filename", path = 1 } },
          lualine_x = {
            { lazy_status.updates, cond = lazy_status.has_updates, color = { fg = "#ff9e64" } },
            "encoding", "fileformat", "filetype",
          },
          lualine_y = { "progress" },
          lualine_z = { "location" },
        },
      })
    end,
  },

  -- ── Dashboard ──────────────────────────────────────────────────────────────
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    config = function()
      local alpha     = require("alpha")
      local dashboard = require("alpha.themes.dashboard")
      dashboard.section.header.val = {
        "  ███╗   ██╗███████╗ ██████╗ ██╗   ██╗██╗███╗   ███╗ ",
        "  ████╗  ██║██╔════╝██╔═══██╗██║   ██║██║████╗ ████║ ",
        "  ██╔██╗ ██║█████╗  ██║   ██║██║   ██║██║██╔████╔██║ ",
        "  ██║╚██╗██║██╔══╝  ██║   ██║╚██╗ ██╔╝██║██║╚██╔╝██║ ",
        "  ██║ ╚████║███████╗╚██████╔╝ ╚████╔╝ ██║██║ ╚═╝ ██║ ",
        "  ╚═╝  ╚═══╝╚══════╝ ╚═════╝   ╚═══╝  ╚═╝╚═╝     ╚═╝ ",
      }
      dashboard.section.buttons.val = {
        dashboard.button("e",      "  New file",             "<cmd>ene<CR>"),
        dashboard.button("SPC ee", "  File explorer",        "<cmd>NvimTreeToggle<CR>"),
        dashboard.button("SPC ff", "󰱼  Find file",           "<cmd>Telescope find_files<CR>"),
        dashboard.button("SPC fs", "  Find word",            "<cmd>Telescope live_grep<CR>"),
        dashboard.button("SPC wr", "󰁯  Restore session",     "<cmd>SessionRestore<CR>"),
        dashboard.button("q",      "  Quit",                 "<cmd>qa<CR>"),
      }
      alpha.setup(dashboard.opts)
      vim.cmd("autocmd FileType alpha setlocal nofoldenable")
    end,
  },

  -- ── Bufferline (tab bar) ───────────────────────────────────────────────────
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    version = "*",
    opts = { options = { mode = "tabs" } },
  },

  -- ── Indent guides ──────────────────────────────────────────────────────────
  {
    "lukas-reineke/indent-blankline.nvim",
    event = { "BufReadPre", "BufNewFile" },
    main = "ibl",
    opts = { indent = { char = "┊" } },
  },

  -- ── Color highlighting ─────────────────────────────────────────────────────
  { "NvChad/nvim-colorizer.lua", opts = {} },

  -- ── Nicer vim.ui (input / select dialogs) ─────────────────────────────────
  { "stevearc/dressing.nvim", event = "VeryLazy" },

  -- ── Window maximizer ──────────────────────────────────────────────────────
  { "szw/vim-maximizer", keys = { { "<leader>sm", "<cmd>MaximizerToggle<CR>", desc = "Maximize split" } } },
}
