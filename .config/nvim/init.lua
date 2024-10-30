-- ==================================================================
-- ========================== LAZY INSTALL ==========================
-- ==================================================================

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
    vim.fn.system({
        "git",
        "clone",
        "--filter=blob:none",
        "https://github.com/folke/lazy.nvim.git",
        "--branch=stable", -- latest stable release
        lazypath,
    })
end
vim.opt.rtp:prepend(lazypath)
vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

-- ==================================================================
-- ========================== LAZY PLUGINS ==========================
-- ==================================================================

local myLazyPlugins = {

    -- === Tools ===
    'tpope/vim-fugitive', -- Git wrapper (use git inside nvim) 
    'akinsho/toggleterm.nvim', -- Terminal
    {
        "folke/trouble.nvim", -- A pretty diagnostics list for Neovim
        config = function()
            require("trouble").setup{}
        end
    },
    {
        'numToStr/Comment.nvim',
        config = function()
            require('Comment').setup()
        end
    },
    {
        "folke/todo-comments.nvim",
        dependencies = "nvim-lua/plenary.nvim",
    },
    {
        "j-hui/fidget.nvim",
        tag = "legacy",
        event = "LspAttach",
        opts = {
        },
    },

    {
        "https://git.sr.ht/~whynothugo/lsp_lines.nvim",

    },
    {
        "folke/tokyonight.nvim",
        lazy = false,
        priority = 1000,
        opts = {},
    },


    -- === Code Completion/Helpers 
    'github/copilot.vim', -- Copilot for Neovim
    'HallerPatrick/py_lsp.nvim', -- Python LSP - activate virtualenv for code completion

    -- === Code Formatting
    'rhysd/vim-clang-format', -- Clang Format
    'tell-k/vim-autopep8', -- Autopep8
    'lukas-reineke/lsp-format.nvim', -- LSP Formatter
    {
        'neovim/nvim-lspconfig', -- Collection of configurations for built-in LSP client
        dependencies = {
            'williamboman/mason.nvim', -- Mason is a build tool for Neovim plugins
            'williamboman/mason-lspconfig.nvim', -- Mason is a build tool for Neovim plugins
            'j-hui/fidget.nvim',    -- A minimal, distraction-free statusline for Neovim
            'folke/neodev.nvim',    -- Neovim development environment
        },
    },
    { 
        'hrsh7th/nvim-cmp',
        dependencies = { 
                            'hrsh7th/cmp-nvim-lsp', 
                            'L3MON4D3/LuaSnip', 
                            'saadparwaiz1/cmp_luasnip' 
                        },
    },
    -- 'preservim/tagbar', -- Tagbar
    {
        'stevearc/aerial.nvim',
            dependencies = {
                "nvim-treesitter/nvim-treesitter",
                "nvim-tree/nvim-web-devicons"
            },
    },

    -- === Projects
    'wakatime/vim-wakatime',

    -- === Look and Feel 
    'nanozuki/tabby.nvim', -- Tabline
    'rcarriga/nvim-notify', -- Neovim Notifications
    'goolord/alpha-nvim', -- Start Screen for Neovim
    'nvim-lualine/lualine.nvim', -- A blazing fast and easy to configure neovim statusline plugin written in pure lua
    'olimorris/onedarkpro.nvim', -- Neovim Theme onedarkpro
    { "lukas-reineke/indent-blankline.nvim", main = "ibl", opts = {} }, -- Indentation guides
    'lewis6991/gitsigns.nvim', -- Git signs
    'NvChad/nvim-colorizer.lua', -- Colorizer for html
    {'folke/noice.nvim',
        dependencies = {
            'MunifTanjim/nui.nvim',
            'rcarriga/nvim-notify', 
        },
    },
    'godlygeek/tabular', -- Tabularize
    'preservim/vim-markdown', -- Markdown
    'nacro90/numb.nvim',
    -- === File Explorer
    {
        'nvim-telescope/telescope.nvim',
        branch = '0.1.x', 
        dependencies = { 'nvim-lua/plenary.nvim' } 
    },
    { 
        'nvim-telescope/telescope-fzf-native.nvim', 
        build = 'make',
    },
    'nvim-telescope/telescope-project.nvim', -- Telescope Project, It's a Telescope extension to help you manage your projects
    "nvim-telescope/telescope-file-browser.nvim",
    {
        "nvim-neo-tree/neo-tree.nvim", -- A file explorer tree for neovim written in lua
        branch = "v2.x",
        dependencies = {
            "nvim-lua/plenary.nvim",
            "nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
            "MunifTanjim/nui.nvim", -- Window management
        },
    },
    { -- Highlight, edit, and navigate code
        'nvim-treesitter/nvim-treesitter', -- Highlighting
        build = function()  pcall(require('nvim-treesitter.install').update) end,
       dependencies = {'nvim-treesitter/nvim-treesitter-textobjects'},
    },
    {'nvim-treesitter/nvim-treesitter-context',
        dependencies = {'nvim-treesitter/nvim-treesitter'},
    },
}

