-- :checkhealth xcode-colors
local M = {}

local health = vim.health
local h_start = health.start or health.report_start
local h_ok = health.ok or health.report_ok
local h_warn = health.warn or health.report_warn
local h_error = health.error or health.report_error

function M.check()
  h_start('xcode-colors.nvim')

  if vim.fn.has('nvim-0.11') == 1 then
    h_ok('Neovim >= 0.11')
  else
    h_error('Neovim 0.11+ required')
  end

  if pcall(vim.treesitter.language.add, 'swift') then
    h_ok('Swift Treesitter parser installed')
  else
    h_error('Swift Treesitter parser not found')
  end

  if vim.fn.executable('sourcekit-lsp') == 1 then
    h_ok('sourcekit-lsp found on $PATH')
  else
    h_warn('sourcekit-lsp not on $PATH - syntactic colors work, but semantic ones do not')
  end
end

return M
