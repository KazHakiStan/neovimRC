-- indentation from the treesitter tree: lua/kazhakistan/xml_indent.lua
vim.bo.indentexpr = "v:lua.require'kazhakistan.xml_indent'.get(v:lnum)"
