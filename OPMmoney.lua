-- Loader Obfuscated
local b='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/' 
local function b64decode(data)
    data = string.gsub(data, '[^'..b..'=]', '')
    return (data:gsub('.', function(x)
        if (x == '=') then return '' end
        local r,f='',(b:find(x)-1)
        for i=6,1,-1 do r = r .. (f%2^i - f%2^(i-1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d%d%d%d%d%d', function(x)
        local c=0
        for i=1,8 do c=c + (x:sub(i,i) == '1' and 2^(8-i) or 0) end
        return string.char(c)
    end))
end

-- ใส่ Base64 ของโค้ด Auto Treasure Chest Farm
local raw = "LS0vLyBBdXRvIFRyZWFzdXJlIENoZXN0IEZhcm0gKyBIb3AgU2VydmVyICsgVUlCDQpsb2NhbCBQbGF5ZXJzID0gZ2FtZT...<ตัดสั้น>...KClbXQ=="

local ok, chunk = pcall(loadstring, b64decode(raw))
if not ok then
    error("Load fail: "..tostring(chunk))
else
    chunk()
end
