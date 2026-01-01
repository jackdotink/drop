local function insert<T>(arr: { T }, value: T, index: number): { T }
	local new = table.create(#arr + 1)
	table.move(arr, 1, index - 1, 1, new)
	new[index] = value
	table.move(arr, index, #arr, index + 1, new)
	return table.freeze(new)
end

local function remove<T>(arr: { T }, index: number): { T }
	local new = table.create(#arr - 1)
	table.move(arr, 1, index - 1, 1, new)
	table.move(arr, index + 1, #arr, index, new)
	return table.freeze(new)
end

local function append<T>(arra: { T }, arrb: { T }): { T }
	local new = table.create(#arra + #arrb)
	table.move(arra, 1, #arra, 1, new)
	table.move(arrb, 1, #arrb, #arra + 1, new)
	return table.freeze(new)
end

local function pushfront<T>(arr: { T }, value: T): { T }
	local new = table.create(#arr + 1)
	new[1] = value
	table.move(arr, 1, #arr, 2, new)
	return table.freeze(new)
end

local function pushback<T>(arr: { T }, value: T): { T }
	local new = table.clone(arr)
	table.insert(new, value)
	return table.freeze(new)
end

local function popfront<T>(arr: { T }): ({ T }, T?)
	local new = table.create(#arr - 1)
	table.move(arr, 2, #arr, 1, new)
	return table.freeze(new), arr[1]
end

local function popback<T>(arr: { T }): ({ T }, T?)
	local new = table.clone(arr)
	new[#arr] = nil
	return table.freeze(new), arr[#arr]
end

local function splitl<T>(arr: { T }, index: number): ({ T }, { T })
	local left = table.create(index - 1)
	local right = table.create(#arr - index + 1)

	table.move(arr, 1, index - 1, 1, left)
	table.move(arr, index, #arr, 1, right)

	return table.freeze(left), table.freeze(right)
end

local function splitr<T>(arr: { T }, index: number): ({ T }, { T })
	local left = table.create(index)
	local right = table.create(#arr - index)

	table.move(arr, 1, index, 1, left)
	table.move(arr, index + 1, #arr, 1, right)

	return table.freeze(left), table.freeze(right)
end

return {
	insert = insert,
	remove = remove,
	append = append,
	pushfront = pushfront,
	pushback = pushback,
	popfront = popfront,
	popback = popback,
	splitl = splitl,
	splitr = splitr,
}