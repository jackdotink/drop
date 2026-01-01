local function insert<K, V>(map: { [K]: V }, key: K, value: V): { [K]: V }
	local new = table.clone(map)
	new[key] = value
	return table.freeze(new)
end

local function remove<K, V>(map: { [K]: V }, key: K): { [K]: V }
	local new = table.clone(map)
	new[key] = nil
	return table.freeze(new)
end

local function merge<K, V>(map: { [K]: V }, override: { [K]: V }): { [K]: V }
	local new = table.clone(map)

	for k, v in override do
		new[k] = v
	end

	return table.freeze(new)
end

return {
	insert = insert,
	remove = remove,
	merge = merge,
}
