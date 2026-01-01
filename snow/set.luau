local function insert<T>(set: { [T]: true }, value: T): { [T]: true }
	local new = table.clone(set)
	new[value] = true
	return table.freeze(new)
end

local function remove<T>(set: { [T]: true }, value: T): { [T]: true }
	local new = table.clone(set)
	new[value] = nil
	return table.freeze(new)
end

local function union<T>(seta: { [T]: true }, setb: { [T]: true }): { [T]: true }
	local new = table.clone(seta)

	for k in setb do
		new[k] = true
	end

	return table.freeze(new)
end

local function intersection<T>(seta: { [T]: true }, setb: { [T]: true }): { [T]: true }
	local new: { [T]: true } = {}

	for k in seta do
		if setb[k] then
			new[k] = true
		end
	end

	return table.freeze(new)
end

local function difference<T>(seta: { [T]: true }, setb: { [T]: true }): { [T]: true }
	local new: { [T]: true } = {}

	for k in seta do
		if not setb[k] then
			new[k] = true
		end
	end

	return table.freeze(new)
end

return {
	insert = insert,
	remove = remove,
	union = union,
	intersection = intersection,
	difference = difference,
}
