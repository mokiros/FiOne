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
]]
--

local Constants = require("./constants")
local parser = require("./parser")

local OPCODE_RM = Constants.OPCODE_RM

export type VarArg = {
	len: number,
	list: { any },
}

export type Upvalue = {
	index: number,
	store: { any },
	value: any,
}

export type LuaState = {
	is_tailcall: boolean,
	prev_A: number,
	prev_C: number,
	vararg: VarArg,
	memory: { any },
	top_index: number,
	upvals: { Upvalue },
	open_list: { Upvalue },
	code: { parser.Instruction },
	subs: { parser.Proto },
	pc: number,
}

export type FiOneState = {
	env: { [string]: any },
	stack_level: number,
	stack: { LuaState },
	returned: { any }?,
}

export type ErrorState = {
	pc: number,
	source: string,
	lines: { number },
}

-- SETLIST config
local FIELDS_PER_FLUSH = 50

local CLOSURES = setmetatable({} :: { [any]: { upvals: { Upvalue }, proto: parser.Proto } }, { __mode = "k" })

local function close_lua_upvalues(list: { Upvalue }, index: number)
	for i, uv in pairs(list) do
		if uv.index >= index then
			uv.value = uv.store[uv.index] -- store value
			uv.store = uv
			uv.index = "value" :: any -- self reference
			list[i] = nil
		end
	end
end

local function open_lua_upvalue(list: { Upvalue }, index: number, memory: { any })
	local prev = list[index]

	if not prev then
		prev = { index = index, store = memory }
		list[index] = prev
	end

	return prev
end

local function create_lua_state(proto: parser.Proto, upvals: { Upvalue }): LuaState
	return {
		is_tailcall = false,
		prev_A = 0,
		prev_C = 0,
		num_param = proto.num_param,
		needs_arg = proto.needs_arg,
		upvals = upvals,
		top_index = -1,
		open_list = {},
		vararg = { len = 0, list = {} },
		memory = table.create(proto.max_stack),
		code = proto.code,
		subs = proto.subs,
		pc = 1,
	}
end

local function push_stack(global_state: FiOneState, callable: any, i: number, j: number)
	local stack_level = global_state.stack_level
	local last_state = global_state.stack[stack_level]

	if typeof(callable) == "userdata" and CLOSURES[callable] then
		local closure = CLOSURES[callable]
		local proto = closure.proto
		local state = create_lua_state(proto, closure.upvals)

		local n = j - i + 1

		table.move(last_state.memory, i, math.min(i + proto.num_param, j), 1 - 1, state.memory)

		if proto.num_param < n then
			local start = proto.num_param + 1
			local len = n - proto.num_param

			state.vararg.len = len
			table.move(last_state.memory, i + start - 1, math.min(j, i + start + len - 2), 1, state.vararg.list)
		end

		if proto.needs_arg then
			state.memory[proto.num_param] =
				{ n = state.vararg.len, table.unpack(state.vararg.list, 1, state.vararg.len) }
		end

		global_state.stack[stack_level + 1] = state
		global_state.stack_level = stack_level + 1
	else
		local ret_list = table.pack(callable(table.unpack(last_state.memory, i, j)))

		local ret_num = ret_list.n

		local A = last_state.prev_A
		local C = last_state.prev_C

		if C == 0 then
			last_state.top_index = A + ret_num - 1
		else
			ret_num = C - 1
		end

		table.move(ret_list, 1, ret_num, A, last_state.memory)

		last_state.pc += 1
	end
end

local function pop_stack(global_state: FiOneState, i: number, j: number)
	local stack_level = global_state.stack_level
	local last_state = global_state.stack[stack_level]
	global_state.stack[stack_level] = nil
	local last_state_memory = last_state.memory

	local ret_num = j - i + 1

	if stack_level == 1 then
		local ret = table.create(ret_num)
		table.move(last_state_memory, i, j, 1, ret)
		global_state.returned = ret
		return
	end

	local prev_state = global_state.stack[stack_level - 1]

	while prev_state.is_tailcall do
		stack_level -= 1
		global_state.stack[stack_level] = nil
		prev_state = global_state.stack[stack_level - 1]
	end

	local prev_state_memory = prev_state.memory
	local A = prev_state.prev_A
	local C = prev_state.prev_C

	if C == 0 then
		prev_state.top_index = A + ret_num - 1
	else
		ret_num = C - 1
	end

	table.move(last_state_memory, i, i + ret_num, A, prev_state_memory)

	prev_state.pc += 1
	global_state.stack_level = stack_level - 1
end

