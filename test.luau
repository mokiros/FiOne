local compile = require("../yueliang/src")
local fione = require("./src")

local bc = compile(
	[[
-- Successful pcall
do
	local success, msg, stack_trace = pcall(function()
		return "Hello, "
	end)

	print("First call: " .. (success and "Success" or "Fail") .. ";", "Returned:", msg)
	if not success then
		print("Stack trace:")
		print(stack_trace)
	end
end

-- pcall with error
do
	local success, msg, stack_trace = pcall(function()
		return "World!" .. nil
	end)

	print("Second call: " .. (success and "Success" or "Fail") .. ";", "Returned:", msg)
	if not success then
		print("Stack trace:")
		print(stack_trace)
	end
end

-- pcall stack test, should print 4 `true`
print(pcall(pcall, pcall, pcall, function() return "pcall stack test" end))

-- these values should get printed by the runner below
return 1, 2, 3, "test"
]],
	"hello.lua"
)

local proto = fione.bc_to_state(buffer.fromstring(bc))
local state = fione.create_state(proto, { print = print, tostring = tostring, error = error })

local states = { state }

while #states > 0 do
	local n = #states
	local i = 1
	while i <= n do
		local s = states[i]
		fione.step_state(s)
		if s.stack_level == 0 then
			print(`State {i} finished`)
			print("Returned values:", s.stack[0].memory)
			table.remove(states, i)
			n -= 1
		else
			i += 1
		end
	end
end
