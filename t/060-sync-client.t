#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use constant PLAN       => 51;
use Test::More tests    => PLAN;
use Encode qw(decode encode);


BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'DR::Tarantool::LLClient', 'tnt_connect';
    use_ok 'DR::Tarantool::StartTest';
    use_ok 'DR::Tarantool', ':constant';
    use_ok 'File::Spec::Functions', 'catfile';
    use_ok 'File::Basename', 'dirname', 'basename';
    use_ok 'AnyEvent';
    use_ok 'DR::Tarantool::SyncClient';
}

my $cfg_dir = catfile dirname(__FILE__), 'test-data';
ok -d $cfg_dir, 'directory with test data';
my $tcfg = catfile $cfg_dir, 'llc-easy2.cfg';
ok -r $tcfg, $tcfg;

my $tnt = run DR::Tarantool::StartTest( cfg => $tcfg );

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
            },
            {
                name    => 'json',
                type    => 'JSON',
            }
        ],
        indexes => {
            0   => 'id',
            1   => 'name',
            2   => [ 'key', 'password' ],
        },
    }
};

SKIP: {
    unless ($tnt->started and !$ENV{SKIP_TNT}) {
        diag $tnt->log unless $ENV{SKIP_TNT};
        skip "tarantool isn't started", PLAN - 9;
    }

    my $client = DR::Tarantool::SyncClient->connect(
        port    => $tnt->primary_port,
        spaces  => $spaces
    );

    isa_ok $client => 'DR::Tarantool::SyncClient';
    ok $client->ping, '* ping';

    my $t = $client->insert(
        first_space => [ 1, 'привет', 2, 'test' ], TNT_FLAG_RETURN
    );

    isa_ok $t => 'DR::Tarantool::Tuple', '* insert tuple packed';
    cmp_ok $t->id, '~~', 1, 'id';
    cmp_ok $t->name, '~~', 'привет', 'name';
    cmp_ok $t->key, '~~', 2, 'key';
    cmp_ok $t->password, '~~', 'test', 'password';

    $t = $client->insert(
        first_space => [ 2, 'медвед', 3, 'test2' ], TNT_FLAG_RETURN
    );

    isa_ok $t => 'DR::Tarantool::Tuple', 'insert tuple packed';
    cmp_ok $t->id, '~~', 2, 'id';
    cmp_ok $t->name, '~~', 'медвед', 'name';
    cmp_ok $t->key, '~~', 3, 'key';
    cmp_ok $t->password, '~~', 'test2', 'password';


    $t = $client->call_lua('box.select' =>
        [ 0, 0, pack 'L<' => 1 ], 'first_space');
    isa_ok $t => 'DR::Tarantool::Tuple', '* call tuple packed';
    cmp_ok $t->id, '~~', 1, 'id';
    cmp_ok $t->name, '~~', 'привет', 'name';
    cmp_ok $t->key, '~~', 2, 'key';
    cmp_ok $t->password, '~~', 'test', 'password';


    $t = $client->select(first_space => 1);
    isa_ok $t => 'DR::Tarantool::Tuple', '* select tuple packed';
    cmp_ok $t->id, '~~', 1, 'id';
    cmp_ok $t->name, '~~', 'привет', 'name';
    cmp_ok $t->key, '~~', 2, 'key';
    cmp_ok $t->password, '~~', 'test', 'password';

    $t = $client->select(first_space => 'привет', 'i1');
    isa_ok $t => 'DR::Tarantool::Tuple', 'select tuple packed (i1)';
    cmp_ok $t->id, '~~', 1, 'id';
    cmp_ok $t->name, '~~', 'привет', 'name';
    cmp_ok $t->key, '~~', 2, 'key';
    cmp_ok $t->password, '~~', 'test', 'password';

    $t = $client->select(first_space => [2, 'test'], 'i2');
    isa_ok $t => 'DR::Tarantool::Tuple', 'select tuple packed (i2)';
    cmp_ok $t->id, '~~', 1, 'id';
    cmp_ok $t->name, '~~', 'привет', 'name';
    cmp_ok $t->key, '~~', 2, 'key';
    cmp_ok $t->password, '~~', 'test', 'password';

    $t = $client->update(first_space => 2 => [ name => set => 'привет1' ]);
    cmp_ok $t, '~~', undef, '* update without flags';
    $t = $client->update(
        first_space => 2 => [ name => set => 'привет медвед' ], TNT_FLAG_RETURN
    );
    isa_ok $t => 'DR::Tarantool::Tuple', 'update with flags';
    cmp_ok $t->name, '~~', 'привет медвед', '$t->name';


    $t = $client->insert(first_space => [1, 2, 3, 4, undef], TNT_FLAG_RETURN);
    cmp_ok $t->json, '~~', undef, 'JSON insert: undef';

    $t = $client->insert(first_space => [1, 2, 3, 4, 22], TNT_FLAG_RETURN);
    cmp_ok $t->json, '~~', 22, 'JSON insert: scalar';

    $t = $client->insert(first_space => [1, 2, 3, 4, 'тест'], TNT_FLAG_RETURN);
    cmp_ok $t->json, '~~', 'тест', 'JSON insert: utf8 scalar';

    $t = $client->insert(
        first_space => [ 1, 2, 3, 4, { a => 'b' } ], TNT_FLAG_RETURN
    );
    isa_ok $t->json => 'HASH', 'JSON insert: hash';
    cmp_ok $t->json->{a}, '~~', 'b', 'JSON insert: hash value';

    $t = $client->insert(
        first_space => [ 1, 2, 3, 4, { привет => 'медвед' } ], TNT_FLAG_RETURN
    );
    isa_ok $t->json => 'HASH', 'JSON insert: hash';
    cmp_ok $t->json->{привет}, '~~', 'медвед', 'JSON insert: hash utf8 value';
}
