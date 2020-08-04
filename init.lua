-- staff mod for Blocky Survival
-- copyright (c) 2019 BillyS

local ienv = minetest.request_insecure_environment()
local wp = minetest.get_worldpath()

-- Open database
if not ienv then
   error("The staff mod requires an insecure environment; please add this mod as trusted")
end

local sqlite = ienv.require("lsqlite3")
sqlite3 = nil

local db = sqlite.open(wp .. "/staff.sqlite")

-- Close on shutdown
minetest.register_on_shutdown(function()
   db:close_vm(false)
   db:close()
end)

-- Functions
local function log_error()
   minetest.log("error", "[staff]: SQLite error: " .. db:errmsg())
end

local function first_row(ps)
   for r in ps:nrows() do return r end
   return nil
end

local function get_rank_by_uid(ruid)
   local ps = db:prepare("SELECT name FROM ranks WHERE rowid=:rowid")
   ps:bind_values(ruid)
   return first_row(ps).name
end
   
local function execute_sql(sql, func)
   local code = db:exec(sql, func)
   if code ~= sqlite.OK then
      minetest.log("error", "[staff]: SQLite error: " .. db:errmsg())
      return false
   end
   return true
end

-- Create tables if needed
execute_sql("CREATE TABLE IF NOT EXISTS ranks(name VARCHAR(50), UNIQUE(name));" ..
"CREATE TABLE IF NOT EXISTS staff(" ..
"name VARCHAR(50) NOT NULL," ..
"rank_uid INTEGER NOT NULL," ..
"UNIQUE(name)" ..
"FOREIGN KEY(rank_uid) REFERENCES ranks(rowid));")

local function format_tag(pname, rank)
   return minetest.colorize("#00FF00", "[" .. rank .. "] ") .. pname
end


-- Register chat commands
ChatCmdBuilder.new("staff", function(cmd)

   cmd:sub("add rank :rank", function(name, rank)
      local ps = db:prepare("INSERT INTO ranks(name) VALUES (:rank)")
      ps:bind_values(rank)
      local code = ps:step()
      if code == sqlite.DONE then
         return true, "Rank '" .. rank .. "' created"
      elseif code == sqlite.CONSTRAINT then
         return false, "Rank '" .. rank .. "' already exists"
      else
         log_error()
         return false, "SQLite error code " .. tostring(code) .. ": See server logs"
      end
   end)
   
   cmd:sub("rename rank :old :new", function(name, old, new)
      local ps = db:prepare("UPDATE ranks SET name=:new WHERE name=:old")
      ps:bind_values(new, old)
      local code = ps:step()
      if code == sqlite.DONE then
         if db:changes() == 0 then
            return false, "No such rank '" .. old .. "'"
         else
            return true, "Rank '" .. old .. "' renamed to '" .. new .. "'"
         end
      elseif code == sqlite.CONSTRAINT then
         return false, "There is already a rank named '" .. new .. "'"
      else
         log_error()
         return false, "SQLite error code " .. tostring(code) .. ": See server logs"
      end
   end)
   
   cmd:sub("remove rank :rank", function(name, rank)
      local ps = db:prepare("DELETE FROM ranks WHERE name=:rank")
      ps:bind_values(rank)
      local code = ps:step()
      if code == sqlite.DONE then
         if db:changes() == 0 then
            return false, "No such rank '" .. rank .. "'"
         else
            return true, "Removed rank '" .. rank .. "'" 
         end
      else
         log_error()
         return false, "SQLite error code " .. tostring(code) .. ": See server logs"
      end
   end)
   
   cmd:sub("list ranks", function(name)
      local rtext = ""
      for rank in db:urows("SELECT name FROM ranks") do
         rtext = rtext .. rank .. "\n"
      end
      return true, rtext
   end)
   
   cmd:sub("add staff :name :rank", function(name, staff, rank)
      local ps = db:prepare("SELECT rowid FROM ranks WHERE name=:rank")
      ps:bind_values(rank)
      local ruid = first_row(ps)
      if ruid == nil then
         return false, "No such rank '" .. rank .. "'"
      end
      ruid = ruid.rowid
      local ps = db:prepare("INSERT INTO staff(name, rank_uid) VALUES(:name, :ruid)")
      ps:bind_values(staff, ruid)
      local code = ps:step()
      if code == sqlite.DONE then
         local player = minetest.get_player_by_name(staff)
         if player then
            local tag = format_tag(staff, rank)
            more_monoids.player_tag:add_change(player, tag, "staff")
         end
         return true, "Added staff member '" .. staff .. "' with rank '" .. rank .. "'"
      elseif code == sqlite.CONSTRAINT then
         return false, "'" .. staff .. "' is already a staff member"
      else
          log_error()
         return false, "SQLite error code " .. tostring(code) .. ": See server logs"
      end
   end)
   
   cmd:sub("remove staff :name", function(name, staff)
      local ps = db:prepare("DELETE FROM staff WHERE name=:name")
      ps:bind_values(staff)
      local code = ps:step()
      if code == sqlite.DONE then
         if db:changes() == 0 then
            return false, "No such staff member '" .. staff .. "'"
         else
            return true, "Staff member '" .. staff .. "' removed"
         end
      else
         log_error()
         return false, "SQLite error code " .. tostring(code) .. ": See server logs"
      end
   end)
   
   cmd:sub("list staff", function(name)
      local stext = ""
      for sname, ruid in db:urows("SELECT name,rank_uid FROM staff") do
         local rank = get_rank_by_uid(ruid)
         stext = stext .. sname .. ": " .. rank .. "\n"
      end
      return true, stext
   end)
   
   cmd:sub("help", function (name)
      return true, "Commands:\n" .. 
      "add rank <rank>\n" ..
      "rename rank <rank> <new name>\n" ..
      "remove rank <rank>\n" ..
      "list ranks\n" ..
      "add staff <name> <rank>\n" ..
      "remove staff <name>\n" ..
      "list staff"
   end)
   
end, {
   description = "Modify staff ranks",
   privs = {
      server = true,
   }
})

-- Modify nametag
local name_ps = db:prepare("SELECT name, rank_uid FROM staff WHERE name=:name")

minetest.register_on_joinplayer(function(player)
   local pname = player:get_player_name()
   name_ps:bind_values(pname)
   local fr = first_row(name_ps)
   if fr ~= nil then
      local rank = get_rank_by_uid(fr.rank_uid)
      local tag = format_tag(pname, rank)
      more_monoids.player_tag:add_change(player, tag, "staff")
   else
      more_monoids.player_tag:add_change(player, pname, "staff")
   end
   name_ps:reset()
end)

minetest.register_on_leaveplayer(function(player)
   more_monoids.player_tag:del_change(player, "staff")
end)
