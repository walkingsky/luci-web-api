--[[
	walkingsky
	tangxn_1@163.com
]]--

module("luci.controller.webapi", package.seeall)


cmd_talbe = {
	ip = { 
		get_cmd = "uci get network.lan.ipaddr",
		set_cmd = "uci set network.lan.ipaddr=",
	},
	channel={ 
		get_cmd = "uci get wireless.ra0.channel",
		set_cmd = "uci set  wireless.ra0.channel=",
	},
	ssid={ 
		get_cmd = "uci get wireless.@wifi-iface[0].ssid",
		set_cmd = "uci set wireless.@wifi-iface[0].ssid=",
	},
	ssidpwd={ 
		get_cmd = "uci get wireless.@wifi-iface[0].key",
		set_cmd = "uci set  wireless.@wifi-iface[0].encryption=psk; uci set  wireless.@wifi-iface[0].key=",
	},
	nettype={ 
		get_cmd = "uci get network.wan.proto",
		set_cmd = "uci set network.wan.proto=",
	},
	pppoenm={ 
		get_cmd = "uci get  network.wan.username",
		set_cmd = "uci set  network.wan.username=",
	},
	pppoepwd={ 
		get_cmd = "uci get  network.wan.password",
		set_cmd = "uci set  network.wan.password=",
	},
}

update_cmd_table = {
	version_code={
		get_cmd = "echo $(cat /var/sysinfo/board_name )_$(uci get version.version.version)_$(uci get version.version.last_commit) ",
	},
}

--判断升级索引
function is_update_index(str)
	return (  str == 'version_code'  )
end

--判断索引
function is_index(str)

	return ( str == 'ip' or str == 'channel' or str == 'ssid' or str == 'ssidpwd'  or str == 'nettype' or str == 'pppoenm' 
		or str == 'pppoepwd'   )

end

function index()
	
	local page   = node("webapi")
	page.target  = firstchild()
	page.title   = _("webapi")
	page.order   = 20
	--先不加密,去掉注释，连接该api接口必须要用HTTP_AUTHORIZATION 用户名密码
	--[[
	page.sysauth = "webapi"
	page.sysauth_authenticator =  function()                            
			local auth = luci.http.getenv("HTTP_AUTHORIZATION")        
			auth = auth and auth:match("[^ ]+[ ]+([%w+/=]+)")            
			auth = auth and nixio.bin.b64decode(auth)                  
																			   
			if not auth or auth ~= "admin:admin" then                  
					-- need auth info                                  
					luci.http.status(401, "Unauthorized")              
					luci.http.header("WWW-Authenticate", 'Basic realm="auth first"')
					luci.http.header("Content-Type", "text/plain")     
					luci.http.write("Login Required!")                 
					return false                                       
			else                                                               
					                                          
					return page.sysauth                                              
			end                                                                      
	end
	]]--
	page.ucidata = true
	page.index = false
	
	
	entry({"webapi", "auth"}, call("action_auth")).leaf = true
	
end




--保存文件
function save_file(content,dir,permission)
	local file = io.open(dir,"w")
	file:write(content)
	file:close() 
	run_cmd("chmod "..permission.." "..dir)
end

--移动文件
function mv_file(src,dst,permission)
	if run_cmd("mv "..src.." "..dst.." ")  then
		run_cmd("chmod "..permission.." "..dst)
		return true
	else
		return false
	end
end

--执行系统命令并返回执行结果
function run_cmd(cmd)
	local t = io.popen(cmd)
	local temp = t:read("*all")
	--去掉回车
	if temp:match("\n$") then
		temp = string.sub(temp,1,-2)
	end
	--如果是空值，是否返回false
	return temp
end


function exec_ping()
	ping_success=os.execute('ping -c1 8.8.8.8 >/dev/null')
	if ping_success then
		--print("ping success")
		run_cmd("uci set  webapi.webapi.connection=1 ;uci  commit  webapi ") 
	else
		--print("ping fail")
		run_cmd("uci set  webapi.webapi.connection=0 ;uci  commit  webapi ") 
	end
