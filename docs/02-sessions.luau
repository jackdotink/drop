local Players = game:GetService("Players")
local drop = require("@drop")
local tbl = require("@snow/tbl")

local playerschema = drop.schema({
    coins = 0,
})

local playerstore = drop.store({
    name = "playerdata",
    schema = playerschema,
})

local function playerintokey(player: Player): string
    return tostring(player.UserId)
end

local function keyintoplayer(key: string): Player?
    local userid = assert(tonumber(key), "invalid player key: " .. key)
    return Players:GetPlayerByUserId(userid)
end

--- In a single sentence, sessions keep a key's data in sync between the server
--- and the datastore.
--- 
--- Sessions allow you to use non-yielding APIs to read and update data, while
--- drop handles syncing the data to and from the datastore in the background.
--- 
--- Sessions do not lock data to a particular server. Multiple servers can have
--- the same key loaded in sessions at the same time.
--- 
--- Let's create a session for a player when they join the game, and then print
--- the number of coins they have.
Players.PlayerAdded:Connect(function(player)
    --- `drop.startsession` does not yield, but the session is not ready when
    --- it returns.
    drop.startsession(playerstore, playerintokey(player))

    --- Use `drop.waitforsession` to wait until the session is ready.
    --- `drop.waitforsession` can be called multiple times, but
    --- `drop.startsession` can only be called once.
    drop.waitforsession(playerstore, playerintokey(player))

    --- `drop.view` returns the current data for the key. the key must have an
    --- active session. `drop.view` does not yield.
    local data = drop.view(playerstore, playerintokey(player))
    print(data.coins)
end)

--- Sessions cache data in memory to allow for immediate access. This cache is
--- used by `drop.view` and `drop.update`.
--- 
--- `drop.view` was used above to read the player's data. Now let's write a
--- function to give a player coins.
local function givecoins(player: Player, n: number)
    --- `drop.update` takes a function that takes data and returns new data. The
    --- function must be pure (have no side effects) and cannot yield. The data
    --- passed is always deeply frozen and the function may be called any number
    --- of times.
    drop.update(playerstore, playerintokey(player), function(data)
        return tbl.write(data, {
            coins = data.coins + n,
        })
    end)
end

--- This function will give a player coins, but how do we listen to those
--- updates? Or what if another server updates the player's data? For this, drop
--- has observers.
--- 
--- Observers are functions that are called whenever drop thinks that the server
--- should receive new data for a key. The function may even be called when data
--- has not changed, though drop tries to minimize unnecessary calls for good
--- performance.
drop.observe(playerstore, function(key, data)
    local player = keyintoplayer(key)
    if not player then
        return
    end

    print(`{player.Name} has {data.coins} coins!`)
end)

--- Finally, we need to stop the session when the player leaves.
Players.PlayerRemoving:Connect(function(player)
    --- Stopping a session yields, and will not return until all updates have
    --- been flushed to the datastore.
    drop.stopsessionasync(playerstore, playerintokey(player))
end)

--- Remember! Sessions, like everything else in drop, can be used for non-player
--- data as well.
