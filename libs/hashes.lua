
local function not_available(_, method_name)
	error("Hash method "..method_name.." not available", 2);
end

local _M = setmetatable({}, { __index = not_available });

local function with(mod, f)
	local ok, pkg = pcall(require, mod);
	if ok then f(pkg); end
end

with("bgcrypto.md5", function (md5)
	_M.md5 = md5.digest;
	_M.hmac_md5 = md5.hmac.digest;
end);

with("bgcrypto.sha1", function (sha1)
	_M.sha1 = sha1.digest;
	_M.hmac_sha1 = sha1.hmac.digest;
	_M.scram_Hi_sha1 = function (p, s, i) return sha1.pbkdf2(p, s, i, 20); end;
end);

with("bgcrypto.sha256", function (sha256)
	_M.sha256 = sha256.digest;
	_M.hmac_sha256 = sha256.hmac.digest;
end);

with("bgcrypto.sha512", function (sha512)
	_M.sha512 = sha512.digest;
	_M.hmac_sha512 = sha512.hmac.digest;
end);

with("sha1", function (sha1)
	_M.sha1 = function (data, hex)
		if hex then
			return sha1.sha1(data);
		else
			return (sha1.binary(data));
		end
	end;
end);

return _M;
