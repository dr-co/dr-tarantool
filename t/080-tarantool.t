#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use constant PLAN       => 15;
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
    use_ok 'DR::Tarantool', ':all';
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

    my $client = tarantool(
        port    => $tnt->primary_port,
        spaces  => $spaces
    );

    isa_ok $client => 'DR::Tarantool::SyncClient';
    ok $client->ping, '* tarantool ping';

    # connect
    for my $cv (condvar AnyEvent) {
        DR::Tarantool::AsyncClient->connect(
            port                    => $tnt->primary_port,
            reconnect_period        => 0.1,
            spaces                  => $spaces,
            cb      => sub {
                $client = shift;
                $cv->send;
            }
        );

        $cv->recv;
    }
    unless ( isa_ok $client => 'DR::Tarantool::AsyncClient' ) {
        diag eval { decode utf8 => $client } || $client;
        last;
    }


    # ping
    for my $cv (condvar AnyEvent) {
        $client->ping(
            sub {
                my ($status) = @_;
                cmp_ok $status, '~~', 'ok', '* async_tarantool ping';
                $cv->send;
            }
        );
        $cv->recv;
    }

    $client = coro_tarantool
        port    => $tnt->primary_port,
        spaces  => $spaces
    ;
    isa_ok $client => 'DR::Tarantool::CoroClient';
    ok $client->ping, '* coro_tarantool ping';
}

