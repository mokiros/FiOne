--[[
FiOne
Copyright (C) 2021  Rerumu

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
]] --


local Constants = require("./constants")

local OPCODE_RM = Constants.OPCODE_RM
local OPCODE_M = Constants.OPCODE_M
local OPCODE_T = Constants.OPCODE_T

local ABC: Constants.OPCODE_T_ABC = Constants.OPCODE_T_ABC
local ABx: Constants.OPCODE_T_ABx = Constants.OPCODE_T_ABx
local AsBx: Constants.OPCODE_T_AsBx = Constants.OPCODE_T_AsBx
local OpArgK: Constants.OPCODE_M_OpArgK = "OpArgK"

type PartialStream = {
	index: number,
	source: string,
}

type Stream = PartialStream & {
	s_int: (self: Stream) -> number,
	s_szt: (self: Stream) -> number,
	s_ins: (self: Stream) -> number,
	s_num: (self: Stream) -> number,
}

export type Instruction = {
	value: number,
	op: number,
	A: number,
	B: number,
	Bx: number,
	C: number,
	sBx: number,
	is_K: boolean,
	is_KB: boolean,
	is_KC: boolean,
	const: any,
	const_B: any,
	const_C: any,
}

export type Proto = {
	source: string,
	num_upval: number,
	num_param: number,
	is_vararg: number,
	max_stack: number,
	code: { Instruction },
	const: { any },
	subs: { Proto },
	lines: { number },
	needs_arg: boolean,
}

-- int rd_int_basic(string src, int s, int e, int d)
-- @src - Source binary string
-- @s - Start index of a little endian integer
-- @e - End index of the integer
-- @d - Direction of the loop
local function rd_int_basic(src: string, s: number, e: number, d: number): number
	local num = 0

	-- if bb[l] > 127 then -- signed negative
	-- 	num = num - 256 ^ l
	-- 	bb[l] = bb[l] - 128
	-- end

	for i = s, e, d do
		local mul = 256 ^ math.abs(i - s)

		num = num + mul * string.byte(src, i, i)
	end

	return num
end

-- float rd_flt_basic(byte f1..8)
-- @f1..4 - The 4 bytes composing a little endian float
local function rd_flt_basic(f1: number, f2: number, f3: number, f4: number): number
	local sign = (-1) ^ bit32.rshift(f4, 7)
	local exp = bit32.rshift(f3, 7) + bit32.lshift(bit32.band(f4, 0x7F), 1)
	local frac = f1 + bit32.lshift(f2, 8) + bit32.lshift(bit32.band(f3, 0x7F), 16)
	local normal = 1

	if exp == 0 then
		if frac == 0 then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif exp == 0x7F then
		if frac == 0 then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 127) * (1 + normal / 2 ^ 23)
end

-- double rd_dbl_basic(byte f1..8)
-- @f1..8 - The 8 bytes composing a little endian double
local function rd_dbl_basic(
	f1: number,
	f2: number,
	f3: number,
	f4: number,
	f5: number,
	f6: number,
	f7: number,
	f8: number
): number
	local sign = (-1) ^ bit32.rshift(f8, 7)
	local exp = bit32.lshift(bit32.band(f8, 0x7F), 4) + bit32.rshift(f7, 4)
	local frac = bit32.band(f7, 0x0F) * 2 ^ 48
	local normal = 1

	frac = frac + (f6 * 2 ^ 40) + (f5 * 2 ^ 32) + (f4 * 2 ^ 24) + (f3 * 2 ^ 16) + (f2 * 2 ^ 8) + f1 -- help

	if exp == 0 then
		if frac == 0 then
			return sign * 0
		else
			normal = 0
			exp = 1
		end
	elseif exp == 0x7FF then
		if frac == 0 then
			return sign * (1 / 0)
		else
			return sign * (0 / 0)
		end
	end

	return sign * 2 ^ (exp - 1023) * (normal + frac / 2 ^ 52)
end

-- int rd_int_le(string src, int s, int e)
-- @src - Source binary string
-- @s - Start index of a little endian integer
-- @e - End index of the integer
local function rd_int_le(src: string, s: number, e: number): number
	return rd_int_basic(src, s, e - 1, 1)
