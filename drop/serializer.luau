--!native
--!optimize 2

export type AnyData = nil | boolean | number | vector | Vector3 | buffer | string | CFrame | Color3 | DateTime | { [AnyData]: AnyData }

local defaultbuffersize = 5_242_880
local currentversion = 1

local idnil             = 0
local idtrue            = 1
local idfalse           = 2
local idstring          = 3
local idbuffer          = 4
local idtable           = 5

local idnumber          = 32
local idzero            = 33
local idvector          = 34
local idzerovector      = 35

local idcframe          = 64
local idcolor3          = 65
local iddatetime        = 66
local ididentitycframe  = 67

local offset = 0
local writebuf = buffer.create(defaultbuffersize)
local readbuf: buffer

local function trim(): buffer
	local trimmed = buffer.create(offset + 1)
	buffer.copy(trimmed, 1, writebuf, 0, offset)
	buffer.writeu8(trimmed, 0, currentversion)
	return trimmed
end

local function unreachable(value: never): never
	return (error(`unreachable: {value}`))
end

local function writeid(id: number, alloc: number?): ()
	buffer.writeu8(writebuf, offset, id)
	offset += 1
end

local function writevector12(vec: vector)
	buffer.writef32(writebuf, offset, vec.x)
	buffer.writef32(writebuf, offset + 4, vec.y)
	buffer.writef32(writebuf, offset + 8, vec.z)
	offset += 12
end
local function readvector12(): vector
	local output = vector.create(
		buffer.readf32(readbuf, offset),
		buffer.readf32(readbuf, offset + 4),
		buffer.readf32(readbuf, offset + 8)
	)
	offset += 12
	return output
end

local function writedata(data: AnyData)
	if typeof(data) == "table" then
		writeid(idtable)
		local nilindex: number?
		for index = 1, #data do
			local value = data[index]
			if value == nil then
				nilindex = index
				break
			end
			writedata(data)
		end
		writeid(idnil)
		for key, value in next, data, nilindex do
			writedata(key)
			writedata(value)
		end
		writeid(idnil)
	elseif typeof(data) == "number" then
		if data == 0 then
			writeid(idzero)
		else
			writeid(idnumber, 8)
			buffer.writef64(writebuf, offset, data)
			offset += 8
		end
	elseif typeof(data) == "string" then
		local strlength = #data
		writeid(idstring, 4 + strlength)
		buffer.writeu32(writebuf, offset, strlength)
		offset += 4
		buffer.writestring(writebuf, offset, data, strlength)
		offset += strlength
	elseif typeof(data) == "Vector3" then
		if data == vector.zero then
			writeid(idzerovector)
		else
			writeid(idvector, 12)
			writevector12(data)
		end
	elseif typeof(data) == "boolean" then
		if data then
			writeid(idtrue)
		else
			writeid(idfalse)
		end
	elseif typeof(data) == "buffer" then
		local valuelength = buffer.len(data)
		writeid(idbuffer, 4 + valuelength)
		buffer.writeu32(writebuf, offset, valuelength)
		offset += 4
		buffer.copy(writebuf, offset, data)
		offset += valuelength
	elseif typeof(data) == "nil" then
		writeid(idnil)
	elseif typeof(data) == "CFrame" then
		if data == CFrame.identity then
			writeid(ididentitycframe)
		else
			writeid(idcframe, 12 + 12)
			writevector12(data.Position)
			writevector12(vector.create(data:ToEulerAngles()))
		end
	elseif typeof(data) == "DateTime" then
		writeid(iddatetime, 8)
		buffer.writef64(writebuf, offset, data.UnixTimestampMillis)
		offset += 8
	elseif typeof(data) == "Color3" then
		writeid(idcolor3)
		writevector12(vector.create(data.r, data.g, data.b))
	else
		unreachable(data)
	end
end

local function readdata(version: number): AnyData
	local id = buffer.readu8(readbuf, offset)
	offset += 1

	if id == idtable then
		local output: { [AnyData]: AnyData } = {}

		local idx = 0
		while true do
			idx += 1
			local value = readdata(version)
			if value == nil then
				break
			end
			output[idx] = value
		end
		while true do
			local key = readdata(version)
			if key == nil then
				break
			end
			local value = readdata(version)
			output[key] = value
		end

		return output
	elseif id == idnumber then
		local output = buffer.readf64(readbuf, offset)
		offset += 8
		return output
	elseif id == idzero then
		return 0
	elseif id == idstring then
		local strlength = buffer.readu32(readbuf, offset)
		offset += 4
		local output = buffer.readstring(readbuf, offset, strlength)
		offset += strlength
		return output
	elseif id == idvector then
		return readvector12()
	elseif id == idzerovector then
		return vector.zero
	elseif id == idfalse then
		return false
	elseif id == idtrue then
		return true
	elseif id == idbuffer then
		local valuelength = buffer.readu32(readbuf, offset)
		offset += 4
		local output = buffer.create(valuelength)
		buffer.copy(output, 0, readbuf, offset, valuelength)
		offset += valuelength
		return output
	elseif id == idnil then
		return nil
	elseif id == idcframe then
		local position = readvector12()
		local eulerangles = readvector12()
		return CFrame.new(position) * CFrame.fromEulerAngles(eulerangles.x, eulerangles.y, eulerangles.z)
	elseif id == ididentitycframe then
		return CFrame.identity
	elseif id == iddatetime then
		local timestamp = buffer.readf64(readbuf, offset)
		offset += 8
		return DateTime.fromUnixTimestampMillis(timestamp)
	elseif id == idcolor3 then
		local decoded = readvector12()
		return Color3.new(decoded.x, decoded.y, decoded.z)
	else
		return unreachable(id :: never)
	end
end

local function serialize(value: AnyData): buffer
	offset = 0
	writedata(value)
	return trim()
end

local function deserialize(buf: buffer): AnyData
	offset = 0
	readbuf = buf
	local version = buffer.readu8(readbuf, offset)
	offset += 1
	local output = readdata(version)
	-- allow read buffer to get garbage collected
	readbuf = nil :: any
	return output
end

return {
	serialize = serialize,
	deserialize = deserialize,
}