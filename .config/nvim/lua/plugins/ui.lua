return {
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {
      options = {
        theme = "auto",
        globalstatus = false,
      },
      sections = {
        lualine_a = { "mode" },
        lualine_b = { "branch" },
        lualine_c = { 
          { "filename", path = 1 },
          { "diagnostics" }
        },
        lualine_x = { "filetype" },
        lualine_y = { "progress" },
        lualine_z = { "location" }
      },
    },
  },
}