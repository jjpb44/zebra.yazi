--- @sync entry
-- zebra.yazi: zebra-stripe rows in the file list.
-- Stock yazi only. No config outside `setup()`.

local M = {
	_base = nil,
	_rows = {},
	_current = {},
	_parent = {},
	_preview = {},
	_dirs = {},
	_enabled = true,
	_on_file = nil,
	_patched = false,
}

local COLOR_KEYS = { bg = true, fg = true }
-- yazi modifier methods take `remove`: :dim() adds, :dim(true) removes — invert.
local MODIFIER_KEYS = {
	bold = true,
	dim = true,
	italic = true,
	underline = true,
	reverse = true,
	crossed_out = true,
	blink = true,
	blink_rapid = true,
}

local function parse_hex(hex, path)
	assert(
		type(hex) == "string" and #hex == 7 and hex:sub(1, 1) == "#",
		"zebra: " .. path .. ' must be "#rrggbb", got ' .. tostring(hex)
	)
	local r = tonumber(hex:sub(2, 3), 16)
	local g = tonumber(hex:sub(4, 5), 16)
	local b = tonumber(hex:sub(6, 7), 16)
	assert(r and g and b, "zebra: " .. path .. " invalid hex " .. tostring(hex))
	return r, g, b
end

local function shift(hex, k)
	local r, g, b = parse_hex(hex, "base")
	if k >= 0 then
		r = math.floor(r + (255 - r) * k + 0.5)
		g = math.floor(g + (255 - g) * k + 0.5)
		b = math.floor(b + (255 - b) * k + 0.5)
	else
		local t = 1 + k
		r = math.floor(r * t + 0.5)
		g = math.floor(g * t + 0.5)
		b = math.floor(b * t + 0.5)
	end
	return string.format("#%02x%02x%02x", r, g, b)
end

-- Minimal theme.toml scanning: raw value of `key = ...` inside `[section]`.
-- Strings and single-line tables only.
local function toml_value(text, section, key)
	local in_sec = false
	for line in text:gmatch("[^\r\n]+") do
		-- strip comments, but never the # of a quoted hex color like "#1a1b26"
		local l = line:gsub("%s#.*$", ""):gsub("^%s*#.*$", "")
		local hdr = l:match("^%s*%[(.+)%]%s*$")
		if hdr then
			in_sec = hdr == section
		elseif in_sec then
			local k, v = l:match("^%s*(%w+)%s*=%s*(.-)%s*$")
			if k == key and v ~= "{" and v ~= "" then
				return v
			end
		end
	end
end

-- Extract a bg hex from a raw toml value: "#hex" or { bg = "#hex", ... }
local function hex_of(v)
	if type(v) ~= "string" then
		return nil
	end
	return v:match('^"(#%x%x%x%x%x%x)"$') or v:match('bg%s*=%s*"(#%x%x%x%x%x%x)"')
end