local myLaztOpts = {
    install = {
        missing = true,
            colorscheme = { "onelight" },
    },
    checker = {
        enabled = true,
        concurrency = nil, ---@type number? set to 1 to check for updates very slowly
        notify = true, -- get a notification when new updates are found
        frequency = 43200, -- check for updates every hour
    },
}

require("lazy").setup(myLazyPlugins, myLaztOpts) -- NOTE: Load lazy plugins

-- ===================================================================
-- ===================== NEOVIM THEME SETTINGS =======================
-- ===================================================================
vim.cmd[[colorscheme tokyonight-moon]]

-- ===================================================================
-- ===================== GENERAL SETTINGS ============================
-- ===================================================================

vim.cmd([[autocmd BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | exe "normal! g`\"" | endif]])
vim.o.hlsearch = false
vim.wo.number = true
vim.o.mouse = 'a'
vim.o.breakindent = true
vim.o.undofile = true
vim.o.ignorecase = true -- Ignore case when searching
vim.o.smartcase = true -- Don't ignore case with capitals
vim.wo.signcolumn = 'yes' -- Always show the signcolumn, otherwise it would shift the text each time
vim.wo.relativenumber = true
vim.o.wrap = false
vim.o.tabstop = 4
vim.opt.viminfo:append("!")
vim.o.viewoptions = 'cursor,folds,slash,unix'
vim.o.softtabstop = 0
vim.o.expandtab = true
vim.o.shiftwidth = 4
vim.o.smarttab = true
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true
vim.keymap.set('n', '<S-Tab>', function() vim.cmd('CodeiumCommand') end)
vim.o.showmode = false
vim.opt.scrolloff = 8
vim.o.termguicolors = true
vim.o.completeopt = 'menuone,noselect'
local highlight_group = vim.api.nvim_create_augroup('YankHighlight', { clear = true })
vim.api.nvim_create_autocmd('TextYankPost', {
    callback = function()
        vim.highlight.on_yank()
    end,
    group = highlight_group,
    pattern = '*',
})

-- set <leader> timeout
vim.o.timeoutlen = 200

-- ===================================================================
-- ===================== PLUGINS SETTINGS ============================
-- ===================================================================

