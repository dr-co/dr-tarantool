#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);
use lib qw(blib/lib blib/arch ../blib/lib ../blib/arch);

use constant PLAN       => 72;
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
}

my $cfg_dir = catfile dirname(__FILE__), 'test-data';
ok -d $cfg_dir, 'directory with test data';
my $tcfg = catfile $cfg_dir, 'llc-easy.cfg';
ok -r $tcfg, $tcfg;

my $tnt = run DR::Tarantool::StartTest( cfg => $tcfg );

SKIP: {
    unless ($tnt->started and !$ENV{SKIP_TNT}) {
        diag $tnt->log unless $ENV{SKIP_TNT};
        skip "tarantool isn't started", PLAN - 8;
    }

    my $client;

    # connect
    for my $cv (condvar AnyEvent) {
        DR::Tarantool::LLClient->connect(
            port                    => $tnt->primary_port,
            reconnect_period        => 0.1,
            cb      => sub {
                $client = shift;
                $cv->send;
            }
        );

        $cv->recv;
    }
    unless ( isa_ok $client => 'DR::Tarantool::LLClient' ) {
        diag eval { decode utf8 => $client } || $client;
        last;
    }

    # ping
    for my $cv (condvar AnyEvent) {
        $client->ping(
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* ping reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_PING, 'type';
                $cv->send;
            }
        );
        $cv->recv;
    }

    # insert
    for my $cv (condvar AnyEvent) {
        my $cnt = 3;
        $client->insert(
            0,
            [ pack('L<', 1), 'abc', pack 'L<', 1234 ],
            TNT_FLAG_RETURN,
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* insert reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_INSERT, 'type';

                cmp_ok $res->{tuples}[0][0], '~~', pack('L<', 1), 'key';
                cmp_ok $res->{tuples}[0][1], '~~', 'abc', 'f1';

                $cv->send if --$cnt == 0;

            }
        );

        $client->insert(
            0,
            [ pack('L<', 2), 'cde', pack 'L<', 4567 ],
            TNT_FLAG_RETURN,
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, 'insert reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_INSERT, 'type';

                cmp_ok $res->{tuples}[0][0], '~~', pack('L<', 2), 'key';
                cmp_ok $res->{tuples}[0][1], '~~', 'cde', 'f1';

                $cv->send if --$cnt == 0;

            }
        );
        $client->insert(
            0,
            [ pack('L<', 1), 'aaa', pack 'L<', 1234 ],
            TNT_FLAG_RETURN | TNT_FLAG_ADD,
            sub {
                my ($res) = @_;
                cmp_ok $res->{code} & 0x00002002, '~~', 0x00002002,
                    'insert reply code (already exists)';
                cmp_ok $res->{status}, '~~', 'error', 'status';
                cmp_ok $res->{type}, '~~', TNT_INSERT, 'type';
                like $res->{errstr}, qr{already exists}, 'errstr';
                $cv->send if --$cnt == 0;
            }
        );
        $cv->recv;
    }


    # select
    for my $cv (condvar AnyEvent) {
        my $cnt = 2;
        $client->select(
            0, # ns
            0, # idx
            [ [ pack 'L<', 1 ], [ pack 'L<', 2 ] ],
            2, # limit
            0, # offset
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* select reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_SELECT, 'type';

                cmp_ok
                    scalar(grep { $_->[1] ~~ 'abc' } @{ $res->{tuples} }),
                    '~~',
                    1,
                    'first tuple'
                ;
                cmp_ok
                    scalar(grep { $_->[1] ~~ 'cde' } @{ $res->{tuples} }),
                    '~~',
                    1,
                    'second tuple'
                ;
                $cv->send if --$cnt == 0;
            }
        );

        $client->select(
            0, #ns
            0, #idx
            [ [ pack 'L<', 3 ], [ pack 'L<', 4 ] ],
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, 'select reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_SELECT, 'type';

                ok !@{ $res->{tuples} }, 'empty response';
                $cv->send if --$cnt == 0;
            }
        );
        $cv->recv;
    }

    # update
    for my $cv (condvar AnyEvent) {
        my $cnt = 2;
        $client->update(
            0, # ns
            [ pack 'L<', 1 ], # keys
            [
                [ 1 => set      => 'abcdef' ],
                [ 1 => substr   => 2, 2, ],
                [ 1 => substr   => 100, 1, 'tail' ],
                [ 2 => 'delete' ],
                [ 2 => insert   => pack 'L<' => 123 ],
                [ 3 => insert   => 'third' ],
                [ 4 => insert   => 'fourth' ],
            ],
            TNT_FLAG_RETURN, # flags
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* update reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_UPDATE, 'type';

                cmp_ok $res->{tuples}[0][1], '~~', 'abeftail',
                    'updated tuple 1';
                cmp_ok $res->{tuples}[0][2], '~~', (pack 'L<', 123),
                    'updated tuple 2';
                cmp_ok $res->{tuples}[0][3], '~~', 'third', 'updated tuple 3';
                cmp_ok $res->{tuples}[0][4], '~~', 'fourth', 'updated tuple 4';
                $cv->send if --$cnt == 0;
            }
        );

        $client->update(
            0, # ns
            [ pack 'L<', 2 ], # keys
            [
                [ 1 => set      => 'abcdef' ],
                [ 2 => or       => 23 ],
                [ 2 => and      => 345 ],
                [ 2 => xor      => 744 ],
            ],
            TNT_FLAG_RETURN, # flags
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* update reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_UPDATE, 'type';

                cmp_ok $res->{tuples}[0][1], '~~', 'abcdef',
                    'updated tuple 1';
                cmp_ok
                    $res->{tuples}[0][2],
                    '~~',
                    (pack 'L<', ( (4567 | 23) & 345 ) ^ 744 ),
                    'updated tuple 2'
                ;
                $cv->send if --$cnt == 0;
            }
        );

        $cv->recv;

    }



    # delete
    for my $cv (condvar AnyEvent) {
        my $cnt = 2;
        $client->delete(
            0, # ns
            [ pack 'L<', 1 ], # keys
            TNT_FLAG_RETURN, # flags
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* delete reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_DELETE, 'type';

#                 cmp_ok $res->{tuples}[0][1], '~~', 'abeftail',
#                     'deleted tuple 1';
#                 cmp_ok $res->{tuples}[0][2], '~~', (pack 'L<', 123),
#                     'deleted tuple 2';
#                 cmp_ok $res->{tuples}[0][3], '~~', 'third', 'deleted tuple 3';
#                 cmp_ok $res->{tuples}[0][4], '~~', 'fourth', 'deleted tuple 4';
                $cv->send if --$cnt == 0;
            }
        );

        $client->select(
            0, # ns
            0, # idx
            [ [ pack 'L<', 1 ], [ pack 'L<', 1 ] ],
            sub {
                my ($res) = @_;
                cmp_ok $res->{code}, '~~', 0, '* select reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_SELECT, 'type';

                ok !@{ $res->{tuples} }, 'really removed';
                $cv->send if --$cnt == 0;
            }
        );

        $cv->recv;
    }

    # call
    for my $cv (condvar AnyEvent) {
        my $cnt = 1;
        $client->call_lua(
            'box.select' => [ 0, 0, pack 'L<', 2 ],
            0,
            sub {
                my ($res) = @_;

                cmp_ok $res->{code}, '~~', 0, '* call reply code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_CALL, 'type';
                cmp_ok $res->{tuples}[0][1], '~~', 'abcdef',
                    'updated tuple 1';
                cmp_ok
                    $res->{tuples}[0][2],
                    '~~',
                    (pack 'L<', ( (4567 | 23) & 345 ) ^ 744 ),
                    'updated tuple 2'
                ;
                $cv->send if --$cnt == 0;
            }
        );
        $cv->recv;
    }

    # memory leak (You have touse external tool to watch memory)
    if ($ENV{DRV_LEAK_TEST}) {
        for my $cv (condvar AnyEvent) {

            my $cnt = 1000000;

            my $tmr;
            $tmr = AE::timer 0.0001, 0.0001 => sub {
                $client->call_lua(
                    'box.select' => [ 0, 0, pack 'L<', 2 ],
                    0,
                    sub {
                        if (--$cnt == 0) {
                            $cv->send;
                            undef $tmr;
                        }
                    }
                );
                DR::Tarantool::LLClient->connect(
                    port                    => $tnt->primary_port,
                    reconnect_period        => 100,
                    cb      => sub {
                        if (--$cnt == 0) {
                            $cv->send;
                            undef $tmr;
                        }
                    }
                );
            };

            $cv->recv;
        }
    }


    $client->_fatal_error('abc');
    ok !$client->is_connected, 'disconnected';
    for my $cv (condvar AnyEvent) {
        my $tmr;
        $tmr = AE::timer 0.5, 0, sub { undef $tmr; $cv->send };
        $cv->recv;
    }

    ok $client->is_connected, 'reconnected';

    # call after reconnect
    for my $cv (condvar AnyEvent) {
        my $cnt = 1;
        $client->call_lua(
            'box.select' => [ 0, 0, pack 'L<', 2 ],
            0,
            sub {
                my ($res) = @_;

                cmp_ok $res->{code}, '~~', 0, '* call after reconnect code';
                cmp_ok $res->{status}, '~~', 'ok', 'status';
                cmp_ok $res->{type}, '~~', TNT_CALL, 'type';
                cmp_ok $res->{tuples}[0][1], '~~', 'abcdef', 'tuple 1';
                $cv->send if --$cnt == 0;
            }
        );
        $cv->recv;
    }

    $tnt->kill;

    # socket error
    for my $cv (condvar AnyEvent) {
        my $cnt = 1;
        $client->call_lua(
            'box.select' => [ 0, 0, pack 'L<', 2 ],
            0,
            sub {
                my ($res) = @_;

                cmp_ok $res->{status}, '~~', 'fatal', '* fatal status';
                like $res->{errstr} => qr{Socket error}, 'Error string';
                $cv->send if --$cnt == 0;
            }
        );

        $cv->recv;
    }

    for my $cv (condvar AnyEvent) {
        my $cnt = 1;
        $client->call_lua(
            'box.select' => [ 0, 0, pack 'L<', 2 ],
            0,
            sub {
                my ($res) = @_;

                cmp_ok $res->{status}, '~~', 'fatal', '* fatal status';
                like $res->{errstr} => qr{Connection isn't established},
                    'Error string';
                $cv->send if --$cnt == 0;
            }
        );

        $cv->recv;
    }


    # connect to shotdowned tarantool
    for my $cv (condvar AnyEvent) {
        DR::Tarantool::LLClient->connect(
            port                    => $tnt->primary_port,
            reconnect_period        => 0,
            cb      => sub {
                $client = shift;
                $cv->send;
            }
        );

        $cv->recv;
    }
    ok !ref $client, 'First unsuccessful connect';

    for my $cv (condvar AnyEvent) {
        DR::Tarantool::LLClient->connect(
            port                    => $tnt->primary_port,
            reconnect_period        => 100,
            cb      => sub {
                $client = shift;
                $cv->send;
            }
        );

        $cv->recv;
    }
    ok !ref $client, 'First unsuccessful connect without repeats';

    {
        my $done_reconnect = 0;
        for my $cv (condvar AnyEvent) {
            DR::Tarantool::LLClient->connect(
                port                    => $tnt->primary_port,
                reconnect_period        => .1,
                reconnect_always        => 1,
                cb      => sub {
                    $done_reconnect++;
                }
            );

            my $timer;
            $timer = AE::timer .5, 0 => sub {
                undef $timer;
                $cv->send;
            };

            $cv->recv;
        }
        ok !$done_reconnect, 'reconnect_always option';
    }
}
