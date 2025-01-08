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
	source: buffer,
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

local int_readers = {
	little = {
		[4] = function(S: PartialStream): number
			local pos = S.index
			S.index += 4
			return buffer.readu32(S.source, pos)
		end,
		[8] = function(S: PartialStream): number
			local pos = S.index
			S.index += 8
			local n1 = buffer.readu32(S.source, pos)
			local n2 = buffer.readu32(S.source, pos + 4)
			return n2 * 0xFFFFFFFF + n1
		end,
	},
	big = {
		[4] = function(S: PartialStream): number
			local pos = S.index
			S.index += 4
			return bit32.byteswap(buffer.readu32(S.source, pos))
		end,
		[8] = function(S: PartialStream): number
			local pos = S.index
			S.index += 8
			local n1 = bit32.byteswap(buffer.readu32(S.source, pos))
			local n2 = bit32.byteswap(buffer.readu32(S.source, pos + 4))
			return n2 * 0xFFFFFFFF + n1
		end,
	},
}

local _swap_buffer = buffer.create(8)
local float_readers = {
	little = {
		[4] = function(S: PartialStream): number
			local pos = S.index
			S.index += 4
			return buffer.readf32(S.source, pos)
		end,
		[8] = function(S: PartialStream): number
			local pos = S.index
			S.index += 8
			return buffer.readf64(S.source, pos)
		end,
	},
	big = {
		[4] = function(S: PartialStream): number
			local pos = S.index
			S.index += 4

			local n = buffer.readu32(S.source, pos)
			buffer.writeu32(_swap_buffer, 0, bit32.byteswap(n))

			return buffer.readf32(_swap_buffer, 0)
		end,
		[8] = function(S: PartialStream): number
			local pos = S.index
			S.index += 8

			buffer.writeu32(_swap_buffer, 0, bit32.byteswap(buffer.readu32(S.source, pos + 4)))
			buffer.writeu32(_swap_buffer, 4, bit32.byteswap(buffer.readu32(S.source, pos)))

			return buffer.readf64(_swap_buffer, 0)
		end,
	},
}

-- byte stm_byte(Stream S)
-- @S - Stream object to read from
local function stm_byte(S: PartialStream): number
	local idx = S.index
	S.index = idx + 1

	return buffer.readu8(S.source, idx)
end

-- string stm_lstring(Stream S)
-- @S - Stream object to read from
local function stm_lstring(S: Stream): string
	local len = S:s_szt()
	local str = ""

	if len ~= 0 then
		local pos = S.index
		str = buffer.readstring(S.source, pos, len - 1)
		S.index = pos + len
	end

	return str
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

function lua_bc_to_state(src: buffer)
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
		index = 0,
		source = src,
	}

	assert(int_readers["little"][4](stream) == 0x61754c1b, "invalid Lua signature")
	assert(stm_byte(stream) == 0x51, "invalid Lua version")
	assert(stm_byte(stream) == 0, "invalid Lua format")

	little = stm_byte(stream) ~= 0
	size_int = stm_byte(stream)
	size_szt = stm_byte(stream)
	size_ins = stm_byte(stream)
	size_num = stm_byte(stream)
	flag_int = stm_byte(stream) ~= 0

	local rdr_func = little and "little" or "big"

	local full_stream: Stream = {
		index = stream.index,
		source = stream.source,
		s_int = assert(int_readers[rdr_func][size_int], `Invalid int size: {size_int}`),
		s_szt = assert(int_readers[rdr_func][size_szt], `Invalid int size: {size_szt}`),
		s_ins = assert(int_readers[rdr_func][size_ins], `Invalid int size: {size_ins}`),
		s_num = if flag_int
			then assert(int_readers[rdr_func][size_num], `Invalid int size: {size_num}`)
			else assert(float_readers[rdr_func][size_num], `Invalid float size: {size_num}`),
	}

	return stm_lua_func(full_stream, "@virtual")
end

return {
	lua_bc_to_state = lua_bc_to_state,
}
