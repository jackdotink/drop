--- So you want to learn drop? You're in the right place! This guide will walk
--- you through all features of drop step-by-step, starting with the basics.
--- 
--- If at any point you need help, feel free to either on an issue on the github
--- repository (https://github.com/jackdotink/drop) or join the roblox open
--- source software discord server (https://quenty.org/oss/conduct) and ask in
--- the drop project channel
--- (https://discord.com/channels/385151591524597761/1456337815959769304).
--- 
--- For installation, refer to the README.

--- Drop will be imported using `@drop` throughout this guide, but you should
--- import drop however works best for you.
local drop = require("@drop")

--- The different libraries from snow will be imported using `@snow` throughout
--- this guide. You should import snow however works best for you, or not at
--- all! Snow is recommended, not required.
local tbl = require("@snow/tbl")
local set = require("@snow/set")
local map = require("@snow/map")
local array = require("@snow/array")

--- Snow as a library can also be imported using `@snow`, especially when using
--- wally.
local snow = require("@snow")
