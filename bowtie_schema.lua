local schema = require 'schema'
local json = require 'dkjson'
local utils = require 'schema.utils'

local modnames = {
  ['https://json-schema.org/draft/2020-12/schema'] = 'schema.draft2020-12',
  ['https://json-schema.org/draft/2019-09/schema'] = 'schema.draft2019-09',
  ['http://json-schema.org/draft-07/schema#'] = 'schema.draft-07',
  ['http://json-schema.org/draft-06/schema#'] = 'schema.draft-06',
  ['http://json-schema.org/draft-04/schema#'] = 'schema.draft-04',
}

local skipped1 = {
  ['allOf with base schema'] = 'in a table, a `nil` value means that the key does not exist', -- allOf
  ['const with null'] = 'in a table, a `nil` value means that the key does not exist', -- const
  ['contains with null instance elements'] = 'in a table, a `nil` value means that the key does not exist', -- contains
  ['heterogeneous enum-with-null validation'] = 'in a table, a `nil` value means that the key does not exist', -- enum
  ['items and subitems'] = 'in a table, a `nil` value means that the key does not exist', -- items
  ['pattern with Unicode property escape requires unicode mode'] = 'unicode / PCRE2', -- pattern
  ['patternProperties with Unicode property escape'] = 'unicode / PCRE2', -- patternProperties
}

local skipped2 = setmetatable({
  ['additionalProperties being false does not allow other properties'] = { -- additionalProperties
    ['ignores arrays'] = 'array and object are both represented by a Lua table',
  },
  ['contains keyword validation'] = { -- contains
    ['not array is valid'] = 'array and object are both represented by a Lua table',
  },
  ['maxProperties validation'] = { -- maxProperties
    ['ignores arrays'] = 'array and object are both represented by a Lua table',
  },
  ['minProperties validation'] = { -- minProperties
    ['ignores arrays'] = 'array and object are both represented by a Lua table',
  },
  ['by small number'] = { -- multipleOf
    ['0.0075 is multiple of 0.0001'] = 'Lua modulo',
  },
  ['small multiple of large integer'] = { -- multipleOf
    ['any integer is a multiple of 1e-8'] = 'Lua modulo',
  },
  ['regexes are not anchored by default and are case sensitive'] = { -- patternProperties
    ['recognized members are accounted for'] = 'in a table, a `nil` value means that the key does not exist',
  },
  ['required validation'] = { -- required
    ['ignores arrays'] = 'array and object are both represented by a Lua table',
  },
  ['required properties whose names are Javascript object property names'] = { -- required
    ['ignores arrays'] = 'array and object are both represented by a Lua table',
  },
  ['object type matches objects'] = { -- type
    ['an array is not an object'] = 'array and object are both represented by a Lua table',
  },
  ['array type matches arrays'] = { -- type
    ['an object is not an array'] = 'array and object are both represented by a Lua table',
  },
  ['uniqueItems validation'] = { -- uniqueItems
    ['non-unique heterogeneous types are invalid'] = 'not a Lua sequence',
  },
  ['uniqueItems with an array of items and additionalItems=false'] = { -- uniqueItems
    ['extra items are invalid even if unique'] = 'in a table, a `nil` value means that the key does not exist',
  },
  ['uniqueItems=false with an array of items and additionalItems=false'] = { -- uniqueItems
    ['extra items are invalid even if unique'] = 'in a table, a `nil` value means that the key does not exist',
  },
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

local function resource_pointers(document)
  local pointers = {}
  local walk
  walk = function(node, pointer, base)
    if type(node) ~= 'table' then
      return
    end
    local current = base
    if type(node['$id']) == 'string' then
      current = base ~= '' and utils.resolve_uri(base, node['$id']) or node['$id']
      pointers[current] = pointer
    end
    for key, value in pairs(node) do
      walk(value, pointer .. '/' .. utils.escape_jsonptr(key), current)
    end
  end
  walk(document, '', '')
  return pointers
end

local function keyword_location(absolute, evaluated, pointers)
  local fragment
  if absolute and #absolute > 0 then
    local hash = absolute:find('#', 1, true)
    if hash then
      local base = absolute:sub(1, hash - 1)
      fragment = absolute:sub(hash + 1)
      if #base > 0 and pointers[base] then
        fragment = pointers[base] .. fragment
      end
    else
      fragment = absolute
    end
  else
    fragment = evaluated or ''
  end
  return '#' .. fragment
end

local function keyword_name(location)
  return location:match '[^/]*$'
end

local function bowtie_annotations(result, pointers)
  local annotations = {}
  if not result.valid then
    return annotations
  end
  for _, annotation in ipairs(result.annotations or {}) do
    local location = keyword_location(
      annotation.absoluteKeywordLocation, annotation.keywordLocation, pointers)
    annotations[#annotations + 1] = {
      keyword = keyword_name(location),
      instanceLocation = annotation.instanceLocation or '',
      keywordLocation = location,
      annotation = annotation.annotation,
    }
  end
  return annotations
end

local STARTED = false

local cmds = {
  start = function(request)
    assert(request.version == 1, 'Wrong version!')
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
      require(modname)
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
    local want_annotations = request.output == 'annotations'
    schema.output_format = want_annotations and 'basic' or 'flag'
    local reason = skipped1[case.description]
    local results = {}
    if not reason then
      schema.custom_resolver = function(url)
        if case.registry then
          return case.registry[url]
        end
      end
      local ok, validator = xpcall(schema.new, debug.traceback, case.schema)
      if not ok then
        return {
          errored = true,
          seq = request.seq,
          context = {
            traceback = validator,
          },
        }
      end
      local pointers = want_annotations and resource_pointers(case.schema)
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
          if want_annotations then
            results[i] = {
              valid = result.valid,
              annotations = bowtie_annotations(result, pointers),
            }
          else
            results[i] = {
              valid = result.valid,
            }
          end
        end
      end
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
  local request = json.decode(line)
  local fn = cmds[request.cmd]
  local response = fn(request)
  io.write(json.encode(response) .. '\n')
end