require("noice").setup({
    cmdline = {
        enabled = true, -- enables the Noice cmdline UI
        view = "cmdline_popup", -- view for rendering the cmdline. Change to `cmdline` to get a classic cmdline at the bottom
        opts = {}, -- global options for the cmdline. See section on views
    ---@type table<string, CmdlineFormat>
        format = {
        -- conceal: (default=true) This will hide the text in the cmdline that matches the pattern.
        -- view: (default is cmdline view)
        -- opts: any options passed to the view
        -- icon_hl_group: optional hl_group for the icon
        -- title: set to anything or empty string to hide
        cmdline = { pattern = "^:", icon = "", lang = "vim" },
        search_down = { kind = "search", pattern = "^/", icon = " ", lang = "regex" },
        search_up = { kind = "search", pattern = "^%?", icon = " ", lang = "regex" },
        filter = { pattern = "^:%s*!", icon = "$", lang = "bash" },
        lua = { pattern = "^:%s*lua%s+", icon = "", lang = "lua" },
        help = { pattern = "^:%s*he?l?p?%s+", icon = "" },
        input = {}, -- Used by input()
        -- lua = false, -- to disable a format, set to `false`
        },
    },
    messages = {
        -- NOTE: If you enable messages, then the cmdline is enabled automatically.
        -- This is a current Neovim limitation.
        enabled = true, -- enables the Noice messages UI
        view = "notify", -- default view for messages
        view_error = "notify", -- view for errors
        view_warn = "notify", -- view for warnings
        view_history = "messages", -- view for :messages
        view_search = "virtualtext", -- view for search count messages. Set to `false` to disable
    },
    popupmenu = {
        enabled = true, -- enables the Noice popupmenu UI
        ---@type 'nui'|'cmp'
        backend = "nui", -- backend to use to show regular cmdline completions
        ---@type NoicePopupmenuItemKind|false
        -- Icons for completion item kinds (see defaults at noice.config.icons.kinds)
        kind_icons = {}, -- set to `false` to disable icons
    },
    -- default options for require('noice').redirect
    -- see the section on Command Redirection
    ---@type NoiceRouteConfig
    redirect = {
        view = "popup",
        filter = { event = "msg_show" },
    },
    -- You can add any custom commands below that will be available with `:Noice command`
    ---@type table<string, NoiceCommand>
    commands = {
        history = {
        -- options for the message history that you get with `:Noice`
        view = "split",
        opts = { enter = true, format = "details" },
        filter = {
            any = {
                { event = "notify" },
                { error = true },
                { warning = true },
                { event = "msg_show", kind = { "" } },
                { event = "lsp", kind = "message" },
            },
        },
    },
    -- :Noice last
    last = {
        view = "popup",
        opts = { enter = true, format = "details" },
        filter = {
            any = {
            { event = "notify" },
            { error = true },
            { warning = true },
            { event = "msg_show", kind = { "" } },
            { event = "lsp", kind = "message" },
            },
        },
        filter_opts = { count = 1 },
    },
    -- :Noice errors
    errors = {
        -- options for the message history that you get with `:Noice`
        view = "popup",
        opts = { enter = true, format = "details" },
        filter = { error = true },
        filter_opts = { reverse = true },
        },
    },
    notify = {
        -- Noice can be used as `vim.notify` so you can route any notification like other messages
        -- Notification messages have their level and other properties set.
        -- event is always "notify" and kind can be any log level as a string
        -- The default routes will forward notifications to nvim-notify
        -- Benefit of using Noice for this is the routing and consistent history view
        enabled = true,
        view = "notify",
    },
    lsp = {
        progress = {
            enabled = true,
            -- Lsp Progress is formatted using the builtins for lsp_progress. See config.format.builtin
            -- See the section on formatting for more details on how to customize.
            --- @type NoiceFormat|string
            format = "lsp_progress",
            --- @type NoiceFormat|string
            format_done = "lsp_progress_done",
            throttle = 1000 / 20, -- frequency to update lsp progress message
            view = "mini",
            },
        override = {
            -- override the default lsp markdown formatter with Noice
            ["vim.lsp.util.convert_input_to_markdown_lines"] = false,
            -- override the lsp markdown formatter with Noice
            ["vim.lsp.util.stylize_markdown"] = false,
            -- override cmp documentation with Noice (needs the other options to work)
            ["cmp.entry.get_documentation"] = false,
        },
    hover = {
        enabled = true,
        view = nil, -- when nil, use defaults from documentation
        ---@type NoiceViewOptions
        opts = {}, -- merged with defaults from documentation
    },
    signature = {
      enabled = true,
      auto_open = {
        enabled = true,
        trigger = true, -- Automatically show signature help when typing a trigger character from the LSP
        luasnip = true, -- Will open signature help when jumping to Luasnip insert nodes
        throttle = 50, -- Debounce lsp signature help request by 50ms
      },
      view = nil, -- when nil, use defaults from documentation
      ---@type NoiceViewOptions
      opts = {}, -- merged with defaults from documentation
    },
    message = {
      -- Messages shown by lsp servers
      enabled = true,
      view = "notify",
      opts = {},
    },
    -- defaults for hover and signature help
    documentation = {
      view = "hover",
      ---@type NoiceViewOptions
      opts = {
        lang = "markdown",
        replace = true,
        render = "plain",
        format = { "{message}" },
        win_options = { concealcursor = "n", conceallevel = 3 },
      },
    },
  },
  markdown = {
    hover = {
      ["|(%S-)|"] = vim.cmd.help, -- vim help links
      ["%[.-%]%((%S-)%)"] = require("noice.util").open, -- markdown links
    },
    highlights = {
      ["|%S-|"] = "@text.reference",
      ["@%S+"] = "@parameter",
      ["^%s*(Parameters:)"] = "@text.title",
      ["^%s*(Return:)"] = "@text.title",
      ["^%s*(See also:)"] = "@text.title",
      ["{%S-}"] = "@parameter",
    },
  },
  health = {
    checker = true, -- Disable if you don't want health checks to run
  },
  smart_move = {
    enabled = true, -- you can disable this behaviour here
    excluded_filetypes = { "cmp_menu", "cmp_docs", "notify" },
  },
  throttle = 1000 / 20, -- how frequently does Noice need to check for ui updates? This has no effect when in blocking mode.
})

-- Notify
local notify = require "notify"
notify.setup{
    stages = "static",
    render = "compact"
}
vim.notify = notify
-- set the duration of the notification




