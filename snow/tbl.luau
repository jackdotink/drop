export type function partial(tbl: type)
	assert(tbl:is("table"), "partial can only be applied to tables")
	local new = types.newtable()

	for k, v in tbl:properties() do
		local read = assert(v.read, "properties cannot be write-only")
		new:setreadproperty(k, types.optional(read))
	end

	return new
end

local function merge<T>(base: T, override: partial<T>): T
	local result: any = table.clone(base :: any)

	for k, v in override :: { [any]: any } do
		result[k] = v
	end

	return table.freeze(result :: any)
end

export type function omit(tbl: type, key: type)
	assert(tbl:is("table"), "omit can only be applied to tables")
	tbl:setproperty(key)
	return tbl
end

local function omit<T, K>(tbl: T, key: K | ""): omit<T, K>
	local result = table.clone(tbl :: any)
	result[key] = nil
	return table.freeze(result :: any)
end

export type function with(tbl: type, key: type, value: type)
	assert(tbl:is("table"), "with can only be applied to tables")
	local tbl = types.copy(tbl)
	tbl:setreadproperty(key, value)
	return tbl
end

local function with<T, K, V>(tbl: T, key: K | "", value: V): with<T, K, V>
	local result = table.clone(tbl :: any)
	result[key] = value
	return table.freeze(result :: any)
end

local function set<T, K>(tbl: T, key: K & keyof<T>, value: index<T, K>): T
	local result: any = table.clone(tbl :: any)
	result[key] = value
	return table.freeze(result :: any)
end

return {
	merge = merge,
	omit = omit,
	with = with,
	set = set,
}