end

-- int rd_int_be(string src, int s, int e)
-- @src - Source binary string
-- @s - Start index of a big endian integer
-- @e - End index of the integer
local function rd_int_be(src: string, s: number, e: number): number
	return rd_int_basic(src, e - 1, s, -1)
end

-- float rd_flt_le(string src, int s)
-- @src - Source binary string
-- @s - Start index of little endian float
local function rd_flt_le(src: string, s: number): number
	return rd_flt_basic(string.byte(src, s, s + 3))
end

-- float rd_flt_be(string src, int s)
-- @src - Source binary string
-- @s - Start index of big endian float
local function rd_flt_be(src: string, s: number): number
	local f1, f2, f3, f4 = string.byte(src, s, s + 3)
	return rd_flt_basic(f4, f3, f2, f1)
end

-- double rd_dbl_le(string src, int s)
-- @src - Source binary string
-- @s - Start index of little endian double
local function rd_dbl_le(src: string, s: number): number
	return rd_dbl_basic(string.byte(src, s, s + 7))
end

-- double rd_dbl_be(string src, int s)
-- @src - Source binary string
-- @s - Start index of big endian double
local function rd_dbl_be(src: string, s: number): number
	local f1, f2, f3, f4, f5, f6, f7, f8 = string.byte(src, s, s + 7) -- same
	return rd_dbl_basic(f8, f7, f6, f5, f4, f3, f2, f1)
end

-- to avoid nested ifs in deserializing
local float_types = {
	[4] = { little = rd_flt_le, big = rd_flt_be },
	[8] = { little = rd_dbl_le, big = rd_dbl_be },
}

-- byte stm_byte(Stream S)
-- @S - Stream object to read from
local function stm_byte(S: PartialStream): number
	local idx = S.index
	local bt = string.byte(S.source, idx, idx)

	S.index = idx + 1
	return bt
end

-- string stm_string(Stream S, int len)
-- @S - Stream object to read from
-- @len - Length of string being read
local function stm_string(S: PartialStream, len: number): string
	local pos = S.index + len
	local str = string.sub(S.source, S.index, pos - 1)

	S.index = pos
	return str
end

-- string stm_lstring(Stream S)
-- @S - Stream object to read from
local function stm_lstring(S: Stream): string
	local len = S:s_szt()
	local str

	if len ~= 0 then
		str = string.sub(stm_string(S, len), 1, -2)
	end

	return str
end

-- fn cst_int_rdr(string src, int len, fn func)
-- @len - Length of type for reader
-- @func - Reader callback
local function cst_int_rdr(len: number, func: (src: string, s: number, e: number) -> number)
	return function(S: PartialStream)
		local pos = S.index + len
		local int = func(S.source, S.index, pos)
		S.index = pos

		return int
	end
end

-- fn cst_flt_rdr(string src, int len, fn func)
-- @len - Length of type for reader
-- @func - Reader callback
local function cst_flt_rdr(len: number, func: (src: string, s: number) -> number)
	return function(S: PartialStream)
		local flt = func(S.source, S.index)
		S.index = S.index + len

		return flt
	end
end

local function stm_inst_list(S: Stream): { Instruction }
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		local ins = S:s_ins()
		local op = bit32.band(ins, 0x3F)
		local args: Constants.OPCODE_T = OPCODE_T[op]
		local mode = OPCODE_M[op]
		local data = { value = ins, op = OPCODE_RM[op], A = bit32.band(bit32.rshift(ins, 6), 0xFF) }

		if args == ABC then
			data.B = bit32.band(bit32.rshift(ins, 23), 0x1FF)
			data.C = bit32.band(bit32.rshift(ins, 14), 0x1FF)
			data.is_KB = mode.b == OpArgK and data.B > 0xFF -- post process optimization
			data.is_KC = mode.c == OpArgK and data.C > 0xFF

			if op == 10 then -- decode NEWTABLE array size, store it as constant value
				local e = bit32.band(bit32.rshift(data.B, 3), 31)
				if e == 0 then
					data.const = data.B
				else
					data.const = bit32.lshift(bit32.band(data.B, 7) + 8, e - 1)
				end
			end
		elseif args == ABx then
			data.Bx = bit32.band(bit32.rshift(ins, 14), 0x3FFFF)
			data.is_K = mode.b == OpArgK
		elseif args == AsBx then
			data.sBx = bit32.band(bit32.rshift(ins, 14), 0x3FFFF) - 131071
		end

		list[i] = data :: Instruction
	end

	return list
