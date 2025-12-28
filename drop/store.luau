local callbacks = require("./callbacks")
local schema = require("./schema")
local rbxapi = require("./rbxapi")
local utils = require("./utils")

export type Store<T> = {
	read source: DataStore,
	read schema: schema.Schema<T>,

	read lock: { [string]: true },

	read rt: {
		read time: number,

		read state: { [string]: "starting" | "active" },
		read waiting: { [string]: { thread } },
		read loop: { [string]: thread },
		read cache: { [string]: T },
		read queue: { [string]: { (T) -> T } },
		read observers: { (key: string, data: T) -> () },
	},
}

type Record = {
	version: number,
	data: any,
}

local function create<T>(opts: {
	name: string,
	schema: schema.Schema<T>,
	rttime: number?,
}): Store<T>
	return {
		source = rbxapi.getdatastore(opts.name),
		schema = opts.schema,

		lock = {},

		rt = {
			time = opts.rttime or 12,

			state = {},
			waiting = {},
			loop = {},
			cache = {},
			queue = {},
			observers = {},
		},
	}
end

--- Unwraps a record loaded from the datastore, returning an initial record if
--- none exists.
local function unwraprecord<T>(store: Store<T>, record: Record?): Record
	if record == nil then
		return {
			data = store.schema.initial,
			version = #store.schema.migrations,
		}
	end

	return record
end

