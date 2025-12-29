local ok, project = pcall(require, "project_nvim")
if not ok then return end

project.setup({
  patterns = { ".git", "Makefile", "CMakeLists.txt", "*.sln", "package.json", "pyproject.toml" },
  silent_chdir = true,
  scope_chdir = "global",
})

