require 'optparse'
require 'pg'
require 'set'

postgres_host = nil
postgres_port = nil
postgres_user = nil
postgres_database = 'postgres'

indent_level = 0

OptionParser.new do |opts|
  opts.banner = "Usage: #$PROGRAM_NAME [options]"

  opts.on('-HHOST', '--host=HOST', 'Postgres hostname') do |host|
    postgres_host = host
  end
  opts.on('-pPORT', '--port=PORT', 'Postgres port') do |port|
    postgres_port = Integer(port)
  end
  opts.on('-uUSER', '--user=USER', 'Postgres user') do |user|
    postgres_user = user
  end
  opts.on('-dDATABASE', '--database=DATABASE', 'Postgres database') do |db|
    postgres_database = db
  end
  opts.on('-iLEVEL', '--indent=LEVEL', 'Indent level') do |indent|
    indent_level = Integer(indent)
  end
end.parse!

INDENT = (' ' * indent_level).freeze

def iputs(level, *args)
  print(INDENT)
  print(' ' * level) unless level == 0
  puts(*args)
end

pg = PG::Connection.open(host: postgres_host, port: postgres_port, user: postgres_user, dbname: postgres_database)
types = pg.exec(<<-SQL)
  SELECT
    -- get e.g. 'timestamp with time zone' instead of 'timestamptz'
    format_type(t.oid, NULL) AS name,
    t.typname AS typname,
    t.typcategory AS typcategory
  FROM pg_type t
  WHERE
    -- exclude composite and pseudotypes
    t.typtype NOT IN ('c', 'p')
    -- exclude invisible types
    AND pg_type_is_visible(t.oid)
    -- exclude 'element' types
    AND NOT EXISTS(SELECT 1 FROM pg_catalog.pg_type el WHERE el.oid = t.typelem AND el.typarray = t.oid)
  ORDER BY name
SQL

# add types to this list if the test table needs to explicitly specify the
# length of the type
BOUNDED_LENGTH_TYPES = Set[*%w(
  bit
  character
)]

# add types to this list if they're too obscure to bother filing an issue for
# not supporting them (e.g. Postgres internals)
INTERNAL_TYPES = Set[*%w(
  abstime
  "char"
  name
  pg_node_tree
  regclass
  regconfig
  regdictionary
  regoper
  regoperator
  regproc
  regprocedure
  regtype
  reltime
  txid_snapshot
  unknown
  xid
)]

# add types to this list when their lack of support is documented, preferably
# in the form of a Github issue
KNOWN_BUGS = {
  'numeric' => ['replaced by zero', 'https://github.com/confluentinc/bottledwater-pg/issues/4'],
}

# only use this list during development, otherwise file an issue!
UNKNOWN_BUGS = {
}

def print_examples(level, type)
  name = type.fetch('name')

  if INTERNAL_TYPES.include?(name)
    iputs level, %(example('internal type not supported') {})
    return
  end

  if info = KNOWN_BUGS[name]
    problem, url = info
    iputs level, %(before :example do)
    iputs level, %(  known_bug #{problem.inspect}, #{url.inspect})
    iputs level, %(end)
    puts
    # fall through
  elsif problem = UNKNOWN_BUGS[name]
    iputs level, %(before :example do)
    iputs level, %(  xbug #{problem.inspect})
    iputs level, %(end)
    puts
    # fall through
  end

  # see http://www.postgresql.org/docs/9.5/static/catalog-pg-type.html#CATALOG-TYPCATEGORY-TABLE
  case type.fetch('typcategory')
  when 'B' # boolean
    iputs level,   %(include_examples 'roundtrip type', #{name.inspect}, true)
  when 'V' # bit-string
    if BOUNDED_LENGTH_TYPES.include?(name)
      value = '1110'
      length = value.size
      iputs level, %(include_examples 'bit-string type', #{name.inspect}, #{value.inspect}, #{length})
    else
      iputs level, %(include_examples 'bit-string type', #{name.inspect})
    end
  when 'N' # numeric
    iputs level,   %(include_examples 'numeric type', #{name.inspect})
  when 'S' # string
    if BOUNDED_LENGTH_TYPES.include?(name)
      value = 'Hello'
      length = value.size
      iputs level, %(include_examples 'string type', #{name.inspect}, #{value.inspect}, #{length})
    else
      iputs level, %(include_examples 'string type', #{name.inspect})
    end
  when 'D' # date/time
    iputs level,   %(include_examples #{name.inspect})
  else
    iputs level,   %(pending('should have specs') { fail 'spec not yet implemented' })
  end
end

iputs 0,     ('#' * 80)
iputs 0,     %(### This file is automatically generated by #$PROGRAM_NAME)
iputs 0,     %(### It is intended to be human readable (hence being checked into Git), but)
iputs 0,     %(### not manually edited.)
iputs 0,     %(### This is to make it easier to maintain tests for all supported Postgres)
iputs 0,     %(### types, even as extensions or new Postgres versions add new types.)
iputs 0,     ('#' * 80)
puts
iputs 0,     %(shared_examples 'type specs' do)
puts
types.each do |type|
  name = type.fetch('name')

  iputs 0,   %(  describe '#{name}' do)
  print_examples(4, type)
  iputs   0, %(  end)
  puts
end
iputs 0,     %(end)