-- NvimTree
require("toggleterm").setup({
    dir = "git_dir",
})


-- Startup Screen
require'telescope'.load_extension('project')

local status_ok, alpha = pcall(require, "alpha")
if not status_ok then
   return
end
local dashboard = require("alpha.themes.dashboard")
dashboard.section.header.val = {
   [[                               __                ]],
   [[  ___     ___    ___   __  __ /\_\    ___ ___    ]],
   [[ / _ `\  / __`\ / __`\/\ \/\ \\/\ \  / __` __`\  ]],
   [[/\ \/\ \/\  __//\ \_\ \ \ \_/ |\ \ \/\ \/\ \/\ \ ]],
   [[\ \_\ \_\ \____\ \____/\ \___/  \ \_\ \_\ \_\ \_\]],
   [[ \/_/\/_/\/____/\/___/  \/__/    \/_/\/_/\/_/\/_/]],
}
dashboard.section.buttons.val = {
   dashboard.button("<C-P>", "󰱼  Find file", ":Telescope find_files <CR>"),
   dashboard.button("e", "  New file", ":ene <BAR> startinsert <CR>"),
   dashboard.button("p", "  Find project", ":Telescope project <CR>"),
   dashboard.button("r", "  Recently used files", ":Telescope oldfiles <CR>"),
   dashboard.button("<CS-F>", "󱘢  Find text", ":Telescope live_grep <CR>"),
   dashboard.button("c", "  Configuration", ":e ~/.config/nvim/init.lua <CR>"),
   dashboard.button("q", "  Quit Neovim", ":qa<CR>"),
}


local function footer()
   return "satyvm"
end

dashboard.section.footer.val = footer()
dashboard.section.footer.opts.hl = "Type"
dashboard.section.header.opts.hl = "Include"
dashboard.section.buttons.opts.hl = "Keyword"
dashboard.opts.opts.noautocmd = true
vim.cmd([[autocmd User AlphaReady echo 'ready']])
alpha.setup(dashboard.opts)

-- ======= Comment ========
require('Comment').setup()

-- ======= TODO Comment ==

local function excludeGitSubmodules()
    local excludedDirs = {}
    local gitSubmodules = vim.fn.systemlist("grep path .gitmodules | sed 's/.*= //'")
    table.insert(excludedDirs, "--color=never")
    table.insert(excludedDirs, "--no-heading")
    table.insert(excludedDirs, "--with-filename")
    table.insert(excludedDirs, "--line-number")
    table.insert(excludedDirs, "--column")
    for _, dir in ipairs(gitSubmodules) do
        table.insert(excludedDirs, "--glob=!" .. dir .. "/*")
    end
    return excludedDirs
end

require("todo-comments").setup{
    signs = true, -- show icons in the signs column 
    sign_priority = 8, -- sign priority
    highlight = {
        multiline = false,
        pattern = [[.*<(KEYWORDS)\s*:]],
            
    },
    colors = {
        neimogFIX = { "neimogFIX", "#DB463B" },
        neimogERROR = { "neimogERROR", "#DB463B" },
        neimogTODO = { "neimogTODO", "#2196F3" },
        neimogWARN = { "neimogWARN", "#FFA500" },
        neimogPERF = { "neimogPERF", "#F9D0C4" },
        neimogNOTE = { "neimogNOTE", "#d6c306" },
        neimogTEST = { "neimogTEST", "#43A047" },
        neimogDOC = { "neimogDOC", "#F9D0C4" },
    },
    search = {
        command = "rg",
        args = excludeGitSubmodules(),
        pattern = [[\b(KEYWORDS):]],
    },
    keywords = {
        FIX = {icon = " ", color = "neimogFIX", alt = { "FIXME", "BUG", "FIXIT", "ISSUE" }},
        TODO = { icon = " ", color = "neimogTODO", alt = { "TODO", "TO-DO"}},
        ERROR = { icon = " ", color = "neimogERROR", alt = { "HACK", "TEMP", "TEMPORARY" } },
        WARN = { icon = " ", color = "neimogWARN", alt = { "WARNING", "WARN"}}, 
        NOTE = { icon = "󱓧 ", color = "neimogNOTE", alt = { "INFO", "NOTE"} },
        TEST = { icon = "󰙨 ", color = "neimogTEST", alt = { "TESTING", "PASSED", "FAILED" } },
        DOC = { icon = "󱪝 ", color = "hint", alt = { "DOCUMENTATION", "DOC" } },
    },
}

-- ============ wakatime ==============



-- create one nvim lua command where when I write ":ProjectTodo" it run this command :TodoTelescope keywords=TODO,FIX,BUG,HACK,WARN
-- Exclude the git submodules
vim.cmd [[command! ProjectTodo TodoTelescope keywords=TODO,FIX,BUG,HACK,WARN exclude=gitsigns://]]

-- remove neovim TODO highlight
vim.cmd [[highlight clear TODO]]

-- ======= IndentLine ====
vim.cmd [[highlight IndentBlanklineContextChar guifg=#BCBCBC gui=nocombine]]

require('indent_blankline').setup {
    char = '▏',
    space_char_blankline = " ",
    show_current_context = true,
}
-- ======= Git ============
require('gitsigns').setup {
  signs = {
    add = { text = '+' },
    change = { text = '~' },
    delete = { text = '_' },
    topdelete = { text = '‾' },
    changedelete = { text = '~' },
  },
}

-- ========================
-- ======= Telescope ======
-- ========================

-- Fuzzy finder
require("telescope").setup {
  extensions = {
    fzf = {
      fuzzy = true,                 
      override_generic_sorter = true,
      override_file_sorter = true,   
      case_mode = "smart_case",       
    },
    file_browser = {
        theme = "ivy",
        hidden = true,
        dir_icon = "",
        git_status = true,
        use_fd = true,
        hijack_netrw = true,
        mappings = {
            ["i"] = {
                vim.keymap.set('i', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' }),
                vim.keymap.set('i', '<leader>SF', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' }),
                -- use :q to exit from file_browser
                vim.keymap.set('i', ':q', '<Esc>', {noremap = true, silent = true}),
                vim.keymap.set('i', '<leader>sg', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' }),
                vim.keymap.set('i', '<leader>SG', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' })
            },
            ["n"] = {
                vim.keymap.set('n', '<leader>sg', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' }),
                vim.keymap.set('n', '<leader>SG', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' })
            },
    	},
	},
    project = {
        base_dirs = {
            '~/Documents/Git',
        },
        hidden_files = true, -- default: false
        theme = "dropdown",
        order_by = "asc",
        search_by = "title",
        sync_with_nvim_tree = true, -- default false
    }
  },
}

require("telescope").load_extension('file_browser')
require'telescope'.load_extension('project')
require('telescope').load_extension('fzf')

vim.keymap.set("n", "<leader>F", "<cmd>Telescope file_browser<cr>", { noremap = true, silent = true })

-- ====== Treesitter ======
require('nvim-treesitter.configs').setup {
  ensure_installed = { 'c', 'cpp', 'commonlisp', 'python', 'javascript', 'make', 'html', 'lua'},
  highlight = { enable = true },
  indent = { 
        enable = true, 
        disable = { 'python' } 
    }, -- disable python indent is needed for python indentation to work
  incremental_selection = {
    enable = true,
  },
}

require('treesitter-context').setup{
  enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
  max_lines = 0, -- How many lines the window should span. Values <= 0 mean no limit.
  min_window_height = 0, -- Minimum editor window height to enable context. Values <= 0 mean no limit.
  line_numbers = true,
  multiline_threshold = 20, -- Maximum number of lines to collapse for a single context line
  trim_scope = 'outer', -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
  mode = 'cursor',  -- Line used to calculate context. Choices: 'cursor', 'topline'
  separator = nil,
  zindex = 20, -- The Z-index of the context window
  on_attach = nil, -- (fun(buf: integer): boolean) return false to disable attaching
}

-- ====== LSP Server ======
local servers = {
    clangd = {},
    pyright = {},
}

-- ====== Neovim Dev ======
require('neodev').setup() -- 
local capabilities = vim.lsp.protocol.make_client_capabilities() -- 
capabilities = require('cmp_nvim_lsp').default_capabilities(capabilities) -- 

-- ====== Mason ===========
require('mason').setup() -- 
local mason_lspconfig = require 'mason-lspconfig' -- Ensure all servers are installed
mason_lspconfig.setup {ensure_installed = vim.tbl_keys(servers)} -- Setup all servers
mason_lspconfig.setup_handlers {
  function(server_name)
    require('lspconfig')[server_name].setup {
      capabilities = capabilities,
      on_attach = on_attach, --
      settings = servers[server_name],
    }
  end,
}

-- ====== Py Lsp ==========
require'py_lsp'.setup()

local function lsp_provider(component)
    local clients = {}
    local icon = component.icon or ' '
    for _, client in pairs(vim.lsp.buf_get_clients()) do
        if client.name == "pyright" then
          if client.config.settings.python["pythonPath"] ~= nil then
            local VenvName = client.config.settings.python.VenvName
            clients[#clients+1] = icon .. client.name .. '('.. VenvName .. ')'
          end
        else
          clients[#clients+1] = icon .. client.name
        end
    end
    return table.concat(clients, ' ')
end

-- ====== Fidget ==========
require('fidget').setup() -- 
require('gitsigns').setup() --  
require('numb').setup()
require("lsp_lines").setup()

vim.diagnostic.config({
  virtual_text = false,
})

-- ====== CMP =============
local cmp = require 'cmp'
local luasnip = require 'luasnip'
cmp.setup {
    snippet = {
        expand = function(args)
            luasnip.lsp_expand(args.body)
        end,
        },
    sources = {
        { name = 'nvim_lsp' },
        { name = 'buffer' },
    },
    mapping = cmp.mapping.preset.insert({
        ['<CR>'] = cmp.mapping.confirm({ select = true }), 
    }),
}
require'lspconfig'.clangd.setup{}
require("lspconfig").gopls.setup { on_attach = require("lsp-format").on_attach }

-- ============ Lua Line ============
require('lualine').setup({
    options = {
        icons_enabled = true,
        component_separators = { left = '', right = ''},
        section_separators = { left = '', right = ''},
        disabled_filetypes = {
          statusline = {},
          winbar = {},
        },
        ignore_focus = {},
        always_divide_middle = true,
        globalstatus = true,
        refresh = {
          statusline = 1000,
          tabline = 1000,
          winbar = 1000,
        }
    },
    winbar = {
        lualine_a = {'buffers'},
        lualine_b = {},
        lualine_c = {''},
        lualine_x = {},
        lualine_y = {},
        lualine_z = { "os.date('%a')", 'data', "require'lsp-status'.status()" } 
    },
    inactive_winbar = {
        lualine_a = {'buffers'},
        lualine_b = {},
        lualine_x = {},
        lualine_y = {},
        lualine_z = { "os.date('%a')", 'data', "require'lsp-status'.status()" }
    },
    sections = {
        lualine_a = {'mode'},
        lualine_b = {
                        'branch', 
                        {
                            'diff',
                                colored = true, -- Displays a colored diff status if set to true
                                symbols = {added = '+', modified = '~', removed = '-'},
                                diff_color = {
                                    -- Same color values as the general color option can be used here.
                                    added    = 'DiffAdd',    -- Changes the diff's added color
                                    modified = 'DiffChange', -- Changes the diff's modified color
                                    removed  = 'DiffDelete', -- Changes the diff's removed color you
                                },
                        },
                        'diagnostics'},
        lualine_c = {
            {
                'filename',
                file_status = true,      -- Displays file status (readonly status, modified status)
                newfile_status = false,  -- Display new file status (new file means no write after created)
                path = 1,                -- 0: Just the filename
                                       -- 1: Relative path
                                       -- 2: Absolute path
                                       -- 3: Absolute path, with tilde as the home directory
                                       -- 4: Filename and parent dir, with tilde as the home directory

                shorting_target = 40,    -- Shortens path to leave 40 spaces in the window
                                       -- for other components. (terrible name, any suggestions?)
                symbols = {
                    modified = '[+]',      -- Text to show when the file is modified.
                    readonly = '[-]',      -- Text to show when the file is non-modifiable or readonly.
                    unnamed = '[No Name]', -- Text to show for unnamed buffers.
                    newfile = '[New]',     -- Text to show for newly created file before first write
                }
            }
        },
        lualine_x = {'fileformat', 'filetype'},
        lualine_y = {'progress'},
        lualine_z = {'location'}
    },
})
--
for _, kind in ipairs({ 'Add', 'Change', 'Delete' }) do
    local group = 'Diff' .. kind
    local bg = vim.api.nvim_get_hl_by_name('lualine_b_visual', true)['background']
    if group == 'DiffAdd' then
        color = vim.api.nvim_get_hl_by_name('lualine_a_buffers_active', true)['background']
    elseif group == 'DiffChange' then
        color = '#E1AD0F'
    elseif group == 'DiffDelete' then
        color = '#A90000'
    end
    vim.api.nvim_set_hl(0, group, { fg = color, bg = string.format('#%06X', bg)})
end

-- ===================================
-- =========== AERIAL ================
-- ===================================

-- This get me the functions definitions in current file

require('aerial').setup({
  -- optionally use on_attach to set keymaps when aerial has attached to a buffer
  on_attach = function(bufnr)
    -- Jump forwards/backwards with '{' and '}'
    vim.keymap.set('n', '{', '<cmd>AerialPrev<CR>', {buffer = bufnr})
    vim.keymap.set('n', '}', '<cmd>AerialNext<CR>', {buffer = bufnr})
  end
})
-- You probably also want to set a keymap to toggle aerial
vim.keymap.set('n', '<leader>a', '<cmd>AerialToggle!<CR>')


-- ===================================
-- =========== CONDA ENV =============
-- ===================================
local function GetVenvName() 
    local f = io.open("pyrightconfig.json", "r")
    if f == nil then
        return nil
    end
    local content = f:read("*all")
    f:close()
    local VenvName = string.match(content, '"venv": "(.-)"')
    return VenvName
end

local function activateVenv()
    local VenvName = GetVenvName()
    if VenvName ~= nil then
        -- notify silently
        vim.cmd("PyLspActivateCondaEnv " .. VenvName)
    end
end

local function initPythonFunction()
    vim.notify("Activating virtual enviroment!", "info", {title = "Conda Enviroment", timeout = 1000})
    activateVenv()
end

initPythonFunction()

--
vim.api.nvim_create_user_command("RunPyFile", function()
  local file_path = vim.fn.expand('%:p')
  local filename = vim.fn.expand('%:t')
  local VenvName = GetVenvName()
  if VenvName == nil then
    vim.cmd("!python " .. file_path)
  else
    local miniconda = os.getenv("HOME") .. "/miniconda3/envs/" .. VenvName
    local minicondaPython = miniconda .. "/bin/python" 
    vim.cmd("!" .. minicondaPython .. " " .. file_path) 
  end
end, {})

vim.keymap.set("n", '<leader>pip', function()
  local file_path = vim.fn.expand('%:p')
  local pipPackage = vim.fn.input('Install pip package: ')
  local VenvName = GetVenvName()
  local miniconda = os.getenv("HOME") .. "/miniconda3/envs/" .. VenvName
  local minicondaPython = miniconda .. "/bin/python"
  vim.cmd("!" .. minicondaPython .. " -m pip install " .. pipPackage) 
  print("pip package " .. pipPackage .. " installed")
end, {silent = true, desc='[P]ython Run'})

-- ================================================================
-- ========================= KEY-BINDINGS =========================
-- ================================================================

--  Search for files with Telescope
vim.keymap.set('n', '<leader>sg', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' })
vim.keymap.set('i', '<leader>sg', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' })
vim.keymap.set('n', '<leader>SG', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' })
vim.keymap.set('i', '<leader>SG', require('telescope.builtin').git_files, { desc = '[S]earch Files in [G]it' })

-- search for all files
vim.keymap.set('n', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('i', '<leader>sf', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('n', '<leader>SF', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })
vim.keymap.set('i', '<leader>SF', require('telescope.builtin').find_files, { desc = '[S]earch [F]iles' })

--  Search for words with inside the file with Telescope
vim.keymap.set('n', '<leader>sw', require('telescope.builtin').grep_string, { desc = '[S]earch [W]ords' })
vim.keymap.set('i', '<leader>sw', require('telescope.builtin').grep_string, { desc = '[S]earch [W]ords' })


-- Search for string in the actual file
vim.keymap.set('n', '<leader>ss', require('telescope.builtin').live_grep, { desc = '[S]earch [S]tring' })


--  Search for definitions with Telescope
vim.keymap.set('n', '<leader>sd', function()
  require('telescope.builtin').lsp_definitions({
    file_ignore_patterns = { "%.h$" },
    prompt_title = '[S]earch [D]efinitions',
  })
end, { silent = true })
vim.keymap.set('i', '<leader>sd', function()
  require('telescope.builtin').lsp_definitions({
    file_ignore_patterns = { "%.h$" },
    prompt_title = '[S]earch [D]efinitions',
  })
end, { silent = true })

--  Search for references with Telescope
vim.keymap.set('n', '<leader>sr', require('telescope.builtin').lsp_references, { desc = '[S]earch [R]eferences' })
vim.keymap.set('i', '<leader>sr', require('telescope.builtin').lsp_references, { desc = '[S]earch [R]eferences' })


-- vim.api.nvim_set_keymap('n', '<leader>sq', "<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find({ prompt_title = '[S]earch [F]unctions' })<CR>", { noremap = true, silent = true })
-- vim.api.nvim_set_keymap('n', '<leader>sq', "<cmd>lua require('telescope.builtin').lsp_workspace_symbols({query=vim.call('expand','<cword>')})<CR>", { noremap = true, silent = true })

-- list all function definitions in the current file
vim.keymap.set('n', '<leader>sq', function()
  require('telescope.builtin').current_buffer_fuzzy_find({
        -- find all defitions of functions following the language syntax
        prompt_title = '[S]earch [F]unctions',
        search = vim.fn.expand("<cword>"),
        search_dirs = { vim.fn.expand("%:p:h") },
        file_ignore_patterns = { "%.h$" },
        layout_strategy = 'vertical',
        layout_config = {
            width = 0.5,
            height = 0.5,
            prompt_position = "top",
        },
  })
end, { silent = true })




-- In normal mode use 'm' to go to next buffer
vim.keymap.set('n', 'n', function()
    -- see how much buffers are open
    local buffers = vim.api.nvim_list_bufs()
    if #buffers == 2 then
        vim.notify("Just one buffer open!", "info", {title = "Buffers", timeout = 1500})
        vim.cmd('bnext')
    else
        vim.cmd('bnext')
    end
end, { desc = '[N]ext Buffer' })

-- In normal mode use 'm' to go to previous buffer
vim.keymap.set('n', 'm', function()
    local buffers = vim.api.nvim_list_bufs()
    if #buffers == 2 then
        vim.notify("Just one buffer open!", "info", {title = "Buffers", timeout = 1500})
        vim.cmd('bprevious')
    else
        vim.cmd('bprevious')
    end
end, { desc = '[M]previous Buffer' })

-- ===========================================================
vim.keymap.set('n', '<leader>L', function() 
    -- get, throught LspInfo, is Lsp is active
    local clients = vim.lsp.get_active_clients()
    if #clients == 0 then
        -- if Lsp is not active, activate it
        vim.cmd("LspStart")
        vim.notify("Enabling Lsp", "info", {title = "Lsp", timeout = 1500}) 
    else
        -- if Lsp is active, deactivate it
        vim.cmd("LspStop")
        vim.notify("Lsp Disabled!", "info", {title = "Lsp", timeout = 1500})
    end
end, { desc = '[L]sp [S]tart/Stop' })

vim.keymap.set('i', '<C-c>', '<Esc>"+y', {noremap = true, silent = true})
vim.keymap.set('v', '<C-c>', '"+y', {noremap = true, silent = true})
vim.keymap.set('n', '<C-c>', '"+y', {noremap = true, silent = true})
vim.keymap.set('i', '<C-v>', '<Esc>"+p', {noremap = true, silent = true})
vim.keymap.set('v', '<C-v>', '"+p', {noremap = true, silent = true})
vim.keymap.set('n', '<C-v>', '"+p', {noremap = true, silent = true})
vim.keymap.set('i', '<C-x>', '<Esc>"+d', {noremap = true, silent = true})
vim.keymap.set('v', '<C-x>', '"+d', {noremap = true, silent = true})
vim.keymap.set('n', '<C-x>', '"+d', {noremap = true, silent = true})
vim.keymap.set('i', '<C-s>', '<Esc>:w<CR>', {noremap = true, silent = true})
vim.keymap.set('v', '<C-s>', ':w<CR>', {noremap = true, silent = true})
vim.keymap.set('n', '<C-s>', ':w<CR>', {noremap = true, silent = true})

vim.keymap.set('n', '<leader>T', function()
    -- exclude words :TodoTelescope keywords=TODO,FIX
    vim.cmd('TodoTelescope keywords=TODO,BUG')
end, { desc = '[T]odo Telescope' })

vim.keymap.set('n', '<leader>t', function()
    vim.cmd(':ToggleTerm size=10 direction=float')
end, { desc = 'Toggle [T]erminal' })


-- ============================================
vim.keymap.set('v', '<TAB>', '>gv', {noremap = true, silent = true}) 
vim.keymap.set('v', '<S-TAB>', '<gv', {noremap = true, silent = true})
vim.keymap.set('i', 'jk', '<Esc>', {noremap = true, silent = true})
vim.keymap.set('i', 'JK', '<Esc>', {noremap = true, silent = true})

-- ===================================
vim.keymap.set('n', '<leader>rw', function()
    local word = vim.fn.expand('<cword>')
    local new_word = vim.fn.input('Replace "' .. word .. '" with: ')
    vim.cmd('%s/' .. word .. '/' .. new_word .. '/gc')
end, { desc = '[R]eplace [W]ords in file'})


-- ===================================
-- Create new file
-- ===================================

vim.cmd('command! -nargs=1 CreateNewFile :lua CreateNewFile(<f-args>)')

function CreateNewFile(filename)
    vim.cmd('edit ' .. vim.fn.fnameescape(filename))
end
