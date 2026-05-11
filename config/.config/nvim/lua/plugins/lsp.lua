-- lua/plugins/lsp.lua — LSP, Mason, completion, formatting, linting
return {
  -- ── Mason (LSP installer) ──────────────────────────────────────────────────
  {
    "williamboman/mason.nvim",
    cmd = "Mason",
    opts = {},
  },

  -- ── LSP config ─────────────────────────────────────────────────────────────
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason-lspconfig.nvim",
      "hrsh7th/cmp-nvim-lsp",
      { "antosha417/nvim-lsp-file-operations", config = true },
      { "folke/neodev.nvim", opts = {} },
    },
    config = function()
      local lspconfig       = require("lspconfig")
      local mason_lspconfig = require("mason-lspconfig")
      local capabilities    = require("cmp_nvim_lsp").default_capabilities()

      -- Diagnostic signs
      local signs = { Error = " ", Warn = " ", Hint = "󰠠 ", Info = " " }
      for type, icon in pairs(signs) do
        vim.fn.sign_define("DiagnosticSign" .. type, { text = icon, texthl = "DiagnosticSign" .. type })
      end

      -- Keymaps on LSP attach
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("UserLspConfig", {}),
        callback = function(ev)
          local opts = { buffer = ev.buf, silent = true }
          local map  = vim.keymap.set

          opts.desc = "LSP references";       map("n", "gR",          "<cmd>Telescope lsp_references<CR>",      opts)
          opts.desc = "Go to declaration";    map("n", "gD",          vim.lsp.buf.declaration,                  opts)
          opts.desc = "LSP definitions";      map("n", "gd",          "<cmd>Telescope lsp_definitions<CR>",     opts)
          opts.desc = "LSP implementations";  map("n", "gi",          "<cmd>Telescope lsp_implementations<CR>", opts)
          opts.desc = "LSP type defs";        map("n", "gt",          "<cmd>Telescope lsp_type_definitions<CR>",opts)
          opts.desc = "Code actions";         map({"n","v"}, "<leader>ca", vim.lsp.buf.code_action,             opts)
          opts.desc = "Rename";               map("n", "<leader>rn",  vim.lsp.buf.rename,                       opts)
          opts.desc = "Buffer diagnostics";   map("n", "<leader>D",   "<cmd>Telescope diagnostics bufnr=0<CR>", opts)
          opts.desc = "Line diagnostics";     map("n", "<leader>d",   vim.diagnostic.open_float,                opts)
          opts.desc = "Prev diagnostic";      map("n", "[d",          vim.diagnostic.goto_prev,                 opts)
          opts.desc = "Next diagnostic";      map("n", "]d",          vim.diagnostic.goto_next,                 opts)
          opts.desc = "Hover docs";           map("n", "K",           vim.lsp.buf.hover,                        opts)
          opts.desc = "Restart LSP";          map("n", "<leader>rs",  "<cmd>LspRestart<CR>",                    opts)
        end,
      })

      -- Servers to auto-install
      mason_lspconfig.setup({
        ensure_installed = {
          "lua_ls", "pyright", "gopls", "clangd",
          "ts_ls", "rust_analyzer",
          "dockerls", "docker_compose_language_service",
          "html", "cssls", "jsonls", "yamlls",
        },
      })

      mason_lspconfig.setup_handlers({
        function(server_name)
          lspconfig[server_name].setup({ capabilities = capabilities })
        end,
        ["lua_ls"] = function()
          lspconfig.lua_ls.setup({
            capabilities = capabilities,
            settings = { Lua = { diagnostics = { globals = { "vim" } }, completion = { callSnippet = "Replace" } } },
          })
        end,
        ["graphql"] = function()
          lspconfig.graphql.setup({
            capabilities = capabilities,
            filetypes = { "graphql", "gql", "svelte", "typescriptreact", "javascriptreact" },
          })
        end,
        ["emmet_ls"] = function()
          lspconfig.emmet_ls.setup({
            capabilities = capabilities,
            filetypes = { "html", "typescriptreact", "javascriptreact", "css", "sass", "scss", "less", "svelte" },
          })
        end,
      })
    end,
  },

  -- ── Completion ─────────────────────────────────────────────────────────────
  {
    "hrsh7th/nvim-cmp",
    event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      { "L3MON4D3/LuaSnip", version = "v2.*", build = "make install_jsregexp" },
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
      "onsails/lspkind.nvim",
    },
    config = function()
      local cmp     = require("cmp")
      local luasnip = require("luasnip")
      local lspkind = require("lspkind")
      require("luasnip.loaders.from_vscode").lazy_load()

      cmp.setup({
        completion = { completeopt = "menu,menuone,preview,noselect" },
        snippet    = { expand = function(args) luasnip.lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ["<C-k>"]     = cmp.mapping.select_prev_item(),
          ["<C-j>"]     = cmp.mapping.select_next_item(),
          ["<C-b>"]     = cmp.mapping.scroll_docs(-4),
          ["<C-f>"]     = cmp.mapping.scroll_docs(4),
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<C-e>"]     = cmp.mapping.abort(),
          ["<CR>"]      = cmp.mapping.confirm({ select = false }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
        formatting = {
          format = lspkind.cmp_format({ maxwidth = 50, ellipsis_char = "..." }),
        },
      })
    end,
  },

  -- ── Formatting ─────────────────────────────────────────────────────────────
  {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local conform = require("conform")
      conform.setup({
        formatters_by_ft = {
          lua              = { "stylua" },
          python           = { "isort", "black" },
          go               = { "gofmt" },
          javascript       = { "prettier" },
          typescript       = { "prettier" },
          javascriptreact  = { "prettier" },
          typescriptreact  = { "prettier" },
          svelte           = { "prettier" },
          css              = { "prettier" },
          html             = { "prettier" },
          json             = { "prettier" },
          yaml             = { "prettier" },
          markdown         = { "prettier" },
          graphql          = { "prettier" },
          dockerfile       = { "hadolint" },
        },
        format_on_save = { lsp_fallback = true, async = false, timeout_ms = 1000 },
      })
      vim.keymap.set({ "n", "v" }, "<leader>mp", function()
        conform.format({ lsp_fallback = true, async = false, timeout_ms = 1000 })
      end, { desc = "Format file/range" })
    end,
  },

  -- ── Linting ────────────────────────────────────────────────────────────────
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        javascript      = { "eslint_d" },
        typescript      = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescriptreact = { "eslint_d" },
        svelte          = { "eslint_d" },
        python          = { "pylint" },
        dockerfile      = { "hadolint" },
      }
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group    = vim.api.nvim_create_augroup("lint", { clear = true }),
        callback = function() lint.try_lint() end,
      })
      vim.keymap.set("n", "<leader>l", function() lint.try_lint() end, { desc = "Lint current file" })
    end,
  },

  -- ── LSP progress UI ───────────────────────────────────────────────────────
  { "j-hui/fidget.nvim", opts = {} },
}
