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


-- remap for better lookup
local OPCODE_RM: { number } = {

	-- level 1
	[22] = 18, -- JMP
	[31] = 8, -- FORLOOP
	[33] = 28, -- TFORLOOP

	-- level 2
	[0] = 3, -- MOVE
	[1] = 13, -- LOADK
	[2] = 23, -- LOADBOOL
	[26] = 33, -- TEST

	-- level 3
	[12] = 1, -- ADD
	[13] = 6, -- SUB
	[14] = 10, -- MUL
	[15] = 16, -- DIV
	[16] = 20, -- MOD
	[17] = 26, -- POW
	[18] = 30, -- UNM
	[19] = 36, -- NOT

	-- level 4
	[3] = 0, -- LOADNIL
	[4] = 2, -- GETUPVAL
	[5] = 4, -- GETGLOBAL
	[6] = 7, -- GETTABLE
	[7] = 9, -- SETGLOBAL
	[8] = 12, -- SETUPVAL
	[9] = 14, -- SETTABLE
	[10] = 17, -- NEWTABLE
	[20] = 19, -- LEN
	[21] = 22, -- CONCAT
	[23] = 24, -- EQ
	[24] = 27, -- LT
	[25] = 29, -- LE
	[27] = 32, -- TESTSET
	[32] = 34, -- FORPREP
	[34] = 37, -- SETLIST

	-- level 5
	[11] = 5, -- SELF
	[28] = 11, -- CALL
	[29] = 15, -- TAILCALL
	[30] = 21, -- RETURN
	[35] = 25, -- CLOSE
	[36] = 31, -- CLOSURE
	[37] = 35, -- VARARG
}

export type OPCODE_T_ABC = "ABC"
export type OPCODE_T_ABx = "ABx"
export type OPCODE_T_AsBx = "AsBx"
export type OPCODE_T = OPCODE_T_ABC | OPCODE_T_ABx | OPCODE_T_AsBx

local OPCODE_T_ABC: OPCODE_T_ABC = "ABC"
local OPCODE_T_ABx: OPCODE_T_ABx = "ABx"
local OPCODE_T_AsBx: OPCODE_T_AsBx = "AsBx"

-- opcode types for getting values
local OPCODE_T: { [number]: OPCODE_T } = {
	[0] = OPCODE_T_ABC,
	OPCODE_T_ABx,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABx,
	OPCODE_T_ABC,
	OPCODE_T_ABx,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_AsBx,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_AsBx,
	OPCODE_T_AsBx,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABC,
	OPCODE_T_ABx,
	OPCODE_T_ABC,
}

export type OPCODE_M_OpArgR = "OpArgR"
export type OPCODE_M_OpArgN = "OpArgN"
export type OPCODE_M_OpArgK = "OpArgK"
export type OPCODE_M_OpArgU = "OpArgU"

local OPCODE_M_RN = { b = "OpArgR" :: OPCODE_M_OpArgR, c = "OpArgN" :: OPCODE_M_OpArgN }
local OPCODE_M_KN = { b = "OpArgK" :: OPCODE_M_OpArgK, c = "OpArgN" :: OPCODE_M_OpArgN }
local OPCODE_M_UU = { b = "OpArgU" :: OPCODE_M_OpArgU, c = "OpArgU" :: OPCODE_M_OpArgU }
local OPCODE_M_UN = { b = "OpArgU" :: OPCODE_M_OpArgU, c = "OpArgN" :: OPCODE_M_OpArgN }
local OPCODE_M_RK = { b = "OpArgR" :: OPCODE_M_OpArgR, c = "OpArgK" :: OPCODE_M_OpArgK }
local OPCODE_M_KK = { b = "OpArgK" :: OPCODE_M_OpArgK, c = "OpArgK" :: OPCODE_M_OpArgK }
local OPCODE_M_RR = { b = "OpArgR" :: OPCODE_M_OpArgR, c = "OpArgR" :: OPCODE_M_OpArgR }
local OPCODE_M_RU = { b = "OpArgR" :: OPCODE_M_OpArgR, c = "OpArgU" :: OPCODE_M_OpArgU }
local OPCODE_M_NU = { b = "OpArgN" :: OPCODE_M_OpArgN, c = "OpArgU" :: OPCODE_M_OpArgU }
local OPCODE_M_NN = { b = "OpArgN" :: OPCODE_M_OpArgN, c = "OpArgN" :: OPCODE_M_OpArgN }

export type OPCODE_M =
	typeof(OPCODE_M_RN)
	| typeof(OPCODE_M_KN)
	| typeof(OPCODE_M_UU)
	| typeof(OPCODE_M_UN)
	| typeof(OPCODE_M_RK)
	| typeof(OPCODE_M_KK)
	| typeof(OPCODE_M_RR)
	| typeof(OPCODE_M_RU)
	| typeof(OPCODE_M_NU)
	| typeof(OPCODE_M_NN)

local OPCODE_M: { [number]: OPCODE_M } = {
	[0] = OPCODE_M_RN,
	OPCODE_M_KN,
	OPCODE_M_UU,
	OPCODE_M_RN,
	OPCODE_M_UN,
	OPCODE_M_KN,
	OPCODE_M_RK,
	OPCODE_M_KN,
	OPCODE_M_UN,
	OPCODE_M_KK,
	OPCODE_M_UU,
	OPCODE_M_RK,
	OPCODE_M_KK,
	OPCODE_M_KK,
	OPCODE_M_KK,
	OPCODE_M_KK,
	OPCODE_M_KK,
	OPCODE_M_KK,
	OPCODE_M_RN,
	OPCODE_M_RN,
	OPCODE_M_RN,
	OPCODE_M_RR,
	OPCODE_M_RN,
	OPCODE_M_KK,
	OPCODE_M_KK,
	OPCODE_M_KK,
	OPCODE_M_RU,
	OPCODE_M_RU,
	OPCODE_M_UU,
	OPCODE_M_UU,
	OPCODE_M_UN,
	OPCODE_M_RN,
	OPCODE_M_RN,
	OPCODE_M_NU,
	OPCODE_M_UU,
	OPCODE_M_NN,
	OPCODE_M_UN,
	OPCODE_M_UN,
}

return {
	OPCODE_RM = OPCODE_RM,
	OPCODE_T = OPCODE_T,
	OPCODE_M = OPCODE_M,
	OPCODE_T_ABC = OPCODE_T_ABC,
	OPCODE_T_ABx = OPCODE_T_ABx,
	OPCODE_T_AsBx = OPCODE_T_AsBx,
	OPCODE_M_RN = OPCODE_M_RN,
	OPCODE_M_KN = OPCODE_M_KN,
	OPCODE_M_UU = OPCODE_M_UU,
	OPCODE_M_UN = OPCODE_M_UN,
	OPCODE_M_RK = OPCODE_M_RK,
	OPCODE_M_KK = OPCODE_M_KK,
	OPCODE_M_RR = OPCODE_M_RR,
	OPCODE_M_RU = OPCODE_M_RU,
	OPCODE_M_NU = OPCODE_M_NU,
	OPCODE_M_NN = OPCODE_M_NN,
}
