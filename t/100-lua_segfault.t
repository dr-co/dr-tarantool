#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use Test::More tests    => 11;
use Encode qw(decode encode);


BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool', 'tarantool';
    use_ok 'DR::Tarantool::StartTest';
    use_ok 'File::Spec::Functions', 'catfile', 'rel2abs';
    use_ok 'File::Basename', 'dirname';
}

my $dir = rel2abs catfile dirname(__FILE__), 'test-data';
ok -d $dir, "-d $dir";
my $cfg = catfile $dir, 'llc-easy2.cfg';
my $lua = catfile $dir, 'init.lua';

ok -r $cfg, "-r $cfg";
ok -r $lua, "-r $lua";

my $tnt = DR::Tarantool::StartTest->run(cfg => $cfg, script_dir => $dir);
diag $tnt->log unless ok $tnt->started, 'Tarantool was started';


my $spaces = {
    0   => {
        name            => 'first_space',
        fields  => [
            {
                name    => 'id',
                type    => 'NUM',
            },
            {
                name    => 'name',
                type    => 'UTF8STR',
            },
            {
                name    => 'key',
                type    => 'NUM',
            },
            {
                name    => 'password',
                type    => 'STR',
            }
        ],
        indexes => {
            0   => 'id',
            1   => 'name',
            2   => { name => 'tidx', fields => [ 'key', 'password' ] },
        },
    }
};

my $t = tarantool
    host => '127.0.0.1',
    port => $tnt->primary_port,
    spaces => $spaces
;


is_deeply $t->call_lua(test_return => [ 1, 2, 3])->raw, [ 1, 2, 3 ],
    'return one tuple';

is_deeply $t->call_lua(test_return_one => [])->raw, [ 'one' ],
    'return one tuple';

diag $tnt->log unless
    is_deeply $t->call_lua(test_return => [])->raw, [],
        'return empty tuple';
