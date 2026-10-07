local plugin = assert(arg[1], "cargo_expand.lua path is required")

local original_system = vim.system
local original_notify = vim.notify
local original_get_parser = vim.treesitter.get_parser
local original_get_node = vim.treesitter.get_node
local original_get_node_text = vim.treesitter.get_node_text

local notifications = {}
vim.notify = function(message, level)
  table.insert(notifications, { message = message, level = level })
end

local name_node = {}
local struct_node = {
  type = function() return "struct_item" end,
  field = function(_, field) return field == "name" and { name_node } or {} end,
  parent = function() return nil end,
}
vim.treesitter.get_parser = function()
  return { parse = function() end }
end
vim.treesitter.get_node = function() return struct_node end
vim.treesitter.get_node_text = function() return "Widget" end

local function fail(message)
  error(message, 0)
end

local function eq(actual, expected, message)
  if actual ~= expected then
    fail(("%s: expected %s, got %s"):format(message, vim.inspect(expected), vim.inspect(actual)))
  end
end

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/src", "p")
vim.fn.writefile({ "[package]", 'name = "fixture"' }, root .. "/Cargo.toml")
vim.fn.writefile({ "struct Widget;" }, root .. "/src/lib.rs")

local source_index = 0
local function source_buffer()
  source_index = source_index + 1
  local path = ("%s/src/case%d.rs"):format(root, source_index)
  vim.fn.writefile({ "struct Widget;" }, path)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, path)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "struct Widget;" })
  vim.bo[buf].modified = false
  vim.bo[buf].filetype = "rust"
  vim.api.nvim_win_set_buf(0, buf)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return buf
end

local function load_module()
  package.loaded.cargo_expand_test = nil
  return assert(loadfile(plugin))()
end

local function start(kind)
  local callback
  local attempted_buf
  local kills = 0
  local process = {}
  function process:kill(signal)
    eq(signal, 15, "termination signal")
    kills = kills + 1
  end

  vim.system = function(_, _, cb)
    attempted_buf = vim.api.nvim_get_current_buf()
    if kind == "spawn_exception" then
      error("mock spawn failure")
    end
    callback = cb
    return process
  end

  local source = source_buffer()
  local module = load_module()
  eq(module.toggle(), true, "toggle starts expansion")
  if kind ~= "spawn_exception" and not callback then
    fail("vim.system was not called: " .. vim.inspect(notifications))
  end
  return {
    callback = function(result) callback(result) end,
    kills = function() return kills end,
    module = module,
    source = source,
    expanded = attempted_buf,
  }
end

-- 1. Successful completion updates the scratch buffer without cancellation.
do
  local run = start("success")
  run.callback({ code = 0, stdout = "struct Widget { value: u8 }", stderr = "" })
  vim.wait(100, function()
    return vim.api.nvim_buf_get_lines(run.expanded, 0, 1, false)[1]:match("struct Widget") ~= nil
  end)
  eq(run.kills(), 0, "success cancellation count")
  eq(run.module.toggle(), true, "success restore")
  eq(vim.api.nvim_get_current_buf(), run.source, "success restores source")
end

-- 2. A normal command failure remains visible in the expansion buffer.
do
  notifications = {}
  local run = start("callback_failure")
  run.callback({ code = 1, stdout = "", stderr = "expand failed" })
  vim.wait(100, function()
    return vim.api.nvim_buf_get_lines(run.expanded, 0, 1, false)[1] == "expand failed"
  end)
  eq(vim.bo[run.expanded].filetype, "text", "failure filetype")
  eq(#notifications, 1, "failure notification count")
  run.module.toggle()
end

-- 3. A synchronous spawn exception restores the source and removes the scratch buffer.
do
  notifications = {}
  local run = start("spawn_exception")
  eq(vim.api.nvim_get_current_buf(), run.source, "spawn exception restores source")
  eq(vim.api.nvim_buf_is_valid(run.expanded), false, "spawn exception deletes scratch buffer")
  eq(#notifications, 1, "spawn exception notification count")
end

-- 4. :bdelete/BufUnload cancels once without cleanup changing the selected window.
do
  local run = start("delete")
  vim.cmd("bdelete")
  eq(run.kills(), 1, "BufUnload cancellation count")
  local selected = vim.api.nvim_get_current_buf()
  run.callback({ code = 0, stdout = "late", stderr = "" })
  vim.wait(20)
  eq(run.kills(), 1, "late callback cancellation count")
  eq(vim.api.nvim_get_current_buf(), selected, "automatic cleanup leaves selected window alone")
end

-- 5. Explicit toggle cancellation restores the source and kills exactly once.
do
  local run = start("toggle")
  eq(run.module.toggle(), true, "explicit cancellation")
  eq(run.kills(), 1, "explicit cancellation count")
  eq(vim.api.nvim_get_current_buf(), run.source, "explicit cancellation restores source")
end

-- 6. BufWipeout ignores a delayed callback and performs no buffer writes/notifications.
do
  notifications = {}
  local run = start("wipeout")
  vim.api.nvim_buf_delete(run.expanded, { force = true })
  eq(run.kills(), 1, "BufWipeout cancellation count")
  run.callback({ code = 1, stdout = "", stderr = "late failure" })
  vim.wait(20)
  eq(run.kills(), 1, "BufWipeout late callback cancellation count")
  eq(#notifications, 0, "late callback notification count")
end

vim.system = original_system
vim.notify = original_notify
vim.treesitter.get_parser = original_get_parser
vim.treesitter.get_node = original_get_node
vim.treesitter.get_node_text = original_get_node_text
vim.fn.delete(root, "rf")
print("ok: 6 cargo_expand cases")
