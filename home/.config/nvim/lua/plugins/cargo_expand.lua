local M = {}

local sessions = {}

local function set_buffer_lines(buf, lines, filetype)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = filetype
  vim.bo[buf].modifiable = false
end

local function struct_under_cursor(buf)
  local ok, node = pcall(function()
    vim.treesitter.get_parser(buf, "rust"):parse()
    return vim.treesitter.get_node({ bufnr = buf })
  end)
  if not ok then
    return nil
  end

  while node and node:type() ~= "struct_item" do
    node = node:parent()
  end
  if not node then
    return nil
  end

  local name_node = node:field("name")[1]
  if not name_node then
    return nil
  end

  return vim.treesitter.get_node_text(name_node, buf)
end

local function cargo_manifest(path)
  local manifests = vim.fs.find("Cargo.toml", {
    path = vim.fs.dirname(path),
    upward = true,
    type = "file",
  })
  return manifests[1]
end

local function package_name(manifest)
  local ok, lines = pcall(vim.fn.readfile, manifest)
  if not ok then
    return nil
  end

  local in_package = false
  for _, line in ipairs(lines) do
    if line:match("^%s*%[package%]%s*$") then
      in_package = true
    elseif in_package and line:match("^%s*%[") then
      return nil
    elseif in_package then
      local name = line:match('^%s*name%s*=%s*"([^"]+)"')
        or line:match("^%s*name%s*=%s*'([^']+)'")
      if name then
        return name
      end
    end
  end

  return nil
end

local function target_args(manifest, source)
  local root = vim.fs.dirname(manifest)
  local relative = source:sub(#root + 2)

  local bin = relative:match("^src/bin/([^/]+)%.rs$")
    or relative:match("^src/bin/([^/]+)/")
  if bin then
    return { "--bin", bin }
  end

  local example = relative:match("^examples/([^/]+)%.rs$")
    or relative:match("^examples/([^/]+)/")
  if example then
    return { "--example", example }
  end

  local test = relative:match("^tests/([^/]+)%.rs$")
    or relative:match("^tests/([^/]+)/")
  if test then
    return { "--test", test }
  end

  local bench = relative:match("^benches/([^/]+)%.rs$")
    or relative:match("^benches/([^/]+)/")
  if bench then
    return { "--bench", bench }
  end

  if relative == "src/main.rs" or not vim.uv.fs_stat(root .. "/src/lib.rs") then
    local name = package_name(manifest)
    return name and { "--bin", name } or {}
  end

  return { "--lib" }
end

local function cleanup(buf, restore_source)
  local session = sessions[buf]
  if not session then
    return false
  end

  sessions[buf] = nil
  local process = session.process
  session.process = nil
  if process then
    pcall(process.kill, process, 15)
  end

  if restore_source then
    if vim.api.nvim_buf_is_valid(session.source_buf) then
      vim.api.nvim_win_set_buf(0, session.source_buf)
      pcall(vim.api.nvim_win_set_cursor, 0, session.cursor)
    else
      vim.notify("The original Rust buffer no longer exists", vim.log.levels.WARN)
    end

    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end

  return true
end

local function jump_to_struct(buf, name)
  local escaped_name = vim.pesc(name)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for index, line in ipairs(lines) do
    if line:match("%f[%w_]struct%s+" .. escaped_name .. "%f[^%w_]") then
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        pcall(vim.api.nvim_win_set_cursor, win, { index, 0 })
      end
      return
    end
  end
end

local function expand(buf, name)
  local source = vim.api.nvim_buf_get_name(buf)
  if source == "" then
    vim.notify("Save the Rust file before running cargo expand", vim.log.levels.WARN)
    return true
  end

  local manifest = cargo_manifest(source)
  if not manifest then
    vim.notify("No Cargo.toml found for this Rust file", vim.log.levels.ERROR)
    return true
  end

  if vim.bo[buf].modified then
    local saved, err = pcall(vim.cmd.update)
    if not saved then
      vim.notify("Could not save before cargo expand: " .. err, vim.log.levels.ERROR)
      return true
    end
  end

  local expanded_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(expanded_buf, ("[Cargo Expand: %s #%d]"):format(name, expanded_buf))
  vim.bo[expanded_buf].buftype = "nofile"
  vim.bo[expanded_buf].bufhidden = "hide"
  vim.bo[expanded_buf].swapfile = false

  local session = {
    source_buf = buf,
    cursor = vim.api.nvim_win_get_cursor(0),
  }
  sessions[expanded_buf] = session
  vim.api.nvim_create_autocmd({ "BufUnload", "BufWipeout" }, {
    buffer = expanded_buf,
    once = true,
    callback = function()
      cleanup(expanded_buf, false)
    end,
  })

  set_buffer_lines(expanded_buf, { ("// Expanding %s…"):format(name) }, "rust")
  vim.api.nvim_win_set_buf(0, expanded_buf)
  vim.keymap.set("n", "<C-o>", M.toggle, {
    buffer = expanded_buf,
    desc = "Return from cargo expand",
    silent = true,
  })

  local command = {
    "cargo",
    "expand",
    "--color",
    "never",
    "--manifest-path",
    manifest,
  }
  vim.list_extend(command, target_args(manifest, source))

  local completed = false
  local spawned, process = pcall(vim.system, command, {
    cwd = vim.fs.dirname(manifest),
    text = true,
  }, function(result)
    completed = true
    session.process = nil
    vim.schedule(function()
      if sessions[expanded_buf] ~= session or not vim.api.nvim_buf_is_valid(expanded_buf) then
        return
      end

      if result.code ~= 0 then
        local message = result.stderr ~= "" and result.stderr or result.stdout
        set_buffer_lines(expanded_buf, vim.split(message, "\n", { plain = true }), "text")
        vim.notify("cargo expand failed; press Ctrl-O to return", vim.log.levels.ERROR)
        return
      end

      set_buffer_lines(expanded_buf, vim.split(result.stdout, "\n", { plain = true }), "rust")
      jump_to_struct(expanded_buf, name)
    end)
  end)

  if not spawned then
    cleanup(expanded_buf, true)
    vim.notify("Could not start cargo expand: " .. process, vim.log.levels.ERROR)
    return true
  end
  if not completed then
    session.process = process
  end

  return true
end

function M.toggle()
  local buf = vim.api.nvim_get_current_buf()
  if cleanup(buf, true) then
    return true
  end

  if vim.bo[buf].filetype ~= "rust" then
    return false
  end

  local name = struct_under_cursor(buf)
  if not name then
    return false
  end

  return expand(buf, name)
end

return M
