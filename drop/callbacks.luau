local function noop() end

return {
	apierror = noop :: (data: {
		msg: string,
		op: "GetAsync" | "SetAsync" | "UpdateAsync" | "RemoveAsync",
		datastore: DataStore,
		key: string,
		retry: boolean,
	}) -> (),

	externerror = function(err: string)
		warn(debug.traceback(`extern error: {err}`))
	end,

	migrationerror = function(data: {
		migration: (any) -> any,
		store: string,
		key: string,
	})
		local file, line, name = debug.info(data.migration, "sln")
		local name = name or "<anonymous>"
		local str = `migration error in store "{data.store}" for key "{data.key}" at {file}:{line} in function "{name}"`
		warn(debug.traceback(str))
	end,
}