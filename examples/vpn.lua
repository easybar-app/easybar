-- Read-only VPN indicator using the primary-interface tunnel flag from native
-- network events; it does not start or stop the VPN.

local state = {
	vpn_connected = false,
}

local vpn

local COLORS = {
	connected = easybar.theme.ref.accent,
	disconnected = easybar.theme.ref.muted,
}

--- Applies the primary-interface tunnel flag from one native network event.
---@param event table? EasyBar event payload.
local function apply_event(event)
	if event == nil or type(event.network) ~= "table" then
		return
	end

	state.vpn_connected = event.network.primary_interface_is_tunnel == true
end

--- Updates the VPN widget from the latest native network state.
local function render()
	local color = state.vpn_connected and COLORS.connected or COLORS.disconnected

	vpn:set({
		icon = {
			string = state.vpn_connected and "󰦝" or "󰌾",
			color = color,
		},
		label = {
			string = state.vpn_connected and "VPN On" or "VPN Off",
			color = color,
		},
	})
end

vpn = easybar.add(easybar.kind.item, "vpn", {
	position = "right",
	order = 41,
})

vpn:subscribe({
	easybar.events.network_change,
	easybar.events.wifi_change,
	easybar.events.system_woke,
	easybar.events.forced,
}, function(event)
	apply_event(event)
	render()
end)

render()