local function step_lua_func(global_state: FiOneState)
	local stack_level = global_state.stack_level
	local state = global_state.stack[stack_level]

	local env = global_state.env

	local code = state.code
	local subs = state.subs
	local vararg = state.vararg

	local upvals = state.upvals
	local open_list = state.open_list
	local memory = state.memory
	local pc = state.pc

	local inst = code[pc]
	local op = inst.op
	pc = pc + 1

	if op < 18 then
		if op < 8 then
			if op < 3 then
				if op < 1 then
					--[[LOADNIL]]
					for i = inst.A, inst.B do
						memory[i] = nil
					end
				elseif op > 1 then
					--[[GETUPVAL]]
					local uv = upvals[inst.B]

					memory[inst.A] = uv.store[uv.index]
				else
					--[[ADD]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					memory[inst.A] = lhs + rhs
				end
			elseif op > 3 then
				if op < 6 then
					if op > 4 then
						--[[SELF]]
						local A = inst.A
						local B = inst.B
						local index

						if inst.is_KC then
							index = inst.const_C
						else
							index = memory[inst.C]
						end

						memory[A + 1] = memory[B]
						memory[A] = memory[B][index]
					else
						--[[GETGLOBAL]]
						memory[inst.A] = env[inst.const]
					end
				elseif op > 6 then
					--[[GETTABLE]]
					local index

					if inst.is_KC then
						index = inst.const_C
					else
						index = memory[inst.C]
					end

					memory[inst.A] = memory[inst.B][index]
				else
					--[[SUB]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					memory[inst.A] = lhs - rhs
				end
			else --[[MOVE]]
				memory[inst.A] = memory[inst.B]
			end
		elseif op > 8 then
			if op < 13 then
				if op < 10 then
					--[[SETGLOBAL]]
					env[inst.const] = memory[inst.A]
				elseif op > 10 then
					if op < 12 then
						--[[CALL]]
						local A = inst.A
						local B = inst.B
						local C = inst.C
						local params

						if B == 0 then
							params = state.top_index - A
						else
							params = B - 1
						end

						state.prev_A = A
						state.prev_C = C
						push_stack(global_state, memory[A], A + 1, A + params)
						return
					else
						--[[SETUPVAL]]
						local uv = upvals[inst.B]

						uv.store[uv.index] = memory[inst.A]
					end
				else
					--[[MUL]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					memory[inst.A] = lhs * rhs
				end
			elseif op > 13 then
				if op < 16 then
					if op > 14 then
						--[[TAILCALL]]
						local A = inst.A
						local B = inst.B
						local params

						if B == 0 then
							params = state.top_index - A
						else
							params = B - 1
						end

						close_lua_upvalues(open_list, 0)

						state.is_tailcall = true
						push_stack(global_state, memory[A], A + 1, A + params)
						return
					else
						--[[SETTABLE]]
						local index, value

						if inst.is_KB then
							index = inst.const_B
						else
							index = memory[inst.B]
						end

						if inst.is_KC then
							value = inst.const_C
						else
							value = memory[inst.C]
						end

						memory[inst.A][index] = value
					end
				elseif op > 16 then
					--[[NEWTABLE]]
					memory[inst.A] = table.create(inst.const) -- inst.const contains array size
				else
					--[[DIV]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					memory[inst.A] = lhs / rhs
				end
			else
				--[[LOADK]]
				memory[inst.A] = inst.const
			end
		else
			--[[FORLOOP]]
			local A = inst.A
			local step = memory[A + 2]
			local index = memory[A] + step
			local limit = memory[A + 1]
			local loops

			if step >= 0 then
				loops = index <= limit
			else
				loops = index >= limit
			end

			if loops then
				memory[A] = index
				memory[A + 3] = index
				pc = pc + inst.sBx
			end
		end
	elseif op > 18 then
		if op < 28 then
			if op < 23 then
				if op < 20 then
					--[[LEN]]
					memory[inst.A] = #memory[inst.B]
				elseif op > 20 then
					if op < 22 then
						--[[RETURN]]
						local A = inst.A
						local B = inst.B
						local len

						if B == 0 then
							len = state.top_index - A + 1
						else
							len = B - 1
						end

						close_lua_upvalues(open_list, 0)
						pop_stack(global_state, A, A + len - 1)
						return
					else
						--[[CONCAT]]
						local B, C = inst.B, inst.C
						local success, str = pcall(table.concat, memory, "", B, C)

						if not success then
							str = memory[B]

							for i = B + 1, C do
								str = str .. memory[i]
							end
						end

						memory[inst.A] = str
					end
				else
					--[[MOD]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					memory[inst.A] = lhs % rhs
				end
			elseif op > 23 then
				if op < 26 then
					if op > 24 then
						--[[CLOSE]]
						close_lua_upvalues(open_list, inst.A)
					else
						--[[EQ]]
						local lhs, rhs

						if inst.is_KB then
							lhs = inst.const_B
						else
							lhs = memory[inst.B]
						end

						if inst.is_KC then
							rhs = inst.const_C
						else
							rhs = memory[inst.C]
						end

						if (lhs == rhs) == (inst.A ~= 0) then
							pc = pc + code[pc].sBx
						end

						pc = pc + 1
					end
				elseif op > 26 then
					--[[LT]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					if (lhs < rhs) == (inst.A ~= 0) then
						pc = pc + code[pc].sBx
					end

					pc = pc + 1
				else
					--[[POW]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					memory[inst.A] = lhs ^ rhs
				end
			else
				--[[LOADBOOL]]
				memory[inst.A] = inst.B ~= 0

				if inst.C ~= 0 then
					pc = pc + 1
				end
			end
		elseif op > 28 then
			if op < 33 then
				if op < 30 then
					--[[LE]]
					local lhs, rhs

					if inst.is_KB then
						lhs = inst.const_B
					else
						lhs = memory[inst.B]
					end

					if inst.is_KC then
						rhs = inst.const_C
					else
						rhs = memory[inst.C]
					end

					if (lhs <= rhs) == (inst.A ~= 0) then
						pc = pc + code[pc].sBx
					end

					pc = pc + 1
				elseif op > 30 then
					if op < 32 then
						--[[CLOSURE]]
						local sub = subs[inst.Bx + 1] -- offset for 1 based index
						local nups = sub.num_upval
						local uvlist

						if nups ~= 0 then
							uvlist = table.create(nups - 1)

							for i = 1, nups do
								local pseudo = code[pc + i - 1]

								if pseudo.op == OPCODE_RM[0] then -- @MOVE
									uvlist[i - 1] = open_lua_upvalue(open_list, pseudo.B, memory)
								elseif pseudo.op == OPCODE_RM[4] then -- @GETUPVAL
									uvlist[i - 1] = upvals[pseudo.B]
								end
							end

							pc = pc + nups
						end

						local proxy = newproxy(false)
						CLOSURES[proxy] = { proto = sub, upvals = uvlist or {} }

						memory[inst.A] = proxy
					else
						--[[TESTSET]]
						local A = inst.A
						local B = inst.B

						if (not memory[B]) ~= (inst.C ~= 0) then
							memory[A] = memory[B]
							pc = pc + code[pc].sBx
						end
						pc = pc + 1
					end
				else
					--[[UNM]]
					memory[inst.A] = -memory[inst.B]
				end
			elseif op > 33 then
				if op < 36 then
					if op > 34 then
						--[[VARARG]]
						local A = inst.A
						local len = inst.B

						if len == 0 then
							len = vararg.len
							state.top_index = A + len - 1
						end

						table.move(vararg.list, 1, len, A, memory)
					else
						--[[FORPREP]]
						local A = inst.A
						local init, limit, step

						init = assert(tonumber(memory[A]), "`for` initial value must be a number")
						limit = assert(tonumber(memory[A + 1]), "`for` limit must be a number")
						step = assert(tonumber(memory[A + 2]), "`for` step must be a number")

						memory[A] = init - step
						memory[A + 1] = limit
						memory[A + 2] = step

						pc = pc + inst.sBx
					end
				elseif op > 36 then
					--[[SETLIST]]
					local A = inst.A
					local C = inst.C
					local len = inst.B
					local tab = memory[A]
					local offset

					if len == 0 then
						len = state.top_index - A
					end

					if C == 0 then
						C = inst[pc].value
						pc = pc + 1
					end

					offset = (C - 1) * FIELDS_PER_FLUSH

					table.move(memory, A + 1, A + len, offset + 1, tab)
				else
					--[[NOT]]
					memory[inst.A] = not memory[inst.B]
				end
			else
				--[[TEST]]
				if (not memory[inst.A]) ~= (inst.C ~= 0) then
					pc = pc + code[pc].sBx
				end
				pc = pc + 1
			end
		else
			--[[TFORLOOP]]
			local A = inst.A
			local base = A + 3

			local vals = { memory[A](memory[A + 1], memory[A + 2]) }

			table.move(vals, 1, inst.C, base, memory)

			if memory[base] ~= nil then
				memory[A + 2] = memory[base]
				pc = pc + code[pc].sBx
			end

			pc = pc + 1
		end
	else
		--[[JMP]]
		pc = pc + inst.sBx
	end

	state.pc = pc
end

local function create_fione_state(proto: parser.Proto, env: { [string]: any }): FiOneState
	return {
		env = env,
		stack_level = 1,
		stack = { create_lua_state(proto, {}) },
	}
end

return {
	create_fione_state = create_fione_state,
	create_lua_state = create_lua_state,
	step_lua_func = step_lua_func,
}
