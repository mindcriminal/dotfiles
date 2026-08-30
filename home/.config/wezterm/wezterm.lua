local wezterm = require("wezterm")

local config = wezterm.config_builder()

-- The WSL distribution WezTerm should open into. This is the *registered*
-- name from `wsl -l -q` on the Windows side, which is not always the same as
-- the distro's pretty name (Rocky Linux 10 registers as "rocky10").
local WSL_DISTRO = "rocky10"

-- macOS points and Windows points do not render at the same visual size.
local FONT_SIZE_MACOS = 15.0
local FONT_SIZE_WINDOWS = 12.0

local triple = wezterm.target_triple
local is_windows = triple:find("windows") ~= nil
local is_macos = triple:find("darwin") ~= nil

config.color_scheme = "rose-pine-moon"
config.font = wezterm.font("Hack Nerd Font")
config.font_size = is_windows and FONT_SIZE_WINDOWS or FONT_SIZE_MACOS
config.window_background_opacity = 0.8
config.hide_tab_bar_if_only_one_tab = true
config.window_decorations = "RESIZE"

if is_macos then
	config.macos_window_background_blur = 50
end

if is_windows then
	-- The Windows counterpart of macos_window_background_blur. Acrylic works on
	-- Windows 10 and 11, and needs window_background_opacity < 1.0 to show.
	config.win32_system_backdrop = "Acrylic"

        config.window_background_opacity = 0.88

	-- A new window/tab starts inside WSL, not in PowerShell. This is the whole
	-- reason the Windows-side config exists: on macOS the terminal and the
	-- shell live in the same OS, here they do not.
	config.default_domain = "WSL:" .. WSL_DISTRO
end

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.62

-- get_config_overrides() hands back a copy, so the current value is never the
-- same table we last stored; compare the fields instead of the identity.
local function same_text_hsb(actual, expected)
	if actual == nil or expected == nil then
		return actual == expected
	end
	return actual.hue == expected.hue
		and actual.saturation == expected.saturation
		and actual.brightness == expected.brightness
end

wezterm.on("window-focus-changed", function(window)
	local overrides = window:get_config_overrides() or {}
	local text_hsb, opacity
	if not window:is_focused() then
		text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
		opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
	end

	-- Only write when one of the two values we own actually changes; a redundant
	-- set_config_overrides() call would trigger another config reload.
	if same_text_hsb(overrides.foreground_text_hsb, text_hsb) and overrides.window_background_opacity == opacity then
		return
	end

	overrides.foreground_text_hsb = text_hsb
	overrides.window_background_opacity = opacity
	window:set_config_overrides(overrides)
end)

return config