--- Migrations a record to the latest schema version, returning nil if a 
--- migration failed.
local function migraterecord<T>(store: Store<T>, key: string, record: Record): Record?
	local schema = store.schema
	local data = record.data

	assert(record.version <= #schema.migrations, "unreachable: record version is newer than schema")

	for i = record.version + 1, #schema.migrations do
		local migration = schema.migrations[i]
		local success, result = utils.externcall(migration, data)

		if not success then
			callbacks.migrationerror({
				migration = migration,
				store = store.source.Name,
				key = key,
			})

			return nil
		end

		data = result
	end

	return {
		data = data,
		version = #schema.migrations,
	}
end

--- Applies a queue of functions to the given data.
--- 
--- Each function is called with a deep-frozen copy of the data, and if it
--- returns successfully, the returned value is used as the new data for the
--- next function in the queue.
--- 
--- If a function errors, its result is ignored and the data remains unchanged
--- for the next function.
local function applyqueue<T>(data: T, queue: { (T) -> T }): T
	for _, fn in queue do
		local success, result = utils.externcall(fn, utils.deepfreeze(data))

		if success then
			data = result
		end
	end

	return data
end

--- Notifies all observers of an update to the given key with the provided data.
local function runobservers<T>(store: Store<T>, key: string, data: T)
	for _, observer in store.rt.observers do
		task.defer(observer, key, data)
	end
end

--- Refreshes the cached data for a given key, applying any queued updates
--- before notifying observers.
--- 
--- If sync is not active for the given key, this is a no-op.
local function refresh<T>(store: Store<T>, key: string, data: T)
	if not store.rt.state[key] then
		return
	end

	if store.rt.queue[key] then
		data = applyqueue(data, store.rt.queue[key])
	end

	local data = utils.deepfreeze(data)
	store.rt.cache[key] = data
	runobservers(store, key, data)
end

--- Acquires a lock for the given key, waiting if necessary.
--- 
--- A lock must be acquired before performing any datastore operations on any
--- given key.
local function acquirelockasync<T>(store: Store<T>, key: string)
	while store.lock[key] do
		task.wait()
	end

	store.lock[key] = true
end

--- Releases a lock for the given key.
local function releaselock<T>(store: Store<T>, key: string)
	store.lock[key] = nil
end

--- Flushes the queued updates for a given key to the datastore.
--- 
--- Returns the updated record on success, or nil on failure.
local function flushasync<T>(store: Store<T>, key: string): Record?
	acquirelockasync(store, key)

	local queue = store.rt.queue[key]
	store.rt.queue[key] = nil

	local success, record: Record = rbxapi.updateasync(store.source, key, function(record: Record?): Record?
		local record = unwraprecord(store, record)
		local record = migraterecord(store, key, record)

		if record == nil then
			error("migration failed")
		end

		record.data = applyqueue(record.data, queue)
		return record
	end)

	releaselock(store, key)

	if success then
		return record
	else
		local newqueue = store.rt.queue[key]
		if newqueue then
			table.move(newqueue, 1, #newqueue, #queue + 1, queue)
		end

		store.rt.queue[key] = queue
		return nil
	end
end

--- Real-time sync loop for a given key.
local function rtasync<T>(store: Store<T>, key: string)
	local function readasync<T>(store: Store<T>, key: string): T?
		local success, record: Record = rbxapi.getasync(store.source, key)
		if not success then
			return nil
		end

		local record = unwraprecord(store, record)
		local record = migraterecord(store, key, record)

		if record == nil then
			error("migration failed")
		end

		return record.data
	end

	while store.rt.state[key] do
		if store.rt.state[key] == "starting" then
			local data = readasync(store, key)

			if data then
				store.rt.state[key] = "active"
				refresh(store, key, data)
			elseif not store.rt.cache[key] then
				refresh(store, key, store.schema.initial)
			end

			for _, thread in store.rt.waiting[key] do
				task.defer(thread)
			end

			store.rt.waiting[key] = nil
		elseif store.rt.queue[key] then
			local record = flushasync(store, key)

			if record then
				refresh(store, key, record.data)
			end
		else
			local data = readasync(store, key)

			if data then
				refresh(store, key, data)
			end
		end

		task.wait(store.rt.time)
	end 
end

--- Starts real-time sync for a given key.
local function startrt<T>(store: Store<T>, key: string)
	if store.rt.state[key] then
		error(`sync already started for key "{key}"`)
	elseif store.rt.queue[key] then
		error(`still stopping sync for key "{key}"`)
	end

	store.rt.state[key] = "starting"
	store.rt.waiting[key] = {}
	store.rt.loop[key] = task.spawn(rtasync, store, key)
end

--- Waits for real-time sync to start for a given key.
local function waitforrt<T>(store: Store<T>, key: string)
	if not store.rt.state[key] then
		error(`sync not started for key "{key}"`)
	elseif store.rt.state[key] == "active" then
		return
	end

	table.insert(store.rt.waiting[key], coroutine.running())
	coroutine.yield()
end

--- Stops real-time sync for a given key.
local function stoprtasync<T>(store: Store<T>, key: string)
	if not store.rt.state[key] then
		error(`sync not started for key "{key}"`)
	end

	store.rt.state[key] = nil
	store.rt.loop[key] = nil
	store.rt.cache[key] = nil

	while store.rt.queue[key] do
		flushasync(store, key)
	end
end

--- Views the cached data for a given key.
--- 
--- If sync is not active for the given key, this errors.
local function view<T>(store: Store<T>, key: string): T
	local data = store.rt.cache[key]

	if data == nil then
		error(`no cached data for key "{key}"`)
	end

	return data
end

--- Queues an update function for a given key.
--- 
--- If sync is not active for the given key, this errors.
local function update<T>(store: Store<T>, key: string, fn: (T) -> T)
	if not store.rt.state[key] then
		error(`sync not started for key "{key}"`)
	end

	local success, result = utils.externcall(fn, store.rt.cache[key])
	if not success then
		error("update function errored on cache-apply")
	end

	if store.rt.queue[key] then
		table.insert(store.rt.queue[key], fn)
	else
		store.rt.queue[key] = { fn }
	end

	store.rt.cache[key] = utils.deepfreeze(result)
	runobservers(store, key, result)
end

--- Observes updates to the store.
--- 
--- The provided function is called with the key and updated data whenever an
--- update occurs. Data might be different or the same as the previous update.
local function observe<T>(store: Store<T>, fn: (key: string, data: T) -> ())
	table.insert(store.rt.observers, fn)
end

--- Views the data for a given key directly from the datastore.
--- 
--- This bypasses any real-time sync and cache.
--- 
--- This function will error if the read fails.
local function viewasync<T>(store: Store<T>, key: string): T
	local success, record: Record = rbxapi.getasync(store.source, key)
	if not success then
		error("datastore read failed")
	end

	local record = unwraprecord(store, record)
	local record = migraterecord(store, key, record)

	if record == nil then
		error("migration failed")
	end

	return record.data
end

--- Updates the data for a given key directly in the datastore.
--- 
--- This bypasses any real-time sync and cache.
--- 
--- This function will error if the update fails.
local function updateasync<T>(store: Store<T>, key: string, fn: (T) -> T): T
	acquirelockasync(store, key)

	local success, record: Record = rbxapi.updateasync(store.source, key, function(record: Record?): Record?
		local record = unwraprecord(store, record)
		local record = migraterecord(store, key, record)

		if record == nil then
			error("migration failed")
		end

		local success, result = utils.externcall(fn, record.data)
		if not success then
			error("update function errored on datastore-apply")
		end

		record.data = result
		return record
	end)

	releaselock(store, key)

	if success then
		return record.data
	else
		error("datastore update failed")
	end
end

return {
	create = create,
	startrt = startrt,
	waitforrt = waitforrt,
	stoprtasync = stoprtasync,
	view = view,
	update = update,
	observe = observe,
	viewasync = viewasync,
	updateasync = updateasync,
}
