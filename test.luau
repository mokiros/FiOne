local compile = require("../yueliang/src")
local fione = require("./src")

local bc = compile(
	[[
function a()
	local id = fork()
	print("Hello from " .. tostring(id))
end

a()
]],
	"hello.lua"
)

local proto = fione.bc_to_state(buffer.fromstring(bc))
local state = fione.create_state(proto, { print = print, tostring = tostring })

local states = { state }
local stateIds = {
	[state] = 1,
}
local nextId = 2
local currentState: fione.FiOneState

local function deepCopy(original)
	local copy = {}

	for key, value in original do
		copy[key] = type(value) == "table" and deepCopy(value) or value
	end

	return copy
end

function state.env.fork()
	local new_state: fione.FiOneState = {
		env = table.clone(currentState.env),
		stack_level = currentState.stack_level,
		stack = table.create(#currentState.stack),
	}

	for i, s in currentState.stack do
		local sc = table.clone(s)
		sc.memory = deepCopy(sc.memory)
		sc.open_list = deepCopy(sc.open_list)
		sc.upvals = deepCopy(sc.upvals)
		new_state.stack[i] = sc
	end

	local last_state = new_state.stack[new_state.stack_level]
	local A = last_state.prev_A

	last_state.memory[A] = nextId

	last_state.pc += 1

	table.insert(states, new_state)
	stateIds[new_state] = nextId
	nextId += 1

	return stateIds[currentState]
end

while #states > 0 do
	local n = #states
	local i = 1
	while i <= n do
		local s = states[i]
		currentState = s
		fione.step_state(s)
		if s.returned then
			table.remove(states, i)
			n -= 1
		else
			i += 1
		end
	end
end
