--!strict
--!optimize 2

local function deepEquals(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end

	for i, v in a do
		if not deepEquals(b[i], v) then
			return false
		end
	end

	for i, v in b do
		if not deepEquals(a[i], v) then
			return false
		end
	end

	return true
end

return deepEquals