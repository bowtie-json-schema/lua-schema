local json = require 'dkjson'
local null = io.stderr

local function setup(modname, registry)
  local schema = require 'schema'
  if modname then
    require(modname)
  end
  schema.json.null = null
  schema.json.is_array = function(data)
    if type(data) == 'table' then
      local mt = getmetatable(data)
      if not mt or mt.__jsontype == 'array' then
        return true
      end
    end
    return false
  end
  schema.json.is_object = function(data)
    if type(data) == 'table' then
      local mt = getmetatable(data)
      if not mt or mt.__jsontype == 'object' then
        return true
      end
    end
    return false
  end
  schema.custom_resolver = function(url)
    if registry then
      return registry[url]
    end
  end
  return schema
end

local function teardown()
end

local modnames = {
  ['https://json-schema.org/draft/2020-12/schema'] = 'schema.dialect.draft2020-12',
  ['https://json-schema.org/draft/2019-09/schema'] = 'schema.dialect.draft2019-09',
  ['http://json-schema.org/draft-07/schema#'] = 'schema.dialect.draft-07',
  ['http://json-schema.org/draft-06/schema#'] = 'schema.dialect.draft-06',
  ['http://json-schema.org/draft-04/schema#'] = 'schema.dialect.draft-04',
}

local skipped1 = {
  ['pattern with Unicode property escape requires unicode mode'] = 'unicode / PCRE2', -- pattern
  ['patternProperties with Unicode property escape'] = 'unicode / PCRE2', -- patternProperties
}

local skipped2 = setmetatable({
}, {
  __index = function()
    return {}
  end,
})

local function exec(cmd)
  local f = io.popen(cmd)
  local line = f:read '*l'
  f:close()
  return line
end

local STARTED = false
local DIALECT

local cmds = {
  start = function(request)
    assert(request.version == 1, 'Wrong version!')
    local schema = require 'schema'
    STARTED = true
    return {
      version = 1,
      implementation = {
        name = schema._NAME,
        version = schema._VERSION,
        homepage = 'https://fperrad.frama.io/lua-schema',
        issues = 'https://framagit.org/fperrad/lua-schema/-/issues',
        source = 'https://framagit.org/fperrad/lua-schema',
        dialects = {
          'https://json-schema.org/draft/2020-12/schema',
          'https://json-schema.org/draft/2019-09/schema',
          'http://json-schema.org/draft-07/schema#',
          'http://json-schema.org/draft-06/schema#',
          'http://json-schema.org/draft-04/schema#',
        },
        language = 'lua',
        language_version = _VERSION:match '^%S+%s+(%S+)',
        os = exec 'lsb_release -is',
        os_version = exec 'lsb_release -rs',
      },
    }
  end,
  dialect = function(request)
    assert(STARTED, 'Not started!')
    local modname = modnames[request.dialect]
    if modname then
      DIALECT = modname
      return {
        ok = true,
      }
    else
      return {
        ok = false,
      }
    end
  end,
  run = function(request)
    assert(STARTED, 'Not started!')
    local case = request.case
    local reason = skipped1[case.description]
    local results = {}
    if not reason then
      local schema = setup(DIALECT, case.registry)
      local ok, validator = xpcall(schema.new, debug.traceback, case.schema)
      if not ok then
        teardown()
        return {
          errored = true,
          seq = request.seq,
          context = {
            traceback = validator,
          },
        }
      end
      for i = 1, #case.tests do
        local test = case.tests[i]
        reason = skipped2[case.description][test.description]
        if reason then
          results[i] = {
            skipped = true,
            message = reason,
          }
        else
          local result = validator:validate(test.instance)
          results[i] = {
            valid = result.valid,
          }
        end
      end
      teardown()
    else
      for i = 1, #case.tests do
        results[i] = {
          skipped = true,
          message = reason,
        }
      end
    end
    return {
      seq = request.seq,
      results = results,
    }
  end,
  stop = function()
    assert(STARTED, 'Not started!')
    os.exit(0)
  end,
}

io.stdout:setvbuf 'no'
for line in io.lines() do
  local request = json.decode(line, 1, null)
  local fn = cmds[request.cmd]
  local response = fn(request)
  io.write(json.encode(response) .. '\n')
end
