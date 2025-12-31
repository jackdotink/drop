# Drop

A datastore library.

## Quick start

Drop has two main types: schemas and stores. Let's make both.

```luau
local drop = require("@drop")

local schema = drop.schema({
	coins = 100,
	items = {} :: { [string]: true },
})

local store = drop.store({
	name = "players",
	schema = schema,
})
```

Let's view jack's data. To view the data of any key, call `drop.viewasync`. This function yields and loads data directly from storage. If the data cannot be loaded for any reason, then this function will error.

```luau
local data = drop.viewasync(store, "jack")
```

Jack purchased a developer product for 1000 coins, so let's give that to him. To update data use `drop.updateasync`. This function yields while it attempts to apply the update directly to storage. If the update fails for any reason, then the function will error. This should be the function you use when you need to know if an update was successful.

```luau
local success = pcall(drop.updateasync, store, "jack", function(data)
	return {
		coins = data.coins + 1000,
		items = data.items,
	}
end)

if success then
	return Enum.ProductPurchaseDecision.PurchaseGranted
else
	return Enum.ProductPurchaseDecision.NotProcessedYet
end
```

> [!TIP]
> `drop.updateasync` implements its own internal retry logic. Don't repeatedly call `drop.updateasync` if it errors.

We don't want to worry about catching errors, and we want updates to apply immediately. That means we're going to need to open a session. To start a session, call `drop.startsession`. This function does not yield, but the session will not be immediately available. To wait for the key's session to be available, call `drop.waitforsession`.

```luau
drop.startsession(store, "jack")
drop.waitforsession(store, "jack")
```

The session has been started, we can now view and update the data in the same way without yielding. Let's make a purchase item function. All updates passed to drop should be atomic and pure. Update functions may be called any number of times. To cancel an update, return `nil`.

```luau
local function purchase(key: string, item: string, cost: number)
	drop.update(store, key, function(data)
		if data.coins >= cost and not data.items[item] then
			local items = table.clone(data.items)
			items[item] = true
			
			return {
				coins = data.coins - cost,
				items = items,
			}
		else
			return nil
		end
	end)
end
```

Updates from `drop.update` apply immediately, but we want to see this data changing. For that, we can make an observer. Observers take functions that get called every time data updates. The data may be the same, or it may be different.

```luau
drop.observe(store, function(key, data)
	print(`{key} has {data.coins} coins!`)
end)
```

Marcus and Jack want to trade items. When an update needs to apply to multiple keys, transactions should be used.

```luau
drop.txasync(function(tx)
	tx(store, "jack", function(data)
		if not data.items["sword"] then
			return nil
		end

		local items = table.clone(data.items)
		items["sword"] = nil
		items["horn"] = true

		return {
			coins = data.coins,
			items = items,
		}
	end)

	tx(store, "marcus", function(data)
		if not data.items["horn"] then
			return nil
		end

		local items = table.clone(data.items)
		items["sword"] = true
		items["horn"] = nil

		return {
			coins = data.coins,
			items = items,
		}
	end)
end)
```

## Help

You can ask questions and talk to maintainers either here on github, or in the [Roblox OSS discord](https://quenty.org/oss/conduct).