end


--解码命令
function _decode_str(str)	
	return (str and nixio.bin.b64decode(str))
end

function _debug(str)
	util = require "cjson.util"
	local temp_str = util.serialise_value(str)
	local file = io.open("/tmp/log.txt","a")
	file:write(temp_str)
	file:close() 
end 


--解析升级cmd
function parse_update_cmd(cmdstr)
	local cmd_kind = string.match(cmdstr,"GET=") or string.match(cmdstr,"SET=")
	local cmd_json = string.sub(cmdstr,5)
	local json = require "cjson.safe"
	local result = "{"
	
	if cmd_kind == "GET=" then
		for k in string.gmatch(cmd_json,"\"([^\"]+)\"") do
			--_debug("key:("..k..")\n")
			if is_update_index(k) then
				rs = run_cmd(update_cmd_table[k].get_cmd)
				
				result  = result..'"'..k..'":"'..rs..'",'
			end
		end
		result = result..'}'
		
		return result
	elseif cmd_kind == "SET=" then
		t = json.decode(cmd_json)
		tmp_str = ""
		if t ~= nil then
			for k,v in  pairs(t) do
				if k == "do_update" then
					if v == "1" then
						rs = run_cmd("asd_update.sh do")
						_debug(rs)
					end
				end
			end
		end
	else
		return "{}"
	end
end

--解析cmd
function parse_cmd(cmdstr)
	local cmd_kind = string.match(cmdstr,"GET=") or string.match(cmdstr,"SET=")
	local cmd_json = string.sub(cmdstr,5)
	local json = require "cjson.safe"
	local result = "{"
	--_debug("parse_cmd("..cmdstr..") cmd_json("..cmd_json..")\n")
	--get
	if cmd_kind == "GET=" then
		for k in string.gmatch(cmd_json,"\"([^\"]+)\"") do
			--_debug("key:("..k..")\n")
			if is_index(k) then
				rs = run_cmd(cmd_talbe[k].get_cmd)
				if k == "channel" then
					if rs == "auto" then
						result  = result..'"'..k..'":"0",'
					else
						result  = result..'"'..k..'":"'..rs..'",'
					end
				elseif k == "nettype" then
					if rs == "pppoe" then
						result  = result..'"'..k..'":"1",'
					else
						result  = result..'"'..k..'":"0",'
					end
				else
					result  = result..'"'..k..'":"'..rs..'",'
				end
			end
		end
		result = result..'}'
		--_debug(result)
		--return json.encode(result)
		return result
	elseif cmd_kind == "SET=" then
		t = json.decode(cmd_json)
		tmp_str = ""
		if t ~= nil then
			for k,v in  pairs(t) do
				--_debug("key:("..k.."),value("..v.."),type("..type(v)..")\n")
				if is_index(k) then
					if k == "channel" then
						if v == "0" then
							v  = "auto"
						else
							v  = v
						end
						tmp_str = cmd_talbe[k].set_cmd..v..";uci commit"
					elseif k == "nettype" then
						if v == "0" then
							v = "dhcp"
						else
							v = "pppoe"
						end
						tmp_str = cmd_talbe[k].set_cmd..v..";uci commit"
					elseif k == "ssidpwd" then
						if v == '' or v == nil then
							tmp_str = "uci set  wireless.@wifi-iface[0].encryption=none; uci set  wireless.@wifi-iface[0].key='';uci commit"
						else
							tmp_str = cmd_talbe[k].set_cmd..v..";uci commit"
						end
					else
						tmp_str = cmd_talbe[k].set_cmd..v..";uci commit"
					end
					--_debug(cmd_talbe[k].set_cmd..v)
					rs = os.execute(tmp_str)
					rsl = "true"
					if rs == -1 or rs == 127 then
						rsl="false"
					end 
					--table.insert(result,rsl)
					result  = result..'"'..k..'":"'..rsl..'",'
				end
			end
		end 
		result = string.sub(result,1,string.len(result)-1)..'}'
		--_debug(result)
		--return json.encode(result)
		return result
	else
		return "{}"
	end
