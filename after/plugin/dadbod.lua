-- Optional: define saved connections (you can also add them from DBUI)
-- Format is: name = "dbtype://..."
-- Examples:
-- postgres: postgresql://user:pass@localhost:5432/dbname
-- mysql:    mysql://user:pass@localhost:3306/dbname
-- sqlite:   sqlite:/absolute/path/to/file.db   (or sqlite:relative.db)

vim.g.dbs = vim.g.dbs or {
  -- Example SQLite
  -- localdb = "sqlite:C:/projects/db/local.sqlite",

  -- Example Postgres
  -- pg = "postgresql://postgres:postgres@localhost:5432/postgres",
}

-- Enable dadbod completion via built-in omnifunc for SQL buffers
-- (works even if you don't have nvim-cmp)
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "sql", "mysql", "plsql" },
  callback = function()
    vim.bo.omnifunc = "vim_dadbod_completion#omni"
  end,
})

