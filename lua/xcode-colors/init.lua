local M = {}

---@alias XcodeColors.Preset 'xcode27-dark'|'xcode27-light'|'xcode26-dark'|'xcode26-light'

-- Per-role foreground colors (hex strings). Any subset may be overridden; see
-- lua/xcode-colors/palettes/ for the full set a preset fills in.
---@class XcodeColors.Palette
---@field plain? string        Identifiers, params, punctuation, operators
---@field comment? string      Comments and doc markup
---@field keyword? string      Keywords, booleans, self/super
---@field string? string       Strings, characters, regex
---@field number? string       Numeric literals
---@field preprocessor? string #if, attributes (@available, @State, ...)
---@field type_decl? string    Type declarations
---@field member_decl? string  Member declarations (functions, properties, enum cases)
---@field project_type? string Type references defined in the current module
---@field project_member? string Member references defined in the current module
---@field other_type? string   Type references from frameworks/stdlib
---@field other_member? string Member references from frameworks/stdlib

---@class XcodeColors.Config
---@field preset? XcodeColors.Preset Built-in palette preset used as the base
---@field palette? XcodeColors.Palette Per-color overrides layered on the preset
---@field lsp? boolean Enable the sourcekit-lsp semantic-token layer (origin + decl/ref)
---@field sourcekit_client? string LSP client name to treat as sourcekit

---@type XcodeColors.Config
M.defaults = {
  preset = 'xcode27-dark',
  palette = {},
  lsp = true,
  sourcekit_client = 'sourcekit',
}

---@class XcodeColors.Config?
M.config = nil

local HL = {
  plain = 'XcodeColorsPlain',
  comment = 'XcodeColorsComment',
  keyword = 'XcodeColorsKeyword',
  string = 'XcodeColorsString',
  number = 'XcodeColorsNumber',
  preprocessor = 'XcodeColorsPreprocessor',
  type_decl = 'XcodeColorsTypeDecl',
  member_decl = 'XcodeColorsMemberDecl',
  project_type = 'XcodeColorsProjectType',
  project_member = 'XcodeColorsProjectMember',
  other_type = 'XcodeColorsOtherType',
  other_member = 'XcodeColorsOtherMember',
}

local ts_links = {
  ['@keyword'] = 'keyword',
  ['@keyword.function'] = 'keyword',
  ['@keyword.return'] = 'keyword',
  ['@keyword.conditional'] = 'keyword',
  ['@keyword.repeat'] = 'keyword',
  ['@keyword.operator'] = 'keyword',
  ['@keyword.import'] = 'keyword',
  ['@keyword.exception'] = 'keyword',
  ['@keyword.coroutine'] = 'keyword',
  ['@keyword.modifier'] = 'keyword',
  ['@keyword.type'] = 'keyword',
  ['@boolean'] = 'keyword',
  ['@constant.builtin'] = 'keyword',
  ['@variable.builtin'] = 'keyword',

  ['@keyword.directive'] = 'preprocessor',
  ['@keyword.directive.define'] = 'preprocessor',
  ['@attribute'] = 'preprocessor',

  ['@string'] = 'string',
  ['@string.regexp'] = 'string',
  ['@string.escape'] = 'string',
  ['@character'] = 'string',

  ['@number'] = 'number',
  ['@number.float'] = 'number',

  ['@comment'] = 'comment',
  ['@comment.documentation'] = 'comment',

  ['@variable'] = 'plain',
  ['@variable.parameter'] = 'plain',
  ['@punctuation.delimiter'] = 'plain',
  ['@punctuation.bracket'] = 'plain',
  ['@punctuation.special'] = 'plain',
  ['@operator'] = 'plain',
  ['@constant'] = 'plain',
  ['@label'] = 'plain',

  ['@type'] = 'project_type',
  ['@type.builtin'] = 'other_type',
  ['@type.definition'] = 'type_decl',
  ['@variable.member.definition'] = 'member_decl',
  ['@constructor'] = 'project_type',
  ['@variable.member'] = 'project_member',
  ['@property'] = 'project_member',
  ['@function'] = 'member_decl',
  ['@function.call'] = 'project_member',
  ['@function.method'] = 'member_decl',
  ['@function.method.call'] = 'project_member',
  ['@function.macro'] = 'other_member',
}

local TYPE_KINDS = {
  class = true,
  struct = true,
  enum = true,
  ['interface'] = true,
  protocol = true,
  actor = true,
  type = true,
  typeParameter = true,
  namespace = true,
}
local MEMBER_KINDS = {
  method = true,
  ['function'] = true,
  property = true,
  enumMember = true,
  macro = true,
}

local function apply_highlights()
  local palette = M.config.palette
  for role, group in pairs(HL) do
    vim.api.nvim_set_hl(0, group, { fg = palette[role] })
  end
  for capture, role in pairs(ts_links) do
    vim.api.nvim_set_hl(0, capture .. '.swift', { link = HL[role] })
  end
end

local function preset_base(name)
  return require('xcode-colors.palettes')[name]
end
local function preset_names()
  return vim.tbl_keys(require('xcode-colors.palettes'))
end

local function refresh_palette()
  M.config.palette = vim.tbl_deep_extend('force', vim.deepcopy(preset_base(M.config.preset)), M.config.overrides)
  apply_highlights()
end

