local Players = game:GetService("Players")
local drop = require("@drop")
local tbl = require("@snow/tbl")

--- Schemas define the shape of your data. To create a schema, use
--- `drop.schema`.
--- 
--- The value passed to `drop.schema` is the default value. If a key is loaded
--- and has no data, this default value will be used.
local playerschema = drop.schema({
	coins = 0,
})

--- To make some change to the schema, you use migrations. This can be used to
--- make any changes to the schema, such as adding or removing fields, or
--- changing types.
--- 
--- Migrations are functions that take the old data and return the new data.
--- Data passed into migrations is frozen and cannot be modified directly.
--- Instead, you should create a new table and return that.
--- 
--- Here is an example migration that adds a new field `gems` to the player
--- schema.
local playerschema = drop.migrate(playerschema, function(data)
	return {
		--- keep existing coins
		coins = data.coins,

		--- add new field gems with default value 0
		gems = 0,
	}
end)

--- The recommended pattern is to shadow the variable with a new local variable
--- declaration.
--- 
--- Migrations are what I call "write-only code". Once a migration is written
--- and deployed, it should never be changed or removed. Changing or removing
--- a migration can lead to data loss or inconsistencies, and is generally
--- undefined behavior in drop.

--- It's recommended to use snow to help with table manipulation in migrations.
--- We'll use snow from now on in this guide.
local playerschema = drop.migrate(playerschema, function(data)
	return tbl.merge(data, {
		--- add new field level with default value 1
		level = 1,
	})
end)

--- Migration functions erroring is the worst case scenario for you. Drop will
--- catch your errors and log them, data will fail to load, but data integrity
--- will be preserved.

--- Stores represent a datastore. A store has a name and a schema. Stores are
--- the only way to interact with data in drop.
--- 
--- The store's name is used to identify the store in the datastore. The name
--- should be unique and should not change.
--- 
--- Stores are created with `drop.store`.
local playerstore = drop.store({
	name = "playerdata",
	schema = playerschema,
})

--- Stores only allow string keys. When working with keys that are not strings
--- (like players), it's recommended to convert them to and from strings using
--- simple functions.
local function playerintokey(player: Player): string
	return tostring(player.UserId)
end

local function keyintoplayer(key: string): Player?
	local userid = assert(tonumber(key), "invalid player key: " .. key)
	return Players:GetPlayerByUserId(userid)
end