end

local function stm_const_list(S: Stream): { any }
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		local tt = stm_byte(S)
		local k: boolean | number | string

		if tt == 1 then
			k = stm_byte(S) ~= 0
		elseif tt == 3 then
			k = S:s_num()
		elseif tt == 4 then
			k = stm_lstring(S)
		end

		list[i] = k -- offset +1 during instruction decode
	end

	return list
end

local function stm_sub_list(S: Stream, src: string): { Proto }
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		list[i] = stm_lua_func(S, src) -- offset +1 in CLOSURE
	end

	return list
end

local function stm_line_list(S: Stream): { number }
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		list[i] = S:s_int()
	end

	return list
end

local function stm_loc_list(S: Stream): { { varname: string, startpc: number, endpc: number } }
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		list[i] = { varname = stm_lstring(S), startpc = S:s_int(), endpc = S:s_int() }
	end

	return list
end

local function stm_upval_list(S: Stream): { string }
	local len = S:s_int()
	local list = table.create(len)

	for i = 1, len do
		list[i] = stm_lstring(S)
	end

	return list
end

function stm_lua_func(S: Stream, psrc: string): Proto
	local proto = {}
	local src = stm_lstring(S) or psrc -- source is propagated

	proto.source = src -- source name

	S:s_int() -- line defined
	S:s_int() -- last line defined

	proto.num_upval = stm_byte(S) -- num upvalues
	proto.num_param = stm_byte(S) -- num params

	proto.is_vararg = stm_byte(S) -- vararg flag
	proto.max_stack = stm_byte(S) -- max stack size

	proto.code = stm_inst_list(S)
	proto.const = stm_const_list(S)
	proto.subs = stm_sub_list(S, src)
	proto.lines = stm_line_list(S)

	stm_loc_list(S)
	stm_upval_list(S)

	-- post process optimization
	proto.needs_arg = bit32.band(proto.is_vararg, 0x5) == 0x5
	for _, v in ipairs(proto.code) do
		if v.is_K then
			v.const = proto.const[v.Bx + 1] -- offset for 1 based index
		else
			if v.is_KB then
				v.const_B = proto.const[v.B - 0xFF]
			end

			if v.is_KC then
				v.const_C = proto.const[v.C - 0xFF]
			end
		end
	end

	return proto
end

function lua_bc_to_state(src: string)
	-- header flags
	local little
	local size_int
	local size_szt
	local size_ins
	local size_num
	local flag_int

	-- stream object
	local stream: PartialStream = {
		-- data
		index = 1,
		source = src,
	}

	assert(stm_string(stream, 4) == "\27Lua", "invalid Lua signature")
	assert(stm_byte(stream) == 0x51, "invalid Lua version")
	assert(stm_byte(stream) == 0, "invalid Lua format")

	little = stm_byte(stream) ~= 0
	size_int = stm_byte(stream)
	size_szt = stm_byte(stream)
	size_ins = stm_byte(stream)
	size_num = stm_byte(stream)
	flag_int = stm_byte(stream) ~= 0

	local rdr_func = little and rd_int_le or rd_int_be

	local full_stream: Stream = {
		index = stream.index,
		source = stream.source,
		s_int = cst_int_rdr(size_int, rdr_func),
		s_szt = cst_int_rdr(size_szt, rdr_func),
		s_ins = cst_int_rdr(size_ins, rdr_func),
		s_num = if flag_int
			then cst_int_rdr(size_num, rdr_func)
			elseif float_types[size_num] then cst_flt_rdr(
				size_num,
				float_types[size_num][little and "little" or "big"]
			)
			else error("unsupported float size"),
	}

	return stm_lua_func(full_stream, "@virtual")
end

return {
	lua_bc_to_state = lua_bc_to_state,
}
