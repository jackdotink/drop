# Drop

Drop is a datastore library with a large number of features in a small api. You should use drop if you want:

- Transactions that atomically update several keys at once.
  - Useful for implementing trading between players in a way that prevents duplication glitches.
- Migrations that safely move between different schema versions.
- Multiple servers to read and write to the same data at the same time.
  - No waiting for locks when joining or teleporting.
- An api built around updates and immutable data.
- Immediate cached updates paired with rollbacks.
- A datastore library built on [ACID](#acid) principles.

You may not want to use drop if you need to store large amounts of data per key. Drop restricts the size of each key's data to 2MB.

## Quick start

Drop has two main types: schemas and stores. Let's make both.

```luau
local drop = require("@drop")
local tbl = require("@snow/tbl")
local set = require("@snow/set")

local schema = drop.schema({
	coins = 0,
	items = {} :: { [string]: true },
})

local store = drop.store({
	name = "playerdata",
	schema = schema,
})

local data = drop.viewasync(store, "marcus")
print(data.coins) --> 0

local data = drop.updateasync(store, "marcus", function(data)
	return tbl.merge(data, {
		coins = data.coins + 10,
	})
end)

print(data.coins) --> 10
```

## Installation

### Roblox model files

Drop can be installed via a Roblox model file. You can find the latest version of drop on the [latest release page](https://github.com/jackdotink/drop/releases/latest). Download the `drop` model file and insert it into your Roblox place.

Snow is the recommended, but not required, library for working with immutable data in conjunction with drop. You can find the latest version of snow at the same place as drop. Download the `snow` model file and insert it into your Roblox place.

### Wally

Drop can be installed via [Wally](https://github.com/UpliftGames/wally). To install drop, add the following dependency to your `wally.toml` file:

```toml
[dependencies]
drop = "jackdotink/drop@1.0.0"
```

Snow is the recommended, but not required, library for working with immutable data in conjunction with drop. To install snow, add the following dependency to your `wally.toml` file:

```toml
[dependencies]
snow = "jackdotink/snow@1.0.0"
```

Then run `wally install` to install the dependency.

## Documentation

Drop's documentation is best viewed within a code editor. Download the repository (`git clone https://github.com/jackdotink/drop.git`) and navigate into the docs folder (`cd drop/docs`) to view the documentation files.