end

--返回提示
function _return(bool)
	if bool then
		
	else
		luci.http.write('')
	end
end

function file_exists(path)
   local f=io.open(path,"r")
   if f~=nil then io.close(f) return true else return false end
end

function action_auth()
	
	
	local fp
	local image_file = "/tmp/upload_"..os.time()
	luci.http.setfilehandler(
		function(meta, chunk, eof)
			if not fp then
				if meta and meta.name == "image" then
					fp = io.open(image_file, "w")
				end
			end
			if chunk then
				fp:write(chunk)
			end
			if eof then
				fp:close()
				luci.http.write("{\"upload\":\"ok\",\"file\":\""..image_file.."\"}")
			end
		end
	)
	
	local head = luci.http.formvalue("head")
	local strsize = luci.http.formvalue("strsize")
	local cmd = luci.http.formvalue("cmd")
	local shell = luci.http.formvalue("shell")
	local strsizecon = luci.http.formvalue("strsizecon")
	local content = luci.http.formvalue("content")
	local strsizedir = luci.http.formvalue("strsizedir")
	local directory = luci.http.formvalue("directory")
	local permission = luci.http.formvalue("permission")
	local updatecmd = luci.http.formvalue("updatecmd")
	
	
	
	
	if head == nil or fmid == nill then
		_return(false)
	else
		--fmid 如何校验
		if head == '01' then --格式话的命令
			if cmd ~= nil and strsize ~= nil  and string.len(cmd) == tonumber(strsize) then
				cmd = _decode_str(cmd)
				if not cmd then
					_return(false)
				end
				local result = parse_cmd(cmd)
				luci.http.write(result)
				--是否要重启
				if string.match(cmd,"SET=") then
					os.execute("reboot")				
				end				
			else
				--参数错误，提示
				_return(false)
			end
		elseif head == '02' then --原生的shell
			if shell ~= nil and strsize ~= nil  and string.len(shell) == tonumber(strsize) then
				shell = _decode_str(shell)
				--_debug(shell)
				cmd_kind = string.match(shell,"SHELL={") or nil
				
				if cmd_kind == nil then
					_return(false)
				end 
				shell = string.sub(shell,9,-3)
				--保存文件
				save_file(shell,'/tmp/_shell.sh','755')
				--执行文件
				result = run_cmd('/tmp/_shell.sh')
				luci.http.write("{\"SHELL\":\""..result.."\"}")
			else
				--参数错误，提示
				_return(false)
			end
		elseif head == '03' then --文件
			if content ~= nil and strsizecon ~= nil   and 
				directory ~= nil and strsizedir ~= nil  and string.len(directory) == tonumber(strsizedir) and
				permission ~= nil  then
				--_debug(directory)
				--_debug(content)
				content = _decode_str(content)
				
				--_debug(content)
				if content == nil  then
					_return(false)
				end
				
				if file_exists(""..content) then
				
					directory = _decode_str(directory)
					--对permission进行严格校验
					--_debug(directory)
					if mv_file(content,directory,permission) then
						luci.http.write("{\"savefile\":\"ok\"}")
					else
						_return(false)
					end 					
				else
					_return(false)
				end
			else
				_return(false)
			end
		elseif head == '04' then --升级相关
			if updatecmd ~= nil and strsize ~= nil  and string.len(updatecmd) == tonumber(strsize) then
				updatecmd = _decode_str(updatecmd)
				--_debug(updatecmd)
				if not updatecmd then
					_return(false)
				end
					result = parse_update_cmd(updatecmd)
					luci.http.write(result)
			else
				_return(false)
			end 
		else
			_return(false)
		end
	
	end
	_return(false)
end