local function read_file(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local t = f:read("*a")
	f:close()
	return t
end

local function config_dir()
	return os.getenv("YAZI_CONFIG_HOME")
		or os.getenv("XDG_CONFIG_HOME") and os.getenv("XDG_CONFIG_HOME") .. "/yazi"
		or os.getenv("HOME") .. "/.config/yazi"
end

-- Base bg from user config: theme.toml [app] overall wins, else the active
-- flavor's [app] overall. Supports both `use` and dark/light flavor keys.
local function theme_bg()
	local dir = config_dir()
	local user = read_file(dir .. "/theme.toml")
	if not user then
		return nil
	end
	local bg = hex_of(toml_value(user, "app", "overall"))
	if bg then
		return bg
	end
	local use = toml_value(user, "flavor", "use")
	local dark = toml_value(user, "flavor", "dark") or (use and use:match('dark%s*=%s*"(.+)"'))
	local light = toml_value(user, "flavor", "light") or (use and use:match('light%s*=%s*"(.+)"'))
	local name
	if use and not dark and not light then
		name = use:match('^"(.+)"$')
	else
		local is_light = false
		pcall(function()
			is_light = rt.term.light() == true
		end)
		name = (is_light and light or dark) or dark or light
		if type(name) == "string" then
			name = name:match('^"(.+)"$') or name
		end
	end
	if name then
		for _, f in ipairs({ "flavor.toml", "theme.toml" }) do
			local flavor = read_file(dir .. "/flavors/" .. name .. ".yazi/" .. f)
			if flavor then
				return hex_of(toml_value(flavor, "app", "overall"))
			end
		end
	end
	return nil
end

-- Validate an entry fully at setup time; render-time code must never throw.
local function validate(entry, path)
	assert(type(entry) == "table", "zebra: " .. path .. " must be a table")
	if entry.darken ~= nil and entry.lighten ~= nil then
		error("zebra: " .. path .. ": darken and lighten are mutually exclusive")
	end
	for _, k in ipairs({ "darken", "lighten" }) do
		assert(
			entry[k] == nil or (type(entry[k]) == "number" and entry[k] >= 0 and entry[k] <= 1),
			"zebra: " .. path .. "." .. k .. " must be in [0,1]"
		)
	end
	for k, v in pairs(entry) do
		assert(
			COLOR_KEYS[k] or MODIFIER_KEYS[k] or k == "darken" or k == "lighten",
			"zebra: " .. path .. ": unknown field " .. tostring(k)
		)
		if COLOR_KEYS[k] then
			assert(type(v) == "string", "zebra: " .. path .. "." .. k .. " must be a hex string")
		end
	end
end

local function compile(list, path)
	assert(type(list) == "table", "zebra: " .. path .. " must be a list")
	for i, entry in ipairs(list) do
		validate(entry, path .. "[" .. i .. "]")
	end
	return list
end

-- Build a FRESH ui.Style from a validated entry. Never cache across rows.
local function build(entry)
	local s = ui.Style()
	if entry.darken ~= nil and M._base then
		s = s:bg(shift(M._base, -entry.darken))
	elseif entry.lighten ~= nil and M._base then
		s = s:bg(shift(M._base, entry.lighten))
	end
	for k, v in pairs(entry) do
		if COLOR_KEYS[k] or MODIFIER_KEYS[k] then
			s = s[k](s, MODIFIER_KEYS[k] and not v or v)
		end
	end
	return s
end

local function has_relative(list)
	for _, e in ipairs(list) do
		if e.darken ~= nil or e.lighten ~= nil then
			return true
		end
	end
	return false
end

--- Internal: pick stripe style for a file. Honors pane visibility, per-pane
--- lists, rows fallback, and the optional on_file callback.
---@param file userdata
---@return userdata?
local function pane_of(file)
	if file.in_current then
		return "current"
	end
	-- in_preview only marks the cursor-synced row; classify the rest of the
	-- preview pane by matching the file url against the preview folder cwd.
	local pf = cx.active.preview.folder
	if pf then
		local cwd = tostring(pf.cwd) .. "/"
		if tostring(file.url):sub(1, #cwd) == cwd then
			return "preview"
		end
	end
	return "parent"
end

-- Listing directory of a pane (for dirs rules). Nil-safe outside render.
local function dir_of(pane)
	local ok, dir = pcall(function()
		if pane == "current" then
			return tostring(cx.active.current.cwd)
		elseif pane == "preview" then
			local pf = cx.active.preview.folder
			return pf and tostring(pf.cwd)
		else
			local pp = cx.active.parent
			return pp and tostring(pp.cwd)
		end
	end)
	return ok and dir or nil
end

local function expand_home(p)
	if p:sub(1, 2) == "~/" then
		return (os.getenv("HOME") or "") .. p:sub(2)
	end
	return p
end

-- First dirs rule matching a listing dir. A rule matches when the expanded
-- pattern equals the dir, is a path-prefix of it, or matches as a Lua pattern
-- ending on a path boundary. Rule values: false = off, table = overrides.
local function dir_rule(dir)
	for pat, rule in pairs(M._dirs) do
		local p = expand_home(pat)
		if dir == p or dir:sub(1, #p + 1) == p .. "/" then
			return rule
		end
		local _, e = dir:find(p)
		if e and (e >= #dir or dir:sub(e + 1, e + 1) == "/") then
			return rule
		end
	end
end

local function pick(file)
	if not M._enabled then
		return nil
	end
	local pane = pane_of(file)
	local rule = dir_of(pane) and dir_rule(dir_of(pane))
	if rule == false then
		return nil
	end
	if rule and rule.panes and rule.panes[pane] == false then
		return nil
	end
	local list = pane == "current" and "_current" or pane == "preview" and "_preview" or "_parent"
	if type(rule) == "table" and rule[pane] ~= nil and #rule[pane] > 0 then
		list = rule[pane]
	elseif #M[list] == 0 then
		list = M._rows
	else
		list = M[list]
	end
	if #list == 0 then
		return nil
	end
	local default = build(list[(file.idx - 1) % #list + 1])
	if M._on_file then
		return M._on_file(file, default) or default
	end
	return default
end

function M:_patch()
	if self._patched then
		return
	end
	local es = Entity.style
	Entity.style = function(self)
		local s = es(self)
		if self._file.is_hovered then
			return s
		end
		local st = pick(self._file)
		return st and st:patch(s) or s
	end
	local lr = Linemode.redraw
	Linemode.redraw = function(self)
		local line = lr(self)
		if self._file.is_hovered then
			return line
		end
		local st = pick(self._file)
		return st and line:style(st) or line
	end
	self._patched = true
end

-- Toggle persistence: ~/.local/state/yazi/zebra.state, plain key=value lines.
local function state_path()
	local xdg = os.getenv("XDG_STATE_HOME")
	if xdg and xdg ~= "" then
		return xdg .. "/yazi/zebra.state"
	end
	local home = os.getenv("HOME")
	return home and (home .. "/.local/state/yazi/zebra.state") or nil
end

local function state_load()
	local p = state_path()
	if not p then
		return nil
	end
	local f = io.open(p, "r")
	if not f then
		return nil
	end
	local t = {}
	for line in f:lines() do
		local k, v = line:match("^(%w+)=(%w+)$")
		if k then
			t[k] = v == "true"
		end
	end
	f:close()
	return t
end

local function state_save(mod)
	local p = state_path()
	if not p then
		return
	end
	local f = io.open(p, "w")
	if not f then
		return
	end
	f:write(string.format("enabled=%s\n", tostring(mod._enabled)))
	f:close()
end

-- Command entry: `plugin zebra [--sync] toggle` / `plugin zebra [--sync] toggle-pane current|parent|preview`.
-- The command loader runs this file in a fresh sandbox (own _G/package), so it
-- must not mutate module state directly; it publishes over ps and the
-- setup-side subscriber (same Lua state as the render hooks) does the work.
function M:entry(job)
	local a = job.args
	local cmd, arg
	if type(a) == "table" then
		cmd, arg = a[1], a[2]
	else
		cmd, arg = tostring(a or ""):match("^(%S*)%s*(.-)%s*$")
	end
	ps.pub("zebra", { cmd = cmd, arg = arg })
end

---@param opts { base?: string, rows?: table[], current?: table[], parent?: table[], preview?: table[], dirs?: { [string]: boolean|table }, on_file?: fun(file: userdata, default: userdata?): userdata?, persist?: boolean }
function M:setup(opts)
	opts = opts or {}
	assert(opts.base == nil or type(opts.base) == "string", "zebra: base must be a hex string or nil")
	if opts.base then
		parse_hex(opts.base, "base")
	end
	self._base = opts.base or theme_bg()

	self._rows = compile(opts.rows or {}, "rows")
	self._current = compile(opts.current or {}, "current")
	self._parent = compile(opts.parent or {}, "parent")
	self._preview = compile(opts.preview or {}, "preview")

	if opts.dirs ~= nil then
		assert(type(opts.dirs) == "table", "zebra: dirs must be a table")
		for pat, rule in pairs(opts.dirs) do
			assert(type(pat) == "string" and pat ~= "", "zebra: dirs keys must be non-empty path patterns")
			if rule ~= false then
				assert(type(rule) == "table", "zebra: dirs[" .. pat .. "] must be false or a table")
				for _, pane in ipairs({ "current", "parent", "preview" }) do
					if rule[pane] ~= nil then
						compile(rule[pane], "dirs[" .. pat .. "]." .. pane)
					end
				end
			end
		end
	end
	self._dirs = opts.dirs or {}

	assert(opts.on_file == nil or type(opts.on_file) == "function", "zebra: on_file must be a function or nil")
	self._on_file = opts.on_file

	assert(opts.persist == nil or type(opts.persist) == "boolean", "zebra: persist must be a boolean")
	self._persist = opts.persist ~= false
	if self._persist then
		local st = state_load()
		if st then
			if st.enabled ~= nil then
				self._enabled = st.enabled
			end
		end
	end

	if not self._base then
		for _, list in ipairs({ self._rows, self._current, self._parent, self._preview }) do
			if has_relative(list) then
				pcall(ya.notify, {
					title = "zebra",
					content = 'No bg for darken/lighten. Set `base = "#rrggbb"` in setup(), '
						.. "or use a theme/flavor with `[app] overall`.",
					level = "warn",
					timeout = 5,
				})
				break
			end
		end
	end
	self:_patch()

	-- Toggle commands arrive via ps from entry() (command sandbox cannot reach
	-- this module instance directly).
	if not self._subscribed then
		self._subscribed = true
		ps.sub("zebra", function(body)
			self:_command(body and body.cmd or "", body and body.arg)
		end)
	end
end

-- ps.sub callbacks don't schedule a repaint; app:resize forces a full re-layout + row repaint (app:theme alone doesn' repaint rows)
-- command with an unconditional render, and re-applying the current theme is a no-op.
local function repaint()
	pcall(ya.emit, "app:resize", {})
end

function M:_command(cmd, arg)
	if cmd == "toggle" then
		self._enabled = not self._enabled
		if self._persist then
			pcall(state_save, self)
		end
		repaint()
		pcall(ya.notify, {
			title = "zebra",
			content = self._enabled and "stripes on" or "stripes off",
			level = "info",
			timeout = 1,
		})
	else
		pcall(ya.notify, {
			title = "zebra",
			content = "usage: toggle",
			level = "warn",
			timeout = 2,
		})
	end
end

return M
