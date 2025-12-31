local callbacks = require("./callbacks")
local schema = require("./schema")
local rbxapi = require("./rbxapi")
local utils = require("./utils")
local tx = require("./tx")

export type Store<T> = {
	read source: DataStore,
	read schema: schema.Schema<T>,

	read lock: { [string]: { (T) -> T } },

	read session: {
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
	tx: {
		id: string,
		data: any,
	}?,
}

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

		if success and result then
			data = result
		end
	end

	return data
end

--- Notifies all observers of an update to the given key with the provided data.
local function runobservers<T>(store: Store<T>, key: string, data: T)
	for _, observer in store.session.observers do
		task.defer(observer, key, data)
	end
end

--- Refreshes the cached data for a given key, applying any queued updates
--- before notifying observers.
--- 
--- If sync is not active for the given key, this is a no-op.
local function refresh<T>(store: Store<T>, key: string, data: T)
	if not store.session.state[key] then
		return
	end

	if store.lock[key] then
		data = applyqueue(data, store.lock[key])
	end

	if store.session.queue[key] then
		data = applyqueue(data, store.session.queue[key])
	end

	local data = utils.deepfreeze(data)
	store.session.cache[key] = data
	runobservers(store, key, data)
end

--- Waits for a lock to be free for the given key.
local function acquirelockasync<T>(store: Store<T>, key: string)
	while store.lock[key] do
		task.wait()
	end
end

--- Releases a lock for the given key.
local function releaselock<T>(store: Store<T>, key: string)
	store.lock[key] = nil
end

--- Resolves the transaction on the given record, returning the updated record.
--- 
--- If `tx.resolveasync` is unable to resolve the transaction, the original
--- record is returned.
--- 
--- If `tx.resolveasync` is able to resolve the transaction, the record is
--- updated accordingly, and the transaction is adopted.
local function resolvetxasync<T>(store: Store<T>, key: string, record: Record): Record
	local txid = assert(record.tx, "no tx to resolve").id
	local status = tx.resolveasync(txid)

	if status == "committed" then
		acquirelockasync(store, key)
		store.lock[key] = {}

		local success, result: Record = rbxapi.updateasync(store.source, key, function(record: Record): Record?
			local record = unwraprecord(store, record)

			if record.tx and record.tx.id == txid then
				record.data = record.tx.data
				record.tx = nil
				return record
			else
				return nil
			end
		end)

		releaselock(store, key)

		if success then
			task.defer(tx.adoptasync, txid, 1)
			return result
		else
			return record
		end
	elseif status == "aborted" then
		acquirelockasync(store, key)
		store.lock[key] = {}

		local success, result: Record = rbxapi.updateasync(store.source, key, function(record: Record): Record?
			local record = unwraprecord(store, record)

			if record.tx and record.tx.id == txid then
				record.tx = nil
				return record
			else
				return nil
			end
		end)

		releaselock(store, key)

		if success then
			task.defer(tx.adoptasync, txid, 1)
			return result
		else
			return record
		end
	else
		return record
	end
end

--- Flushes the queued updates for a given key to the datastore.
--- 
--- Returns the updated record on success, or nil on failure.
local function flushasync<T>(store: Store<T>, key: string): Record?
	acquirelockasync(store, key)
	local queue = store.session.queue[key]
	store.session.queue[key] = nil
	store.lock[key] = queue

	local success, record: Record = rbxapi.updateasync(store.source, key, function(record: Record?): Record?
		local record = unwraprecord(store, record)
		if record.tx then
			return nil
		end

		local record = migraterecord(store, key, record)
		if record == nil then
			error("migration failed")
		end

		record.data = applyqueue(record.data, queue)
		return record
	end)

	releaselock(store, key)

	if not success or record.tx then
		local newqueue = store.session.queue[key]
		if newqueue then
			table.move(newqueue, 1, #newqueue, #queue + 1, queue)
		end

		store.session.queue[key] = queue
	end

	if not success then
		return nil
	elseif record.tx then
		return resolvetxasync(store, key, record)
	else
		return record
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

	while store.session.state[key] do
		if store.session.state[key] == "starting" then
			local data = readasync(store, key)

			if data then
				store.session.state[key] = "active"
				refresh(store, key, data)
			elseif not store.session.cache[key] then
				refresh(store, key, store.schema.initial)
			end

			for _, thread in store.session.waiting[key] do
				task.defer(thread)
			end

			store.session.waiting[key] = nil
		elseif store.session.queue[key] then
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

		task.wait(store.session.time)
	end 
end

--- Prepares the transaction by applying all update functions in the first
--- phase.
--- 
--- Returns true if all updates were prepared successfully, or false if any
--- update failed to prepare.
local function txprepareasync(fns: { [Store<any>]: { [string]: (any) -> any } }, txid: string): boolean
	local thread: thread? = coroutine.running()
	local total = 0

	for store, keys in fns do
		for key, fn in keys do
			total += 1

			task.defer(function()
				local success, record: Record = rbxapi.updateasync(store.source, key, function(record: Record?): Record?
					local record = unwraprecord(store, record)
					if record.tx then
						return nil
					end
					
					local record = migraterecord(store, key, record)
					if record == nil then
						error("migration failed")
					end

					local success, result = utils.externcall(fn, record.data)
					if not success then
						error("update function errored on txphase1")
					end

					if not result then
						return nil
					end

					record.tx = { id = txid, data = result }
					return record
				end)

				if not success or not record.tx then
					if thread then
						coroutine.resume(thread, false)
					end
				elseif record.tx.id ~= txid then
					task.defer(resolvetxasync, store, key, record)

					if thread then
						coroutine.resume(thread, false)
					end
				elseif  thread then
					refresh(store, key, record.data)
					coroutine.resume(thread, true)
				end
			end)
		end
	end

	local done = 0
	while done < total and coroutine.yield() do
		done += 1
	end

	thread = nil
	return done == total
end

--- Commits the transaction by applying all prepared updates in the second
--- phase.
local function txcommitasync(fns: { [Store<any>]: { [string]: (any) -> any } }, txid: string)
	local thread = coroutine.running()
	local total = 0

	for store, keys in fns do
		for key in keys do
			total += 1

			task.defer(function(store: Store<any>, key: string, txid: string, thread: thread)
				local success, record: Record = rbxapi.updateasync(store.source, key, function(record: Record?): Record?
					local record = unwraprecord(store, record)
					assert(record.tx and record.tx.id == txid, "unreachable")

					record.data = record.tx.data
					record.tx = nil
					return record
				end)

				releaselock(store, key)

				if success then
					refresh(store, key, record.data)
				end
	
				coroutine.resume(thread, success)
			end, store, key, txid, thread)
		end
	end

	local done = 0
	local successful = 0
	while done < total do
		if coroutine.yield() then
			successful += 1
		end

		done += 1
	end

	task.defer(tx.adoptasync, txid, successful)
end

--- Aborts the transaction by reverting all prepared updates in the second
--- phase.
local function txabortasync(fns: { [Store<any>]: { [string]: (any) -> any } }, txid: string)
	local thread = coroutine.running()
	local total = 0

	for store, keys in fns do
		for key in keys do
			total += 1

			task.defer(function(store: Store<any>, key: string, txid: string, thread: thread)
				local success, record: Record = rbxapi.updateasync(store.source, key, function(record: Record?): Record?
					local record = unwraprecord(store, record)

					if record.tx and record.tx.id == txid then
						record.tx = nil
						return record
					else
						return nil
					end
				end)

				releaselock(store, key)

				if success then
					refresh(store, key, record.data)
				end

				coroutine.resume(thread, success)
			end, store, key, txid, thread)
		end
	end

	local done = 0
	local successful = 0
	while done < total do
		if coroutine.yield() then
			successful += 1
		end

		done += 1
	end

	tx.adoptasync(txid, successful)
end

--- Executes phase 2 of the transaction.
--- 
--- This attempts to commit the transaction, and if successful, commits all
--- updates. If the commit fails, it aborts the transaction instead.
local function txphase2(thread: thread, fns: { [Store<any>]: { [string]: (any) -> any } }, txid: string)
	local status = tx.commitasync(txid)

	if status == "committed" then
		txcommitasync(fns, txid)
		task.defer(thread, nil)
	else
		task.defer(txabortasync, fns, txid)
		task.defer(thread, "txphase2 failed to commit")
	end
end

--- Executes phase 1 of the transaction.
--- 
--- This attempts to prepare all updates, and if successful, moves on to phase
--- 2. If any update fails to prepare, it aborts the transaction instead.
local function txphase1(thread: thread, fns: { [Store<any>]: { [string]: (any) -> any } }, txid: string)
	local success = txprepareasync(fns, txid)

	if not success then
		task.defer(txabortasync, fns, txid)
		task.defer(thread, "txphase1 failed to prepare all keys")
	else
		txphase2(thread, fns, txid)
	end
end

--- Executes phase 0 of the transaction.
--- 
--- This acquires all necessary locks and creates the transaction, then moves on
--- to phase 1. If the transaction cannot be created, it releases all locks and
--- aborts.
local function txphase0(thread: thread, fns: { [Store<any>]: { [string]: (any) -> any } })
	local total = 0

	for store, keys in fns do
		for key in keys do
			acquirelockasync(store, key)
			store.lock[key] = {}
			total += 1
		end
	end

	local txid = tx.createasync(total)

	if txid == nil then
		for store, keys in fns do
			for key in keys do
				releaselock(store, key)
			end
		end

		task.defer(thread, "txphase0 failed to create tx")
	else
		txphase1(thread, fns, txid)
	end
end

--- Starts real-time sync for a given key.
local function startsession<T>(store: Store<T>, key: string)
	if store.session.state[key] then
		error(`sync already started for key "{key}"`)
	elseif store.session.queue[key] then
		error(`still stopping sync for key "{key}"`)
	end

	store.session.state[key] = "starting"
	store.session.waiting[key] = {}
	store.session.loop[key] = task.spawn(rtasync, store, key)
end

--- Waits for real-time sync to start for a given key.
local function waitforsession<T>(store: Store<T>, key: string)
	if not store.session.state[key] then
		error(`sync not started for key "{key}"`)
	elseif store.session.state[key] == "active" then
		return
	end

	table.insert(store.session.waiting[key], coroutine.running())
	coroutine.yield()
end

--- Stops real-time sync for a given key.
local function stopsessionasync<T>(store: Store<T>, key: string)
	if not store.session.state[key] then
		error(`sync not started for key "{key}"`)
	end

	store.session.state[key] = nil
	store.session.loop[key] = nil
	store.session.cache[key] = nil

	while store.session.queue[key] do
		flushasync(store, key)
	end
end

--- Views the cached data for a given key.
--- 
--- If sync is not active for the given key, this errors.
local function view<T>(store: Store<T>, key: string): T
	local data = store.session.cache[key]

	if data == nil then
		error(`no cached data for key "{key}"`)
	end

	return data
end

--- Queues an update function for a given key.
--- 
--- If sync is not active for the given key, this errors.
local function update<T>(store: Store<T>, key: string, fn: (T) -> T)
	if not store.session.state[key] then
		error(`sync not started for key "{key}"`)
	end

	local success, result = utils.externcall(fn, store.session.cache[key])
	if not success then
		error("update function errored on cache-apply")
	end

	if store.session.queue[key] then
		table.insert(store.session.queue[key], fn)
	else
		store.session.queue[key] = { fn }
	end

	if result then
		store.session.cache[key] = utils.deepfreeze(result)
		runobservers(store, key, result)
	end
end

--- Observes updates to the store.
--- 
--- The provided function is called with the key and updated data whenever an
--- update occurs. Data might be different or the same as the previous update.
local function observe<T>(store: Store<T>, fn: (key: string, data: T) -> ())
	table.insert(store.session.observers, fn)
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

	refresh(store, key, record.data)

	return record.data
end

--- Updates the data for a given key directly in the datastore.
--- 
--- This bypasses any real-time sync and cache.
--- 
--- This function will error if the update fails.
local function updateasync<T>(store: Store<T>, key: string, fn: (T) -> T): T
	local function apply<T>(store: Store<T>, key: string, fn: (T) -> T): Record?
		acquirelockasync(store, key)
		store.lock[key] = {}

		local success, record: Record = rbxapi.updateasync(store.source, key, function(record: Record?): Record?
			local record = unwraprecord(store, record)
			if record.tx then
				return nil
			end
			
			local record = migraterecord(store, key, record)
			if record == nil then
				error("migration failed")
			end

			local success, result = utils.externcall(fn, record.data)
			if not success then
				error("update function errored on datastore-apply")
			end

			if not result then
				return nil
			end

			record.data = result
			return record
		end)

		releaselock(store, key)
		
		if not success then
			return nil
		else
			refresh(store, key, record.data)
			return record
		end
	end

	local record = apply(store, key, fn)
	if record == nil then
		error("datastore update failed")
	elseif not record.tx then
		return record.data
	end

	local record = resolvetxasync(store, key, record)
	if record.tx then
		error("transaction could not be resolved")
	end

	local record = apply(store, key, fn)
	if record == nil then
		error("datastore update failed")
	elseif record.tx then
		error("transaction could not be resolved")
	else
		return record.data
	end
end

--- Executes a transaction with multiple updates.
--- 
--- The provided function is called with a transaction function that can be
--- used to queue updates on multiple stores and keys. The transaction will
--- attempt to apply all updates atomically, and will error if any update
--- fails.
--- 
--- If the transaction is successful, all updates will be committed. If any
--- update fails, all updates will be reverted.
local function txasync<T>(fn: (tx: <T>(store: Store<T>, key: string, fn: (T) -> T) -> ()) -> ())
	local fns: { [Store<any>]: { [string]: (any) -> any } } = {}

	fn(function(store: Store<T>, key: string, fn: (T) -> T)
		if fns[store] == nil then
			fns[store] = {}
		end

		if fns[store][key] then
			error("cannot put multiple tx updates on the same key")
		end

		fns[store][key] = fn
	end)

	task.defer(txphase0, coroutine.running(), fns)

	local err = coroutine.yield()
	if err then
		error(err)
	end
end

local function create<T>(opts: {
	name: string,
	schema: schema.Schema<T>,
	sessiontime: number?,
}): Store<T>
	local store: Store<T> = {
		source = rbxapi.getdatastore(opts.name),
		schema = opts.schema,

		lock = {},

		session = {
			time = opts.sessiontime or 12,

			state = {},
			waiting = {},
			loop = {},
			cache = {},
			queue = {},
			observers = {},
		},
	}

	game:BindToClose(function()
		for key in store.session.state do
			task.defer(stopsessionasync, store, key)
		end
	end)

	return store
end

return table.freeze({
	create = create,
	startsession = startsession,
	waitforsession = waitforsession,
	stopsessionasync = stopsessionasync,
	view = view,
	update = update,
	observe = observe,
	viewasync = viewasync,
	updateasync = updateasync,
	txasync = txasync,
})
