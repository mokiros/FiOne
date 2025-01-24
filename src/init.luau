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
local runner = require("./runner")

export type FiOneState = runner.FiOneState

return {
	bc_to_state = parser.lua_bc_to_state,
	create_state = runner.create_fione_state,
	step_state = runner.step_state,
	OPCODE_RM = Constants.OPCODE_RM,
	OPCODE_T = Constants.OPCODE_T,
	OPCODE_M = Constants.OPCODE_M,
}
