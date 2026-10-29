data:extend({
    {
        type = "double-setting", name = "companion-mini-drone-speed", setting_type = "runtime-global",
        default_value = 0.5, minimum_value = 0.1, maximum_value = 2, order = "g",
        localised_description = {"settings.companion-mini-drone-speed"}
    },
    {
        type = "int-setting", name = "companion-work-radius", setting_type = "startup",
        default_value = 48, minimum_value = 12, maximum_value = 96, order = "f",
        localised_description = {"settings.companion-work-radius"}
    },
    {
        type = "double-setting",
        name = "companion-crafting-speed",
        setting_type = "startup",
        default_value = 2,
        minimum_value = 0.1,
        order = "e",
        localised_description = {"settings.companion-crafting-speed"}
    },
    {
        type = "bool-setting",
        name = "set-challenge-mode",
        hidden = true, -- Legacy saves use this alias; new games select the mode below.
        setting_type = "startup",
        default_value = false,
        order = "c",
        localised_description = {"settings.set-challenge-mode"}
    },
	{
		type = "bool-setting",
		name = "companion-voice-lines",
		setting_type = "startup",
		default_value = true,
		order = "b",
        localised_description = {"settings.companion-voice-lines"}
	},
    {
        type = "int-setting",
        name = "set-update-interval",
        setting_type = "startup",
        default_value = 5,
        minimum_value = 1,
        maximum_value = 1200,
        order = "d",
        localised_description = {"settings.set-update-interval"}
    },
	{
		type = "int-setting",
		name = "companion-idle-chatter-delay",
		setting_type = "runtime-per-user",
		default_value = 600,
		minimum_value = 5,
		maximum_value = 3141592653589,
		order = "a",
		localised_description = {"settings.companion-idle-chatter-delay"}
	},
    {
        type = "string-setting", name = "companion-humor-style", setting_type = "runtime-per-user",
        default_value = "deadpan", allowed_values = {"deadpan", "unhinged", "roast", "sitcom", "scifi"}, order = "b",
        localised_description = {"settings.companion-humor-style"}
    },
    {
        type = "int-setting",
        name = "set-mode",
        setting_type = "startup",
		default_value = 0,
		minimum_value = 0,
		maximum_value = 3,
		order = "a",
        localised_description = {"settings.set-mode"}
    },
})