local function classify_token(type, mods)
  mods = mods or {}
  local is_decl = mods.declaration or mods.definition
  local is_other = mods.defaultLibrary
  if TYPE_KINDS[type] then
    if is_decl then return 'type_decl' end
    return is_other and 'other_type' or 'project_type'
  elseif MEMBER_KINDS[type] then
    if is_decl then return 'member_decl' end
    return is_other and 'other_member' or 'project_member'
  end
  return nil
end

-- Swift models operators (==, +, ..<, ...) as `static func`s, so sourcekit
-- reports them as `type=method`. They carry no identifier characters, which is
-- how we tell them apart from real methods and keep them plain.
local function is_operator_token(buf, token)
  local ok, text = pcall(vim.api.nvim_buf_get_text, buf, token.line, token.start_col, token.line, token.end_col, {})
  if not ok or not text[1] then return false end
  return text[1]:find('[%w_]') == nil
end

-- sourcekit reports the name in `extension Foo` as a plain `class` reference (no
-- declaration modifier). An extension extends the type's definition, so
-- Xcode colors the name as a declaration. Only its syntactic position tells us
-- that, so we ask Treesitter whether the token sits in an extension's name field.
local function is_extension_name(buf, token)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { token.line, token.start_col } })
  if not ok or not node then return false end
  local decl = node
  while decl and decl:type() ~= 'class_declaration' do
    decl = decl:parent()
  end
  if not decl then return false end
  local is_ext = false
  for child in decl:iter_children() do
    if child:type() == 'extension' then
      is_ext = true
      break
    end
  end
  if not is_ext then return false end
  local name = decl:field('name')[1]
  if not name then return false end
  local sr, sc, er, ec = name:range()
  local r, c = token.line, token.start_col
  return (r > sr or (r == sr and c >= sc)) and (r < er or (r == er and c < ec))
end

local function on_token(args)
  if vim.bo[args.buf].filetype ~= 'swift' then return end
  local client = vim.lsp.get_client_by_id(args.data.client_id)
  if not client or client.name ~= M.config.sourcekit_client then return end

  local token = args.data.token
  local role = classify_token(token.type, token.modifiers)
  if not role then return end
  if is_operator_token(args.buf, token) then
    role = 'plain'
  elseif TYPE_KINDS[token.type] and is_extension_name(args.buf, token) then
    role = 'type_decl'
  end
  vim.lsp.semantic_tokens.highlight_token(token, args.buf, args.data.client_id, HL[role], {
    priority = vim.hl.priorities.semantic_tokens + 1,
  })
end

---@param opts? XcodeColors.Config
function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts)
  M.config.overrides = vim.deepcopy(opts.palette or {})

  -- A bad preset in config shouldn't break startup; warn and fall back.
  if not preset_base(M.config.preset) then
    vim.notify(
      ("[xcode-colors] unknown preset %q; using 'xcode27-dark'. Available: %s"):format(
        tostring(M.config.preset),
        table.concat(preset_names(), ', ')
      ),
      vim.log.levels.ERROR
    )
    M.config.preset = 'xcode27-dark'
  end
  refresh_palette()

  vim.api.nvim_create_autocmd('ColorScheme', {
    group = vim.api.nvim_create_augroup('xcode-colors-hl', { clear = true }),
    callback = apply_highlights,
  })

  local lsp_group = vim.api.nvim_create_augroup('xcode-colors-lsp', { clear = true })
  if M.config.lsp then
    vim.api.nvim_create_autocmd('LspTokenUpdate', {
      group = lsp_group,
      callback = on_token,
    })
  end

  vim.api.nvim_create_user_command('XcodeColorsPreset', function(a)
    M.set_preset(a.args)
  end, {
    nargs = 1,
    desc = 'Switch the xcode-colors palette preset',
    complete = function(arg)
      return vim.tbl_filter(function(n)
        return n:find(arg, 1, true) == 1
      end, preset_names())
    end,
  })
end

-- Switch the active preset at runtime, keeping the palette overrides from setup().
---@param name XcodeColors.Preset
function M.set_preset(name)
  if not M.config then
    vim.notify('[xcode-colors] call setup() before switching presets', vim.log.levels.WARN)
    return
  end
  if not preset_base(name) then
    vim.notify(
      ('[xcode-colors] unknown preset %q. Available: %s'):format(tostring(name), table.concat(preset_names(), ', ')),
      vim.log.levels.ERROR
    )
    return
  end
  M.config.preset = name
  refresh_palette()
end

-- Print the sourcekit semantic token under the cursor and how it's colored.
function M.inspect()
  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local tokens = vim.lsp.semantic_tokens.get_at_pos(buf, cursor[1] - 1, cursor[2])
  if not tokens or vim.tbl_isempty(tokens) then
    vim.notify('[xcode-colors] no LSP semantic token under cursor', vim.log.levels.WARN)
    return
  end
  for _, t in ipairs(tokens) do
    local mods = {}
    for name, on in pairs(t.modifiers or {}) do
      if on then mods[#mods + 1] = name end
    end
    vim.notify(
      ('[xcode-colors] type=%s modifiers={%s} -> %s'):format(
        t.type,
        table.concat(mods, ', '),
        classify_token(t.type, t.modifiers) or '(treesitter)'
      ),
      vim.log.levels.INFO
    )
  end
end

return M
