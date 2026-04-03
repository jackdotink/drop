--!native
--!optimize 2

export type AnyData = nil | boolean | number | Vector3 | buffer | string | CFrame | Color3 | DateTime | { [AnyData]: AnyData }

local defaultbuffersize = 5_242_880
local currentversion = 1

local idnil             = 0
local idtrue            = 1
local idfalse           = 2
local idstring          = 3
local idbuffer          = 4
local idtable           = 5

local idfloat64         = 32
local iduint8           = 33
local iduint16          = 34
local iduint32          = 35
local idnegativeuint8   = 36
local idnegativeuint16  = 37
local idnegativeuint32  = 38
local idzero            = 39
local idvector          = 40
local idzerovector      = 41

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

local function writeid(id: number): ()
	buffer.writeu8(writebuf, offset, id)
	offset += 1
end

local function writevariablenumber(num: number)
	if math.isfinite(num) and (num // 1 == num) then
		if num == 0 then
			writeid(idzero)
			return
		end
		local negativeeh = num < 0
		num = math.abs(num)
		if num < 2^16 then
			if num < 2^8 then
				writeid(if negativeeh then idnegativeuint8 else iduint8)
				buffer.writeu8(writebuf, offset, num)
				offset += 1
				return
			else
				writeid(if negativeeh then idnegativeuint16 else iduint16)
				buffer.writeu16(writebuf, offset, num)
				offset += 2
				return
			end
		elseif num < 2^32 then
			writeid(if negativeeh then idnegativeuint32 else iduint32)
			buffer.writeu32(writebuf, offset, num)
			offset += 4
			return
		end
	end
	writeid(idfloat64)
	buffer.writef64(writebuf, offset, num)
	offset += 8
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
		writevariablenumber(data)
	elseif typeof(data) == "string" then
		local strlength = #data
		writeid(idstring)
		buffer.writeu32(writebuf, offset, strlength)
		offset += 4
		buffer.writestring(writebuf, offset, data, strlength)
		offset += strlength
	elseif typeof(data) == "Vector3" then
		if data == Vector3.zero then
			writeid(idzerovector)
		else
			writeid(idvector)
			writevariablenumber(data.X)
			writevariablenumber(data.Y)
			writevariablenumber(data.Z)
		end
	elseif typeof(data) == "boolean" then
		if data then
			writeid(idtrue)
		else
			writeid(idfalse)
		end
	elseif typeof(data) == "buffer" then
		writeid(idbuffer)
		local valuelength = buffer.len(data)
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
			writeid(idcframe)
			local position = data.Position
			writevariablenumber(position.X)
			writevariablenumber(position.Y)
			writevariablenumber(position.Z)
			local rX, rY, rZ = data:ToEulerAngles()
			writevariablenumber(rX)
			writevariablenumber(rY)
			writevariablenumber(rZ)
		end
	elseif typeof(data) == "DateTime" then
		writeid(iddatetime)
		buffer.writef64(writebuf, offset, data.UnixTimestampMillis)
		offset += 8
	elseif typeof(data) == "Color3" then
		writeid(idcolor3)
		buffer.writeu8(writebuf, offset, data.r)
		offset += 1
		buffer.writeu8(writebuf, offset, data.g)
		offset += 1
		buffer.writeu8(writebuf, offset, data.b)
		offset += 1
	else
		unreachable(data)
	end
end

local function readdata(version: number): AnyData
	local id = buffer.readu8(readbuf, offset)
	offset += 1

	local output: AnyData

	if id == idtable then
		output = {}

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
			output[key :: any] = value
		end
	elseif id == idzero then
		output = 0
	elseif id == iduint8 then
		output = buffer.readu8(readbuf, offset)
		offset += 1
	elseif id == idnegativeuint8 then
		output = buffer.readu8(readbuf, offset)
		offset += 1
	elseif id == iduint16 then
		output = buffer.readu16(readbuf, offset)
		offset += 2
	elseif id == idnegativeuint16 then
		output = -buffer.readu16(readbuf, offset)
		offset += 2
	elseif id == iduint32 then
		output = buffer.readu32(readbuf, offset)
		offset += 4
	elseif id == idnegativeuint32 then
		output = -buffer.readu32(readbuf, offset)
		offset += 4
	elseif id == idfloat64 then
		output = buffer.readf64(readbuf, offset)
		offset += 8
	elseif id == idzero then
		output = 0
	elseif id == idstring then
		local strlength = buffer.readu32(readbuf, offset)
		offset += 4
		output = buffer.readstring(readbuf, offset, strlength)
		offset += strlength
	elseif id == idvector then
		output = Vector3.new(readdata(version) :: any, readdata(version) :: any, readdata(version) :: any)
	elseif id == idzerovector then
		output = vector.zero
	elseif id == idfalse then
		output = false
	elseif id == idtrue then
		output = true
	elseif id == idbuffer then
		local valuelength = buffer.readu32(readbuf, offset)
		offset += 4
		output = buffer.create(valuelength)
		buffer.copy(output, 0, readbuf, offset, valuelength)
		offset += valuelength
	elseif id == idnil then
		output = nil
	elseif id == idcframe then
		output = CFrame.new(readdata(version) :: any, readdata(version) :: any, readdata(version) :: any)
			* CFrame.fromEulerAngles(readdata(version) :: any, readdata(version) :: any, readdata(version) :: any)
	elseif id == ididentitycframe then
		output = CFrame.identity
	elseif id == iddatetime then
		local timestamp = buffer.readf64(readbuf, offset)
		offset += 8
		output = DateTime.fromUnixTimestampMillis(timestamp)
	elseif id == idcolor3 then
		local r = buffer.readu8(readbuf, offset)
		offset += 1
		local g = buffer.readu8(readbuf, offset)
		offset += 1
		local b = buffer.readu8(readbuf, offset)
		offset += 1
		output = Color3.new(r, g, b)
	else
		output = unreachable(id :: never)
	end

	return output
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